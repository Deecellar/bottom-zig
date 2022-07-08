const std = @import("std");
const bottom = @import("encoder.zig").BottomEncoder;
const ByteEnum = @import("encoder.zig").ByteEnum;
const mem = @import("zig-native-vector");
const help_text = @embedFile("help.txt");

pub const DecoderError = error{
    invalid_input,
} || std.mem.Allocator.Error;

/// This struct is just a namespace for the decoder
pub const BottomDecoder = struct {
    const decodeHash = GetDecodeHash();
    pub fn decodeAlloc(str: []const u8, allocator: std.mem.Allocator) DecoderError![]u8 {
        var len = @maximum(std.math.divCeil(usize, str.len, bottom.max_expansion_per_byte) catch str.len, 40);
        var memory = try allocator.alloc(u8, (len - 1) * 2);
        errdefer allocator.free(memory);
        return decode(str, memory);
    }

    pub fn decode(str: []const u8, buffer: []u8) ![]u8 {
        var iter = std.mem.split(u8, str, "👉👈");
        var index: usize = 0;
        while (iter.next()) |owo| {
            if (owo.len == 0) {
                break;
            }
            buffer[index] = decodeByte(owo) orelse return error.invalid_input;
            index += 1;
        }
        return buffer[0..index];
    }
    const ListType = struct { @"0": []const u8, @"1": u8 };
    fn GetDecodeHash() type {
        var list: [256]ListType = undefined;
        inline for (list) |*v, index| {
            v.* = getByte(index);
        }
        return std.ComptimeStringMap(u8, list);
    }

    fn getByte(comptime a: u8) ListType {
        @setEvalBranchQuota(10000000);
        comptime {
            var buffer: [40]u8 = std.mem.zeroes([40]u8);
            _ = bottom.encodeByte(a, &buffer);
            return .{ .@"0" = buffer[0..40], .@"1" = a };
        }
    }
    pub fn decodeByte(byte: []const u8) ?u8 {
        var res: [40]u8 = comptime std.mem.zeroes([40]u8);
        var text = "👉👈";
        if (byte.len > 40) return null;
        @memcpy(res[0..], byte.ptr, byte.len); // This is less than 40 always
        @memcpy(res[byte.len..].ptr, text, text.len); // There is always enough space
        var result = decodeHash.get(&res);
        return result;
    }
};
test "decoder works" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, decoderWorks, .{});
}

fn decoderWorks(allocator: std.mem.Allocator) !void {
    if (@import("builtin").os.tag == .windows) {
        if (std.os.windows.kernel32.SetConsoleOutputCP(65001) == 0) {
            return error.console_not_support_utf8;
        }
    }
    const @"😈" = "💖💖,,,,👉👈💖💖,👉👈💖💖🥺,,,👉👈💖💖🥺,,,👉👈💖💖✨,👉👈✨✨✨,,👉👈💖💖✨🥺,,,,👉👈💖💖✨,👉👈💖💖✨,,,,👉👈💖💖🥺,,,👉👈💖💖👉👈✨✨✨,,,👉👈";
    const res = try BottomDecoder.decodeAlloc(@"😈", allocator);
    defer allocator.free(res);
    try std.testing.expectEqualStrings("hello world!", res);
}

test "All bytes possible values are decodable" {
    var byte: u8 = @truncate(u8, 0);
    var buffer: [40]u8 = comptime std.mem.zeroes([40]u8);
    var encode: []u8 = undefined;
    var result: u8 = undefined;
    for (@as([256]u0, undefined)) |_, index| {
        byte = @truncate(u8, index);
        encode = bottom.encodeByte(byte, &buffer);
        result = BottomDecoder.decodeByte(encode[0 .. encode.len - 8]) orelse {
            std.log.err("Error", .{});
            std.log.err("value of byte: {d} unexpected", .{byte});
            std.log.err("value of byte encoded: {s} unexpected", .{encode});
            return error.invalid_input;
        };
        try std.testing.expectEqual(byte, result);
    }
}

test "All bytes decodeable in decode" {
    var byte: u8 = @truncate(u8, 0);
    var buffer: [40]u8 = comptime std.mem.zeroes([40]u8);
    var encode: []u8 = undefined;
    var result: []u8 = undefined;
    for (@as([256]u0, undefined)) |_, index| {
        byte = @truncate(u8, index);
        encode = bottom.encodeByte(byte, &buffer);
        result = BottomDecoder.decode(encode, &buffer) catch |err| {
            std.log.err("Error {}", .{err});
            std.log.err("value of byte: {d} unexpected", .{byte});
            std.log.err("value of byte encoded: {s} unexpected", .{encode});
            return err;
        };
        try std.testing.expectEqual(byte, result[0]);
    }
}

test "All bytes decodeable in decodeAlloc" {
    std.testing.checkAllAllocationFailures(std.testing.allocator, allocAllBytesReachable, .{}) catch |err| {
        if (err == error.NondeterministicMemoryUsage) {
            return;
        } else return err;
    };
}

fn allocAllBytesReachable(allocator: std.mem.Allocator) !void {
    var byte: u8 = @truncate(u8, 0);
    var buffer: [40]u8 = undefined;
    var encode: []u8 = undefined;
    var result: []u8 = undefined;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    for (@as([256]u0, undefined)) |_, index| {
        byte = @truncate(u8, index);
        encode = bottom.encodeByte(byte, &buffer);
        result = BottomDecoder.decodeAlloc(encode, arena.allocator()) catch |err| {
            if (err == error.OutOfMemory) {
                return err; // We don't want to die on out of memory, poor people that did have a problem with this
            }
            std.log.err("Error {}", .{err});
            std.log.err("value of byte: {d} unexpected", .{byte});
            std.log.err("value of byte encoded: {s} unexpected", .{encode});
            return err;
        };
        try std.testing.expectEqual(byte, result[0]);
    }
}

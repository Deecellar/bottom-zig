//! # Bottom Text Decoder Module
//!
//! Provides functionality to decode bottom-encoded text back into regular UTF-8.
//! 
//! ## Implementation Details
//! The decoder uses a hash table lookup system to efficiently map encoded sequences
//! back to their original byte values.

const std = @import("std");
const bottom = @import("encoder.zig").BottomEncoder;
const ByteEnum = @import("encoder.zig").ByteEnum;

/// ## Error Types
/// Represents possible errors during decoding:
/// - `invalid_input`: Input string contains invalid bottom encoding
/// - Any allocation errors from `std.mem.Allocator`
pub const DecoderError = error{
    invalid_input,
} || std.mem.Allocator.Error;

/// # Bottom Decoder
/// Main decoder namespace containing all decoding functionality
pub const BottomDecoder = struct {
    /// ## Decode with Allocation
    /// Decodes a bottom-encoded string, allocating memory for the result
    /// 
    /// ### Parameters
    /// - `str`: The bottom-encoded input string
    /// - `allocator`: Memory allocator to use for the result
    /// 
    /// ### Returns
    /// Allocated slice containing decoded bytes
    pub fn decodeAlloc(str: []const u8, allocator: std.mem.Allocator) DecoderError![]u8 {
        const len = std.mem.count(u8, str, "👉👈");
        const memory = try allocator.alloc(u8, len);
        errdefer allocator.free(memory);
        return decode(str, memory);
    }

    /// ## Decode to Buffer
    /// Decodes a bottom-encoded string into a provided buffer
    /// 
    /// ### Parameters
    /// - `str`: The bottom-encoded input string 
    /// - `buffer`: Pre-allocated buffer to store the result
    /// 
    /// ### Returns
    /// Slice of the buffer containing decoded bytes
    pub fn decode(str: []const u8, buffer: []u8) ![]u8 {
        @setRuntimeSafety(false);
        var iter = std.mem.splitSequence(u8, str, "👉👈");
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

    /// ## Lookup Table
    /// Pre-computed lookup table for byte decoding
    const data = getByteData();

    /// ## Decode Single Byte
    /// Decodes a single bottom-encoded byte sequence
    /// 
    /// ### Parameters
    /// - `byte`: Bottom-encoded sequence representing a single byte
    /// 
    /// ### Returns
    /// Decoded byte value, or null if invalid
    pub fn decodeByte(byte: []const u8) ?u8 {
        @setRuntimeSafety(false);
        var res: [40]u8 = comptime std.mem.zeroes([40]u8);
        const text = "👉👈";
        if (byte.len > 40) return null;
        if (byte.len > 40) unreachable;

        @memcpy(res[0..byte.len], byte[0..byte.len]); // This is less than 40 always
        @memcpy(res[byte.len..40], text); // There is always enough space
        const result = std.mem.indexOfScalar(u64, &data, std.hash.XxHash64.hash(0, &res));
        return @as(u8, @intCast(result orelse return null));
    }

    /// ## Hash Table Generator
    /// Generates lookup table for byte decoding at comptime
    /// 
    /// ### Implementation Details
    /// - Creates a table of 256 pre-computed hashes
    /// - Validates there are no hash collisions
    /// 
    /// ### Returns
    /// Array of 256 pre-computed hashes
    pub fn getByteData() [256]u64 {
        @setEvalBranchQuota(100000000);
        var buffer_data: [256]u64 = undefined;
        var buffer: [40]u8 = comptime std.mem.zeroes([40]u8);
        for (0..256) |index| {
            buffer = comptime std.mem.zeroes([40]u8);
            _ = bottom.encodeByte(@intCast(index), &buffer);
            const dat = std.hash.XxHash64.hash(0, &buffer);
            buffer_data[index] = dat;
        }
        for (buffer_data, 0..) |b, index_1| {
            for (buffer_data, 0..) |c, index_2| {
                if (index_1 == index_2 or b != c) continue;
                var buffer_one: [40]u8 = comptime std.mem.zeroes([40]u8);
                var buffer_two: [40]u8 = comptime std.mem.zeroes([40]u8);
                @compileError(std.fmt.comptimePrint("Duplicate hash {d} found at {d} and {d}\n {s} hash is equal to {s} hash", .{ b, index_1, index_2, bottom.encodeByte(index_1, &buffer_one), bottom.encodeByte(index_2, &buffer_two) }));
            }
        }
        return buffer_data;
    }
};

// Test functions verify:
// 1. Basic decoding functionality
// 2. All possible byte values can be decoded
// 3. Allocation behavior
// 4. Edge cases and error handling

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
    var byte: u8 = @truncate(0);
    var buffer: [40]u8 = comptime std.mem.zeroes([40]u8);
    var encode: []u8 = undefined;
    var result: u8 = undefined;
    for (0..256) |index| {
        byte = @as(u8, @truncate(index));
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
    var byte: u8 = @truncate(0);
    var buffer: [40]u8 = comptime std.mem.zeroes([40]u8);
    var encode: []u8 = undefined;
    var result: []u8 = undefined;
    for (0..256) |index| {
        byte = @as(u8, @truncate(index));
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
    var byte: u8 = @truncate(0);
    var buffer: [40]u8 = undefined;
    var encode: []u8 = undefined;
    var result: []u8 = undefined;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    for (0..256) |index| {
        byte = @as(u8, @truncate(index));
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

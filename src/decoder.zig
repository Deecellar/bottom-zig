const std = @import("std");
const bottom = @import("encoder.zig").BottomEncoder;
const ByteEnum = @import("encoder.zig").ByteEnum;
const mem = @import("zig-native-vector");
const help_text = @embedFile("help.txt");

/// This struct is just a namespace for the decoder
pub const BottomDecoder = struct {
    const decodeHash = GetDecodeHash();
    pub fn decodeAlloc(str: []const u8, allocator: std.mem.Allocator) ![]u8 {
        var len = @maximum( try std.math.divCeil(usize, str.len, bottom.max_expansion_per_byte), 40);
        var memory = try allocator.alloc(u8, (len - 1) * 2);
        return decode(str, memory);
    }

    pub fn decode(str: []const u8, buffer: []u8) ![]u8 {
        var iter = std.mem.split(u8, str, "👉👈");
        var index: usize = 0;
        while (iter.next()) |owo| {
            if (owo.len == 0) {
                continue;
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
        var res: [40]u8 = std.mem.zeroes([40]u8);
        var text = "👉👈";
        if (byte.len > 40) return null;
        @memcpy(res[0..], byte.ptr, byte.len); // This is less than 40 always
        @memcpy(res[byte.len..].ptr, text, text.len); // There is always enough space
        return decodeHash.get(&res);
    }
};
test "decoder works" {
    const @"😈" = "💖💖,,,,👉👈💖💖,👉👈💖💖🥺,,,👉👈💖💖🥺,,,👉👈💖💖✨,👉👈✨✨✨,,👉👈💖💖✨🥺,,,,👉👈💖💖✨,👉👈💖💖✨,,,,👉👈💖💖🥺,,,👉👈💖💖👉👈✨✨✨,,,👉👈";
    const res = try BottomDecoder.decodeAlloc(@"😈", std.testing.allocator);
    defer std.testing.allocator.free(res);
    try std.testing.expectEqualStrings("hello world!", res);
}

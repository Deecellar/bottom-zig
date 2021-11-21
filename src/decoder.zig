const std = @import("std");
const bottom = @import("encoder.zig").BottomEncoder;

/// This struct is just a namespace for the decoder
pub const BottomDecoder = struct {
    pub fn decodeAlloc(str: [] const u8, allocator : *std.mem.Allocator) ![]u8 {
        var len = try std.math.divCeil(usize, str.len, bottom.max_expansion_per_byte);
        var mem = try allocator.alloc(u8, len * 2);
        return try decode(str,mem);
    }
    pub fn decode(str: [] const u8, buffer: [] u8) ![]u8 {
        var iter = std.mem.split(u8, str, "👉👈");
        var index : usize = 0;
        while (true) {
            if (iter.next()) |owo| {
                buffer[index] = (try decodeByte(owo));
                index += 1;
            } else {
                break;
            }
        }
        return buffer[0..index - 1];
    }
    pub fn decodeByte(byte: []const u8) !u8 {
        var b: u8 = 0;
        var index: u64 = 0;
        while (index < byte.len) {
            if (index + 4 < byte.len + 1) {
                if (std.mem.eql(u8, bottom.chars[0..4], byte[index .. index + 4])) {
                    b += 200;
                    index += 4;
                    continue;
                }
                if (std.mem.eql(u8, bottom.chars[4..8], byte[index .. index + 4])) {
                    b += 50;
                    index += 4;
                    continue;
                }
                if (std.mem.eql(u8, bottom.chars[8..11], byte[index .. index + 3])) {
                    b += 10;
                    index += 3;
                    continue;
                }
                if (std.mem.eql(u8, bottom.chars[11..15], byte[index .. index + 4])) {
                    b += 5;
                    index += 4;
                    continue;
                }
            }
            if (byte.len > index) {
                if (std.mem.eql(u8, ",", byte[index .. index + 1])) {
                    b += 1;
                    index += 1;
                    continue;
                }
            }
            break;
        }
        return b;
    }
};
test "encode works" {
    const a = "💖💖,,,,👉👈💖💖,👉👈💖💖🥺,,,👉👈💖💖🥺,,,👉👈💖💖✨,👉👈✨✨✨,,👉👈💖💖✨🥺,,,,👉👈💖💖✨,👉👈💖💖✨,,,,👉👈💖💖🥺,,,👉👈💖💖👉👈✨✨✨,,,👉👈";
    const res = try BottomDecoder.decodeAlloc(a, std.testing.allocator);
    defer std.testing.allocator.free(res);
    try std.testing.expectEqualStrings("hello world!", res);
}

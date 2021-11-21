const std = @import("std");
const bottom = @import("encoder.zig").BottomEncoder;

/// This struct is just a namespace for the decoder
pub const BottomDecoder = struct {
    pub fn decode(str: []u8, allocator: *std.mem.Allocator) ![]u8 {
        var normalStreamBuffer = std.ArrayList(u8).init(allocator);
        var iter = std.mem.split(u8, str, "👉👈");
        while (true) {
            if (iter.next()) |owo| {
                try normalStreamBuffer.append(try decodeByte(owo));
            } else {
                break;
            }
        }
        _ =  normalStreamBuffer.pop();
        return normalStreamBuffer.toOwnedSlice();
    }
    pub fn decodeByte(byte: []const u8) !u8 {
        var b: u8 = 0;
        var index: u64 = 0;
        while (index < byte.len) {
            if (index+4 < byte.len +1) {
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
    var arr = std.ArrayList(u8).init(std.testing.allocator);
    try arr.appendSlice("hello world!");
    defer arr.deinit();
    const a = "💖💖,,,,👉👈💖💖,👉👈💖💖🥺,,,👉👈💖💖🥺,,,👉👈💖💖✨,👉👈✨✨✨,,👉👈💖💖✨🥺,,,,👉👈💖💖✨,👉👈💖💖✨,,,,👉👈💖💖🥺,,,👉👈💖💖👉👈✨✨✨,,,👉👈";
    var arr2 = std.ArrayList(u8).init(std.testing.allocator);
    try arr2.appendSlice(a);
    defer arr2.deinit();
    const res = try BottomDecoder.decode(arr2.items, std.testing.allocator);
    defer std.testing.allocator.free(res);
    try std.testing.expectEqualStrings(arr.items, res);
}

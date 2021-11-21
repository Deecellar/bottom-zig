const std = @import("std");
const options = @import("build_options").c_use;
/// This is just a namespace for the bottom encoder
pub const BottomEncoder = struct {
    pub const chars: []const u8 = "🫂💖✨🥺❤👉👈";

    /// Encode a stream of bytes to a bottomified version, the caller owns memory
    pub fn encode(str: []u8, allocator: *std.mem.Allocator) ![]u8 {
        var bottomStreamBuffer = try std.ArrayList(u8).initCapacity(allocator,str.len * 5);
        for (str) |v| {
            var byte = try encodeByte(v,allocator);
            defer allocator.free(byte);
            try bottomStreamBuffer.appendSlice(byte);
        }
        return bottomStreamBuffer.toOwnedSlice();
    }
    /// Encode one byte to bottom, the caller owns memory
    pub fn encodeByte(byte: u8,allocator : *std.mem.Allocator) ![]u8 {
        var bottomBuffer: std.ArrayList(u8) = try std.ArrayList(u8).initCapacity(allocator,35);
        var b: u8 = byte;
        if (b == 0) try bottomBuffer.appendSlice(chars[15..18]);
        while (b != 0) {
            if (b >= 200) {
                b -= 200;
                try bottomBuffer.appendSlice(chars[0..4]);
            } else if (b >= 50) {
                b -= 50;
                try bottomBuffer.appendSlice(chars[4..8]);
            } else if (b >= 10) {
                b -= 10;
                try bottomBuffer.appendSlice(chars[8..11]);
            } else if (b >= 5) {
                b -= 5;
                try bottomBuffer.appendSlice(chars[11..15]);
            } else if (b >= 1) {
                b -= 1;
                try bottomBuffer.append(',');
            }
        }
        
        try bottomBuffer.appendSlice(chars[18..]);
        
        return bottomBuffer.toOwnedSlice();
    }
};

test "encode works" {
    var arr =  std.ArrayList(u8).init(std.testing.allocator);
    try arr.appendSlice("hello world!");
    defer arr.deinit();
    const a = "💖💖,,,,👉👈💖💖,👉👈💖💖🥺,,,👉👈💖💖🥺,,,👉👈💖💖✨,👉👈✨✨✨,,👉👈💖💖✨🥺,,,,👉👈💖💖✨,👉👈💖💖✨,,,,👉👈💖💖🥺,,,👉👈💖💖👉👈✨✨✨,,,👉👈";
    var arr2 =  std.ArrayList(u8).init(std.testing.allocator);
    try arr2.appendSlice(a);
    defer arr2.deinit();
    const res = try BottomEncoder.encode(arr.items, std.testing.allocator);
    defer std.testing.allocator.free(res);
    try std.testing.expectEqualStrings(arr2.items,res) ;

}
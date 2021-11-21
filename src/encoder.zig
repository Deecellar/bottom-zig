const std = @import("std");
const options = @import("build_options").c_use;
/// This is just a namespace for the bottom encoder
pub const BottomEncoder = struct {
    pub const chars: []const u8 = "🫂💖✨🥺❤👉👈";
    pub const max_expansion_per_byte = 40;
    pub fn encodeAlloc(str: []const u8, allocator : *std.mem.Allocator) ![]u8 {
        const mem = try allocator.alloc(u8,str.len * max_expansion_per_byte);
        return try encode(str,mem);
    }
    

    /// Encode a stream of bytes to a bottomified version, the caller owns memory
    pub fn encode(str: []const u8, mem: []u8) ![]u8 {
        var index : usize = 0;
        for (str) |v| {
            var byte = try encodeByte(v);
            std.mem.copy(u8, mem[index..index+byte.len], byte[0..byte.len ]); 
            index += byte.len;
        }
        return mem[0..index];
    }
    /// Encode one byte to bottom, the caller owns memory
    pub fn encodeByte(byte: u8) ![]u8 {
        var buffer: [max_expansion_per_byte]u8 = undefined; // The maximum ammount of bytes per byte is 40
        var b: u8 = byte;
        var index: u6 = 0;
        if (b == 0) {
            std.mem.copy(u8, buffer[0..3], chars[15..18]);
            index += 3;
        }
        while (b != 0) {
            if (b >= 200) {
                b -= 200;
                std.mem.copy(u8, buffer[index .. index + 4], chars[0..4]);
                index += 4;
            } else if (b >= 50) {
                b -= 50;
                std.mem.copy(u8, buffer[index .. index + 4], chars[4..8]);
                index += 4;
            } else if (b >= 10) {
                b -= 10;
                std.mem.copy(u8, buffer[index .. index + 3], chars[8..11]);
                index += 3;
            } else if (b >= 5) {
                b -= 5;
                std.mem.copy(u8, buffer[index .. index + 4], chars[11..15]);
                index += 4;
            } else if (b >= 1) {
                b -= 1;
                buffer[index] = ',';
                index += 1;
            }
        }
        std.mem.copy(u8, buffer[index..], chars[18..]);
        index += 8;
        return buffer[0..index];
    }
};

test "encode works" {
    const a = "💖💖,,,,👉👈💖💖,👉👈💖💖🥺,,,👉👈💖💖🥺,,,👉👈💖💖✨,👉👈✨✨✨,,👉👈💖💖✨🥺,,,,👉👈💖💖✨,👉👈💖💖✨,,,,👉👈💖💖🥺,,,👉👈💖💖👉👈✨✨✨,,,👉👈";
    const res = try BottomEncoder.encodeAlloc("hello world!", std.testing.allocator);
    defer std.testing.allocator.free(res);
    try std.testing.expectEqualStrings(a, res);
}

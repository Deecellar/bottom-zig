const std = @import("std");

pub const ByteEnum = enum(u8) {
    @"🫂" = 200,
    @"💖" = 50,
    @"✨" = 10,
    @"🥺" = 5,
    @",,,," = 4,
    @",,," = 3,
    @",," = 2,
    @"," = 1,
};

/// This is just a namespace for the bottom encoder
pub const BottomEncoder = struct {
    pub const max_expansion_per_byte = 40;
    pub fn encodeAlloc(str: []const u8, allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
        const memory = try allocator.alloc(u8, str.len * max_expansion_per_byte);
        return encode(str, memory);
    }

    /// Encode a stream of bytes to a bottomified version, the caller owns memory
    pub fn encode(str: []const u8, memory: []u8) []u8 {
        @setRuntimeSafety(false);
        var index: usize = 0;
        var buffer: [max_expansion_per_byte]u8 = undefined; // The maximum ammount of bytes per byte is 40
        for (str) |v| {
            var byte = encodeByte(v, &buffer);
            @memcpy(memory[index .. index + byte.len], byte);
            index += byte.len;
        }
        return memory[0..index];
    }
    /// Encode one byte to bottom, the caller owns memory
    pub fn encodeByte(byte: u8, buffer: []u8) []u8 {
        @setRuntimeSafety(false);
        var b: u8 = byte;
        var index: usize = 0;
        var passed: bool = false;
        if (byte == 0) {
            var text = "❤";
            @memcpy(buffer[index .. index + text.len], text);
            index += text.len;
        }
        while (b != 0) {
            passed = false;
            inline for (@typeInfo(ByteEnum).Enum.fields) |f| {
                if (b >= f.value and !passed and b != 0) {
                    b -= f.value;
                    @memcpy(buffer[index .. index + f.name.len], f.name[0..]);
                    index += f.name.len;
                    passed = true;
                }
            }
        }
        var text = "👉👈";
        @memcpy(buffer[index .. index + text.len], text);
        index += text.len;
        return buffer[0..index];
    }
};

test "encode works" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, testEncoder, .{});
}

fn testEncoder(allocator: std.mem.Allocator) !void {
    if (@import("builtin").os.tag == .windows) {
        if (std.os.windows.kernel32.SetConsoleOutputCP(65001) == 0) {
            return error.console_not_support_utf8;
        }
    }
    const a = "💖💖,,,,👉👈💖💖,👉👈💖💖🥺,,,👉👈💖💖🥺,,,👉👈💖💖✨,👉👈✨✨✨,,👉👈💖💖✨🥺,,,,👉👈💖💖✨,👉👈💖💖✨,,,,👉👈💖💖🥺,,,👉👈💖💖👉👈✨✨✨,,,👉👈";
    const res = try BottomEncoder.encodeAlloc("hello world!", allocator);
    defer allocator.free(res);
    try std.testing.expectEqualStrings(a, res);
}

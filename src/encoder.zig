//! # Bottom Encoder Module
//! 
//! Converts regular text into "bottom-speak" encoding. This encoder transforms 
//! bytes into a specific emoji-based encoding scheme known as "bottom language".
//!
//! ## Example
//! ```zig
//! const text = "hello";
//! var result = try BottomEncoder.encodeAlloc(text, allocator);
//! defer BottomEncoder.encodeDealloc(allocator, result);
//! ```

const std = @import("std");

/// ## Byte Encoding Values
/// Maps each emoji/character sequence to a specific byte value in the bottom language.
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

/// ## Bottom Encoder
/// Core functionality for converting text to bottom-speak encoding
pub const BottomEncoder = struct {
    /// Maximum number of bytes that a single input byte could expand to during encoding
    pub const max_expansion_per_byte = 40;

    /// ## Encode With Allocation
    /// Allocates memory and encodes a byte slice into bottom-speak
    ///
    /// ### Parameters
    /// - `str`: Input byte slice to encode
    /// - `allocator`: Memory allocator to use
    ///
    /// ### Returns
    /// Allocated slice containing the encoded string
    ///
    /// ### Errors
    /// Returns allocator errors if memory allocation fails
    pub fn encodeAlloc(str: []const u8, allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
        const memory = try allocator.alloc(u8, str.len * max_expansion_per_byte);
        return encode(str, memory);
    }

    /// ## Direct Encoding
    /// Encodes a byte slice into bottom-speak using pre-allocated memory
    ///
    /// ### Parameters
    /// - `str`: Input byte slice to encode
    /// - `memory`: Pre-allocated memory to store the result
    ///
    /// ### Returns
    /// Slice of the memory containing the encoded string
    pub fn encode(str: []const u8, memory: []u8) []u8 {
        @setRuntimeSafety(false);
        var index: usize = 0;
        var buffer: [max_expansion_per_byte]u8 = undefined;
        for (str) |v| {
            const byte = encodeByte(v, &buffer);
            @memcpy(memory[index .. index + byte.len], byte);
            index += byte.len;
        }
        return memory[0..index];
    }

    /// ## Naive Byte Encoding
    /// Reference implementation used for validation and compilation
    ///
    /// ### Parameters
    /// - `byte`: Single byte to encode
    /// - `buffer`: Pre-allocated buffer for result
    ///
    /// ### Returns
    /// Slice of the buffer containing the encoded byte
    pub fn naiveEncodeByte(byte: u8, buffer: []u8) []u8 {
        @setRuntimeSafety(false);
        var b: u8 = byte;
        var index: usize = 0;
        var passed: bool = false;
        if (byte == 0) {
            const text = "❤";
            @memcpy(buffer[index .. index + text.len], text);
            index += text.len;
        }
        while (b != 0) {
            passed = false;
            inline for (@typeInfo(ByteEnum).@"enum".fields) |f| {
                if (b >= f.value and !passed and b != 0) {
                    b -= f.value;
                    @memcpy(buffer[index .. index + f.name.len], f.name[0..]);
                    index += f.name.len;
                    passed = true;
                }
            }
        }
        const text = "👉👈";
        @memcpy(buffer[index .. index + text.len], text);
        index += text.len;
        return buffer[0..index];
    }

    /// ## Optimized Byte Encoding
    /// Uses pre-computed lookup tables for faster encoding
    ///
    /// ### Parameters
    /// - `byte`: Single byte to encode
    /// - `buffer`: Pre-allocated buffer for result
    ///
    /// ### Returns
    /// Slice of the buffer containing the encoded byte
    pub fn encodeByte(byte: u8, buffer: []u8) []u8 {
        @setRuntimeSafety(false);
        const buffers, const lengths = comptime getBuffers();
        @memcpy(buffer[0..lengths[byte]], buffers[byte][0..lengths[byte]]);
        return buffer[0..lengths[byte]];
    }

    /// ## Generate Lookup Tables
    /// Creates compile-time lookup tables for all possible byte values
    ///
    /// ### Returns
    /// Tuple containing:
    /// - Array of buffers `[256][40]u8`
    /// - Array of lengths `[256]usize`
    pub fn getBuffers() struct { [256][40]u8, [256]usize } {
        @setEvalBranchQuota(100000000);
        var runtime_buffers: [256][40]u8 = undefined;
        var buffers_len: [256]usize = undefined;
        for (0..256) |index| {
            runtime_buffers[index] = std.mem.zeroes([40]u8);
            const result = naiveEncodeByte(@intCast(index), &runtime_buffers[index]);
            buffers_len[index] = result.len;
        }
        return .{ runtime_buffers, buffers_len };
    }

    /// ## Deallocate Encoded Memory
    /// Frees memory previously allocated by `encodeAlloc`
    ///
    /// ### Parameters
    /// - `allocator`: Memory allocator used for allocation
    /// - `ptr`: Pointer to the allocated memory
    pub fn encodeDealloc(allocator: std.mem.Allocator, ptr: []const u8) void {
        const len = std.mem.count(u8, ptr, "👉👈") * max_expansion_per_byte;
        var slice = ptr;
        slice.len = len;
        allocator.free(slice);
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
    defer BottomEncoder.encodeDealloc(allocator, res);
    try std.testing.expectEqualStrings(a, res);
}

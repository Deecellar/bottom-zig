//! # Bottom Encoder - Streaming writer for encoding to Bottom emoji format
//!
//! Provides a std.Io.Writer-compatible interface for encoding text to Bottom
//! emoji encoding. Implements efficient buffering with direct encoding for
//! oversized writes.

const std = @import("std");
const common = @import("common.zig");

/// Streaming encoder for Bottom emoji encoding.
///
/// Implements std.Io.Writer interface to encode raw bytes to Bottom emoji
/// format. Uses a two-phase drain strategy for optimal performance:
/// - Small writes are buffered and batch-encoded during flush()
/// - Large writes (exceeding buffer capacity) bypass buffering and encode directly
///
/// This approach minimizes memory copies while maintaining high throughput.
pub const BottomWriter = struct {
    writer: std.Io.Writer,
    sink: *std.Io.Writer,

    /// Initialize a Bottom encoder.
    ///
    /// buffer: Internal buffer for raw bytes before encoding (can be zero-sized for unbuffered mode)
    /// sink: The underlying writer receiving encoded Bottom data
    ///
    /// Returns a BottomWriter that implements std.Io.Writer interface.
    pub fn init(buffer: []u8, sink: *std.Io.Writer) BottomWriter {
        return .{
            .writer = .{
                .vtable = &vtable,
                .buffer = buffer,
                .end = 0,
            },
            .sink = sink,
        };
    }

    const vtable = std.Io.Writer.VTable{
        .drain = drain,
        .flush = flush,
    };

    /// flush() encodes all buffered raw data and writes it to the sink.
    ///
    /// This is called either explicitly by the user (e.g., before closing a file)
    /// or implicitly by drain() when making space for new data. Encoding happens
    /// byte-by-byte using the Bottom lookup table.
    fn flush(interface: *std.Io.Writer) !void {
        const self: *BottomWriter = @alignCast(@fieldParentPtr("writer", interface));
        const buffered_raw_data = interface.buffered();

        if (buffered_raw_data.len == 0) {
            return;
        }

        for (buffered_raw_data) |raw_byte| {
            const encoded = common.BottomLut.lut(raw_byte);
            try self.sink.writeAll(encoded);
        }

        interface.end = 0;
    }

    /// drain() implements the std.Io.Writer contract for making buffer space.
    ///
    /// Strategy:
    /// 1. Flush existing buffered data to the sink (making the buffer empty)
    /// 2. Check if the incoming write is larger than the entire buffer capacity
    ///    - If yes: encode and write directly to sink, bypassing the buffer
    ///    - If no: return 0 to signal write() should buffer the data
    ///
    /// This two-phase approach optimizes for both small writes (buffering reduces
    /// system calls) and large writes (direct encoding avoids unnecessary copying).
    ///
    /// Returning 0 tells write() that the buffer is now empty and ready to receive
    /// the new data, per the std.Io.Writer.VTable contract.
    fn drain(
        interface: *std.Io.Writer,
        data: []const []const u8,
        splat: usize,
    ) std.Io.Writer.Error!usize {
        // Phase 1: Make space by flushing existing buffered data.
        try flush(interface);

        const self: *BottomWriter = @alignCast(@fieldParentPtr("writer", interface));
        var consumed_from_args: usize = 0;
        const total_new_data_len = std.Io.Writer.countSplat(data, splat);

        // Phase 2: Handle oversized writes by encoding directly to sink.
        // This avoids the copy-to-buffer-then-flush cycle for large data.
        if (total_new_data_len > interface.buffer.len) {
            // Direct encoding path: process data without buffering.
            // data[] is a splat array where the last element is repeated
            // 'splat' times. We encode all parts sequentially.
            for (data[0 .. data.len - 1]) |part| {
                for (part) |raw_byte| {
                    const encoded = common.BottomLut.lut(raw_byte);
                    try self.sink.writeAll(encoded);
                }
                consumed_from_args += part.len;
            }
            // Handle the splatted final element
            if (data.len > 0) {
                const pattern = data[data.len - 1];
                for (0..splat) |_| {
                    for (pattern) |raw_byte| {
                        const encoded = common.BottomLut.lut(raw_byte);
                        try self.sink.writeAll(encoded);
                    }
                }
                consumed_from_args += pattern.len * splat;
            }
            return consumed_from_args;
        }

        // Normal case: buffer is now empty, return 0 to signal write() should
        // copy the new data into the buffer. This should maximize buffering efficiency
        // for small writes.
        return 0;
    }
};
fn testBufferSize(comptime size: usize) !void {
    if (@import("builtin").os.tag == .windows) {
        if (std.os.windows.kernel32.SetConsoleOutputCP(65001) == 0) {
            return error.console_not_support_utf8;
        }
    }
    const vector = "💖💖,,,,👉👈💖💖,👉👈💖💖🥺,,,👉👈💖💖🥺,,,👉👈💖💖✨,👉👈✨✨✨,,👉👈💖💖✨🥺,,,,👉👈💖💖✨,👉👈💖💖✨,,,,👉👈💖💖🥺,,,👉👈💖💖👉👈✨✨✨,,,👉👈";
    const base_string = "hello world!";

    var allocating_writer = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer allocating_writer.deinit();

    var bottom_writer_buffer: [size]u8 = undefined;

    var encoder = BottomWriter.init(&bottom_writer_buffer, &allocating_writer.writer);
    try encoder.writer.writeAll(base_string);
    try encoder.writer.flush();

    const res = allocating_writer.written();

    try std.testing.expectEqualStrings(vector, res);
}

test "BottomWriter works unbuffered" {
    try testBufferSize(0);
}

test "BottomWriter works with small buffer" {
    try testBufferSize(8);
}

test "BottomWriter works with medium buffer" {
    try testBufferSize(32);
}

test "BottomWriter works with large buffer" {
    try testBufferSize(128);
}

test "BottomWriter works with larger than content buffer" {
    try testBufferSize(256);
}

test "BottomWriter works with power of two buffer" {
    @setEvalBranchQuota(1000_000_000);
    const values = comptime blk: {
        var vals: [20]usize = undefined;
        var exp: usize = 1;
        for (&vals) |*v| {
            v.* = exp;
            exp *= 2;
        }
        break :blk [1]usize{0} ++ vals;
    };
    inline for (values) |size| {

        try testBufferSize(size);
    }

}

test "BottomWriter encodes individual bytes correctly" {
    // Stress test for drain() logic: write all 256 bytes individually with
    // a small buffer to force frequent drain() calls and verify correctness.

    var allocating_writer = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer allocating_writer.deinit();

    var bottom_writer_buffer: [32]u8 = undefined;
    var encoder = BottomWriter.init(&bottom_writer_buffer, &allocating_writer.writer);

    for (0..256) |i| {
        const byte: u8 = @truncate(i);
        try encoder.writer.writeByte(byte);
    }
    try encoder.writer.flush();

    var expected_builder: std.ArrayList(u8) = .empty;
    defer expected_builder.deinit(std.testing.allocator);

    for (0..256) |i| {
        const byte: u8 = @truncate(i);
        const encoded = common.BottomLut.lut(byte);
        try expected_builder.appendSlice(std.testing.allocator, encoded);
    }

    const actual_result = allocating_writer.written();
    const expected_result = expected_builder.items;

    try std.testing.expectEqualSlices(u8, expected_result, actual_result);
}

fn testOne(ctx: void, smith: *std.testing.Smith) !void {
    _ = ctx;
    var data: [4096]u8 = undefined;
    const len = smith.slice(&data);

    var allocating_writer = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer allocating_writer.deinit();

    var bottom_writer_buffer: [4096]u8 = undefined;

    var encoder = BottomWriter.init(&bottom_writer_buffer, &allocating_writer.writer);
    try encoder.writer.writeAll(data[0..len]);
    try encoder.writer.flush();

    _ = allocating_writer.written();
}
test "Fuzz testing" {
    try std.testing.fuzz({}, testOne, .{});
}
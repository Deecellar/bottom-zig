const std = @import("std");
const common = @import("common.zig");

pub const BottomWriter = struct {
    writer: std.Io.Writer,
    sink: *std.Io.Writer,

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

    // flush() is the workhorse. It is responsible for encoding
    // all raw data currently in the buffer and writing it to the sink.
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

    // drain()'s only job is to make space. It does this by calling flush().
    // It returns 0 to tell the caller ("write()") that no *new* data was
    // consumed, and that the caller is now free to put its data into the
    // now-empty buffer. This correctly follows the std lib contract.
    fn drain(
        interface: *std.Io.Writer,
        data: []const []const u8,
        splat: usize,
    ) std.Io.Writer.Error!usize {
        // To make space, we just flush what we have.
        try flush(interface);

        // The caller (`write`) might be trying to write a chunk of data
        // that is larger than our entire buffer. In this case, we need to
        // process that data directly without buffering it.
        const self: *BottomWriter = @alignCast(@fieldParentPtr("writer", interface));
        var consumed_from_args: usize = 0;
        const total_new_data_len = std.Io.Writer.countSplat(data, splat);

        if (total_new_data_len > interface.buffer.len) {
            // This new data will never fit in our buffer, so we must process it directly.
            for (data[0 .. data.len - 1]) |part| {
                for (part) |raw_byte| {
                    const encoded = common.BottomLut.lut(raw_byte);
                    try self.sink.writeAll(encoded);
                }
                consumed_from_args += part.len;
            }
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

        // Otherwise, we made space, so we tell the caller we consumed 0 bytes
        // from its new data, and it will now buffer it for us.
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
    // This test writes all 256 byte values one-by-one to stress the
    // buffering and drain logic of the writer.

    var allocating_writer = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer allocating_writer.deinit();

    // Use a small buffer to ensure drain() is called many times.
    var bottom_writer_buffer: [32]u8 = undefined;

    var encoder = BottomWriter.init(&bottom_writer_buffer, &allocating_writer.writer);

    // 1. Write every possible byte value
    for (0..256) |i| {
        const byte: u8 = @truncate(i);
        try encoder.writer.writeByte(byte);
    }

    // 2. IMPORTANT: Flush any remaining raw bytes in the buffer.
    try encoder.writer.flush();

    // 3. Build the expected result by concatenating all known encodings.
    var expected_builder = std.ArrayList(u8){};
    defer expected_builder.deinit(std.testing.allocator);

    for (0..256) |i| {
        const byte: u8 = @truncate(i);
        const encoded = common.BottomLut.lut(byte);
        try expected_builder.appendSlice(std.testing.allocator, encoded);
    }

    // 4. Compare the actual result with the expected result.
    const actual_result = allocating_writer.written();
    const expected_result = expected_builder.items;

    try std.testing.expectEqualSlices(u8, expected_result, actual_result);
}

fn testOne(ctx: void, data: []const u8) !void {
    _ = ctx;
    var allocating_writer = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer allocating_writer.deinit();

    var bottom_writer_buffer: [4096]u8 = undefined;

    var encoder = BottomWriter.init(&bottom_writer_buffer, &allocating_writer.writer);
    try encoder.writer.writeAll(data);
    try encoder.writer.flush();

    _ = allocating_writer.written();
}
test "Fuzz testing" {
    try std.testing.fuzz({}, testOne, .{.corpus = &.{
        "hello world!",
        "The quick brown fox jumps over the lazy dog.",
        "💖💖,,,,👉👈💖💖,👉👈",
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789",
        "😀😃😄😁😆😅😂🤣😊😇🙂",
    }});
}
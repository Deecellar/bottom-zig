//! # Bottom Decoder - Streaming reader for decoding Bottom emoji encoding
//!
//! Provides a std.Io.Reader-compatible interface for decoding Bottom-encoded
//! text. Handles partial sequences across read boundaries and validates input.

const std = @import("std");
const common = @import("common.zig");

/// Streaming decoder for Bottom emoji encoding.
///
/// Implements std.Io.Reader interface to decode Bottom-encoded data from an
/// underlying reader. Handles sequences that span multiple read() calls by
/// maintaining a partial sequence buffer.
///
/// The decoder tolerates invalid/garbage sequences by skipping them, continuing
/// to decode subsequent valid data after the next delimiter.
pub const BottomReader = struct {
    // Internal buffer for handling sequences that span multiple read() calls.
    // Sized to accommodate the longest Bottom sequence (48 bytes) plus delimiters.
    const processing_buffer_size = 256;

    // Maximum bytes a single encoded sequence can occupy. Validated at comptime
    // against the actual lookup table to catch encoding changes.
    const max_encoded_length = 48;

    reader: std.Io.Reader,
    source: *std.Io.Reader,
    encoded_buffer: []u8,
    partial_sequence_buffer: [processing_buffer_size]u8,
    partial_sequence_len: usize,

    // Compile-time validation: ensure our max_encoded_length constant is
    // actually sufficient for all bytes in the lookup table. This catches
    // encoding changes that would overflow the partial sequence buffer.
    comptime {
        for (0..256) |i| {
            const encoded = common.BottomLut.lut(@intCast(i));
            if (encoded.len > max_encoded_length) {
                @compileError(std.fmt.comptimePrint("Partial buffer too small: byte {} encodes to {} bytes", .{ i, encoded.len }));
            }
        }
    }

    /// Initialize a Bottom decoder.
    ///
    /// buffer: Output buffer for decoded bytes (can be zero-sized for unbuffered streaming)
    /// encoded_buffer: Temporary buffer for reading encoded data from source (can be zero-sized)
    /// source: The underlying reader providing encoded Bottom data
    ///
    /// Returns a BottomReader that implements std.Io.Reader interface.
    pub fn init(buffer: []u8, encoded_buffer: []u8, source: *std.Io.Reader) BottomReader {
        return .{
            .reader = .{
                .vtable = &vtable,
                .buffer = buffer,
                .seek = 0,
                .end = 0,
            },
            .source = source,
            .encoded_buffer = encoded_buffer,
            .partial_sequence_buffer = undefined,
            .partial_sequence_len = 0,
        };
    }

    const vtable = std.Io.Reader.VTable{
        .stream = stream,
    };

    fn stream(
        r: *std.Io.Reader,
        w: *std.Io.Writer,
        limit: std.Io.Limit,
    ) std.Io.Reader.StreamError!usize {
        const self: *BottomReader = @alignCast(@fieldParentPtr("reader", r));

        const dest = limit.slice(try w.writableSliceGreedy(1));
        var decoded_count: usize = 0;

        const room_for_new = if (self.partial_sequence_len >= processing_buffer_size) 0 else processing_buffer_size - self.partial_sequence_len;
        const read_cap = @min(self.encoded_buffer.len, room_for_new);
        var encoded_writer: std.Io.Writer = .fixed(self.encoded_buffer[0..read_cap]);
        const encoded_limit = std.Io.Limit.limited(read_cap);

        var hit_eof = false;
        const encoded_read = self.source.stream(&encoded_writer, encoded_limit) catch |err| switch (err) {
            error.EndOfStream => blk: {
                hit_eof = true;
                break :blk encoded_writer.end;
            },
            else => return err,
        };

        if (encoded_read == 0 and self.partial_sequence_len == 0) {
            return if (hit_eof) error.EndOfStream else 0;
        }

        const encoded_data = encoded_writer.buffered();
        const delimiter = common.BottomDecodeLut.delimiter;

        // Build the combined view of all available data. This handles sequences
        // that span multiple read() calls: we prepend any partial sequence from
        // the previous call, then append the newly read data.
        var view_buf: [processing_buffer_size]u8 = undefined;
        var view_len: usize = 0;
        if (self.partial_sequence_len > 0) {
            @memcpy(view_buf[0..self.partial_sequence_len], self.partial_sequence_buffer[0..self.partial_sequence_len]);
            view_len = self.partial_sequence_len;
        }
        @memcpy(view_buf[view_len..][0..encoded_data.len], encoded_data);
        view_len += encoded_data.len;

        const view = view_buf[0..view_len];
        var view_pos: usize = 0;

        // Parse delimiter-separated sequences. Sequences are validated for length
        // (<=48 bytes) and decodability. Invalid sequences are skipped, allowing
        // the decoder to recover from garbage data.
        while (view_pos < view.len) {
            if (decoded_count >= dest.len) break;

            const remaining_view = view[view_pos..];
            const delim_opt = common.indexOf(remaining_view, delimiter);

            if (delim_opt) |relative_delim_pos| {
                const sequence = remaining_view[0..relative_delim_pos];

                // Validate and decode the sequence. Sequences longer than 48 bytes
                // or containing invalid emoji combinations are silently skipped.
                // @branchHint(.likely) optimizes for the common case of valid data.
                if (sequence.len <= max_encoded_length) {
                    if (common.BottomDecodeLut.decode(sequence)) |byte| {
                        @branchHint(.likely);
                        dest[decoded_count] = byte;
                        decoded_count += 1;
                    }
                }
                // Advance past this sequence and its delimiter, regardless of
                // whether we successfully decoded it. This allows recovery from
                // corrupted data.
                view_pos += relative_delim_pos + delimiter.len;
            } else {
                // No delimiter found: the remaining data is a partial sequence
                // that will be completed in the next read() call.
                break;
            }
        }

        // Preserve unprocessed data (incomplete sequence without delimiter) for
        // the next stream() call. This is essential for sequences that span
        // multiple read boundaries.
        const remaining_len = view.len - view_pos;
        if (remaining_len > 0) {
            @memcpy(self.partial_sequence_buffer[0..remaining_len], view[view_pos..]);
        }
        self.partial_sequence_len = remaining_len;

        // Detect truncated input: EOF reached but partial sequence remains.
        // This indicates corrupted/incomplete Bottom encoding.
        if (hit_eof and self.partial_sequence_len > 0) {
            return error.ReadFailed;
        }

        // Correctly commit the decoded bytes to the writer.
        if (decoded_count > 0) {
            w.advance(decoded_count);
        }

        // If we are at EOF and produced nothing, signal EndOfStream.
        if (hit_eof and decoded_count == 0 and self.partial_sequence_len == 0) {
            return error.EndOfStream;
        }

        return decoded_count;
    }
};

test "BottomReader works correctly" {
    if (@import("builtin").os.tag == .windows) {
        if (std.os.windows.kernel32.SetConsoleOutputCP(65001) == 0) {
            return error.console_not_support_utf8;
        }
    }

    const encoded = "💖💖,,,,👉👈💖💖,👉👈💖💖🥺,,,👉👈💖💖🥺,,,👉👈💖💖✨,👉👈✨✨✨,,👉👈💖💖✨🥺,,,,👉👈💖💖✨,👉👈💖💖✨,,,,👉👈💖💖🥺,,,👉👈💖💖👉👈✨✨✨,,,👉👈";
    const expected = "hello world!";

    var source_reader: std.Io.Reader = .fixed(encoded);

    var decode_buffer: [256]u8 = undefined;
    var encoded_buffer: [512]u8 = undefined;

    var bottom_reader = BottomReader.init(&decode_buffer, &encoded_buffer, &source_reader);

    var result: [expected.len]u8 = undefined;
    try bottom_reader.reader.readSliceAll(&result);

    try std.testing.expectEqualStrings(expected, &result);
}

test "BottomReader works with small buffers" {
    if (@import("builtin").os.tag == .windows) {
        if (std.os.windows.kernel32.SetConsoleOutputCP(65001) == 0) {
            return error.console_not_support_utf8;
        }
    }

    const encoded = "💖💖,,,,👉👈💖💖,👉👈💖💖🥺,,,👉👈💖💖🥺,,,👉👈💖💖✨,👉👈";
    const expected = "hello";

    var source_reader: std.Io.Reader = .fixed(encoded);

    var decode_buffer: [2]u8 = undefined;
    var encoded_buffer: [64]u8 = undefined;

    var bottom_reader = BottomReader.init(&decode_buffer, &encoded_buffer, &source_reader);

    var result: [expected.len]u8 = undefined;
    try bottom_reader.reader.readSliceAll(&result);

    try std.testing.expectEqualStrings(expected, &result);
}

test "All bytes encodable and decodable via streaming" {
    for (0..256) |index| {
        const byte: u8 = @truncate(index);

        // Encode the byte
        const encoded = common.BottomLut.lut(byte);

        // Decode via streaming reader
        var source_reader: std.Io.Reader = .fixed(encoded);
        var decode_buffer: [1]u8 = undefined;
        var encoded_buffer: [64]u8 = undefined;

        var bottom_reader = BottomReader.init(&decode_buffer, &encoded_buffer, &source_reader);

        var result: [1]u8 = undefined;
        try bottom_reader.reader.readSliceAll(&result);

        try std.testing.expectEqual(byte, result[0]);
    }
}

test "BottomReader allocRemaining with all bytes" {
    for (0..256) |index| {
        const byte: u8 = @truncate(index);

        // Encode the byte
        const encoded = common.BottomLut.lut(byte);

        // Decode via allocRemaining
        var source_reader: std.Io.Reader = .fixed(encoded);
        var decode_buffer: [16]u8 = undefined;
        var encoded_buffer: [64]u8 = undefined;

        var bottom_reader = BottomReader.init(&decode_buffer, &encoded_buffer, &source_reader);

        const result = try bottom_reader.reader.allocRemaining(std.testing.allocator, .unlimited);
        defer std.testing.allocator.free(result);

        try std.testing.expectEqual(1, result.len);
        try std.testing.expectEqual(byte, result[0]);
    }
}

test "BottomReader handles partial reads correctly" {
    if (@import("builtin").os.tag == .windows) {
        if (std.os.windows.kernel32.SetConsoleOutputCP(65001) == 0) {
            return error.console_not_support_utf8;
        }
    }

    // Verify partial_sequence_buffer works correctly when sequences span
    // multiple read() calls. Uses tiny buffers to force this condition.
    const original = "The quick brown fox jumps over the lazy dog";

    var encode_sink = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer encode_sink.deinit();

    var encode_buffer: [128]u8 = undefined;
    var encoder = @import("encoder_writer.zig").BottomWriter.init(&encode_buffer, &encode_sink.writer);
    try encoder.writer.writeAll(original);
    try encoder.writer.flush();

    const encoded = encode_sink.written();

    var source_reader: std.Io.Reader = .fixed(encoded);
    var decode_buffer: [4]u8 = undefined;
    var encoded_buffer: [32]u8 = undefined;

    var decoder = BottomReader.init(&decode_buffer, &encoded_buffer, &source_reader);

    const result = try decoder.reader.allocRemaining(std.testing.allocator, .unlimited);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings(original, result);
}

test "BottomReader handles sequences spanning multiple reads" {
    if (@import("builtin").os.tag == .windows) {
        if (std.os.windows.kernel32.SetConsoleOutputCP(65001) == 0) {
            return error.console_not_support_utf8;
        }
    }

    // Verify handling of sequences split mid-encoding across read boundaries.
    // Byte 255 has one of the longest encodings in the Bottom scheme.
    const original: [10]u8 = @splat(255);

    var encode_sink = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer encode_sink.deinit();

    var encode_buffer: [256]u8 = undefined;
    var encoder = @import("encoder_writer.zig").BottomWriter.init(&encode_buffer, &encode_sink.writer);
    try encoder.writer.writeAll(&original);
    try encoder.writer.flush();

    const encoded = encode_sink.written();

    var source_reader: std.Io.Reader = .fixed(encoded);
    var decode_buffer: [2]u8 = undefined;
    var encoded_buffer: [20]u8 = undefined;

    var decoder = BottomReader.init(&decode_buffer, &encoded_buffer, &source_reader);

    const result = try decoder.reader.allocRemaining(std.testing.allocator, .unlimited);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualSlices(u8, &original, result);
}

test "BottomReader handles edge case with exact buffer boundary" {
    if (@import("builtin").os.tag == .windows) {
        if (std.os.windows.kernel32.SetConsoleOutputCP(65001) == 0) {
            return error.console_not_support_utf8;
        }
    }

    // Tests delimiter alignment with buffer boundaries across multiple sizes.
    const original = "ABCDEFGHIJKLMNOP";

    var encode_sink = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer encode_sink.deinit();

    var encode_buffer: [512]u8 = undefined;
    var encoder = @import("encoder_writer.zig").BottomWriter.init(&encode_buffer, &encode_sink.writer);
    try encoder.writer.writeAll(original);
    try encoder.writer.flush();

    const encoded = encode_sink.written();

    const buffer_sizes = [_]usize{ 8, 16, 32, 64, 128 };

    for (buffer_sizes) |buf_size| {
        var source_reader: std.Io.Reader = .fixed(encoded);
        var decode_buffer: [32]u8 = undefined;
        const encoded_buffer = try std.testing.allocator.alloc(u8, buf_size);
        defer std.testing.allocator.free(encoded_buffer);

        var decoder = BottomReader.init(&decode_buffer, encoded_buffer, &source_reader);

        const result = try decoder.reader.allocRemaining(std.testing.allocator, .unlimited);
        defer std.testing.allocator.free(result);

        try std.testing.expectEqualStrings(original, result);
    }
}

test "BottomReader handles truncated data" {
    // Sequences without delimiters at EOF should error (corrupted encoding)
    const encoded = "💖💖,,,,";
    var source_reader: std.Io.Reader = .fixed(encoded);

    var decode_buffer: [8]u8 = undefined;
    var encoded_buffer: [64]u8 = undefined;

    var bottom_reader = BottomReader.init(&decode_buffer, &encoded_buffer, &source_reader);

    var result: [1]u8 = undefined;
    const err = bottom_reader.reader.readSliceAll(&result);

    try std.testing.expectError(error.ReadFailed, err);
}

test "BottomReader validates max sequence length" {
    // Ensure compile-time validation works
    for (0..256) |i| {
        const encoded = common.BottomLut.lut(@intCast(i));
        try std.testing.expect(encoded.len <= BottomReader.max_encoded_length);
    }
}

test "BottomReader handles delimiter split across reads" {
    const encoded = "💖💖,,,,👉👈";
    var source_reader: std.Io.Reader = .fixed(encoded);
    var decode_buffer: [1]u8 = undefined;
    var encoded_buffer: [8]u8 = undefined;
    var bottom_reader = BottomReader.init(&decode_buffer, &encoded_buffer, &source_reader);

    var result: [1]u8 = undefined;
    try bottom_reader.reader.readSliceAll(&result);
    try std.testing.expectEqual(@as(u8, 104), result[0]);
}
test "BottomReader skips garbage and decodes subsequent valid data" {
    // Verify error recovery: invalid/oversized sequences are skipped, allowing
    // decoding to continue with the next valid sequence after a delimiter.

    const garbage_sequence = "💖💖💖💖💖💖💖💖💖💖💖💖💖💖💖💖💖";
    const valid_sequence_A = "💖🥺,";
    const delimiter = "👉👈";
    const full_encoded_string = garbage_sequence ++ delimiter ++ valid_sequence_A ++ delimiter;
    const expected_decoded_byte: u8 = '8';

    var source_reader: std.Io.Reader = .fixed(full_encoded_string);

    var decode_buffer: [16]u8 = undefined;
    var encoded_buffer: [64]u8 = undefined;

    var bottom_reader = BottomReader.init(&decode_buffer, &encoded_buffer, &source_reader);

    const result = try bottom_reader.reader.takeByte();

    try std.testing.expectEqual(expected_decoded_byte, result);
}

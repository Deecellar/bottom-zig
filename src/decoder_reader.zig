const std = @import("std");
const common = @import("common.zig");

pub const BottomReader = struct {
    const processing_buffer_size = 256;
    const max_encoded_length = 48;

    reader: std.Io.Reader,
    source: *std.Io.Reader,
    encoded_buffer: []u8,
    partial_sequence_buffer: [processing_buffer_size]u8,
    partial_sequence_len: usize,

    comptime {
        for (0..256) |i| {
            const encoded = common.BottomLut.lut(@intCast(i));
            if (encoded.len > max_encoded_length) {
                @compileError(std.fmt.comptimePrint("Partial buffer too small: byte {} encodes to {} bytes", .{ i, encoded.len }));
            }
        }
    }

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

        // Build the combined view of all available data.
        var view_buf: [processing_buffer_size]u8 = undefined;
        var view_len: usize = 0;
        if (self.partial_sequence_len > 0) {
            @memcpy(view_buf[0..self.partial_sequence_len], self.partial_sequence_buffer[0..self.partial_sequence_len]);
            view_len = self.partial_sequence_len;
        }
        @memcpy(view_buf[view_len..][0..encoded_data.len], encoded_data);
        view_len += encoded_data.len;

        const view = view_buf[0..view_len];
        var view_pos: usize = 0; // This cursor marks the start of the sequence we're considering.

        // Loop through the view, consuming sequences (or garbage) separated by delimiters.
        while (view_pos < view.len) {
            if (decoded_count >= dest.len) break;

            const remaining_view = view[view_pos..];
            const delim_opt = common.indexOf(remaining_view, delimiter);

            if (delim_opt) |relative_delim_pos| {
                const sequence = remaining_view[0..relative_delim_pos];

                // Check if the candidate is a valid, decodable sequence.
                if (sequence.len <= max_encoded_length) {
                    if (common.BottomDecodeLut.decode(sequence)) |byte| {
                        @branchHint(.likely);
                        dest[decoded_count] = byte;
                        decoded_count += 1;
                    }
                }
                // Regardless of outcome, advance the cursor past this entire segment.
                view_pos += relative_delim_pos + delimiter.len;
            } else {
                // No more delimiters in the view. The rest is a partial sequence.
                break;
            }
        }

        // Save any unprocessed data for the next call.
        const remaining_len = view.len - view_pos;
        if (remaining_len > 0) {
            @memcpy(self.partial_sequence_buffer[0..remaining_len], view[view_pos..]);
        }
        self.partial_sequence_len = remaining_len;

        // Final EOF check for truncated data.
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

    // Test with data that will require multiple partial reads
    const original = "The quick brown fox jumps over the lazy dog";

    // First encode it
    var encode_sink = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer encode_sink.deinit();

    var encode_buffer: [128]u8 = undefined;
    var encoder = @import("encoder_writer.zig").BottomWriter.init(&encode_buffer, &encode_sink.writer);
    try encoder.writer.writeAll(original);
    try encoder.writer.flush();

    const encoded = encode_sink.written();

    // Now decode with intentionally tiny buffers to force many partial reads
    var source_reader: std.Io.Reader = .fixed(encoded);
    var decode_buffer: [4]u8 = undefined; // Very small decode buffer
    var encoded_buffer: [32]u8 = undefined; // Small encoded buffer

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

    // Create encoded data where a single sequence might be split across reads
    // Use byte 255 which has a long encoding
    const original = [_]u8{255} ** 10;

    var encode_sink = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer encode_sink.deinit();

    var encode_buffer: [256]u8 = undefined;
    var encoder = @import("encoder_writer.zig").BottomWriter.init(&encode_buffer, &encode_sink.writer);
    try encoder.writer.writeAll(&original);
    try encoder.writer.flush();

    const encoded = encode_sink.written();

    // Decode with buffer smaller than a single encoded byte sequence
    var source_reader: std.Io.Reader = .fixed(encoded);
    var decode_buffer: [2]u8 = undefined;
    var encoded_buffer: [20]u8 = undefined; // Smaller than one 255 encoding

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

    // Test case where delimiter falls exactly at buffer boundary
    const original = "ABCDEFGHIJKLMNOP"; // 16 bytes

    var encode_sink = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer encode_sink.deinit();

    var encode_buffer: [512]u8 = undefined;
    var encoder = @import("encoder_writer.zig").BottomWriter.init(&encode_buffer, &encode_sink.writer);
    try encoder.writer.writeAll(original);
    try encoder.writer.flush();

    const encoded = encode_sink.written();

    // Use various buffer sizes to test boundary conditions
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
    // Verify truncated sequences are detected
    const encoded = "💖💖,,,,"; // 'h' without delimiter
    var source_reader: std.Io.Reader = .fixed(encoded);

    var decode_buffer: [8]u8 = undefined;
    var encoded_buffer: [64]u8 = undefined;

    var bottom_reader = BottomReader.init(&decode_buffer, &encoded_buffer, &source_reader);

    var result: [1]u8 = undefined;
    const err = bottom_reader.reader.readSliceAll(&result);

    // Should fail because sequence is incomplete
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
    // This test verifies the decoder can handle a corrupt/invalid sequence
    // (either too long or undecodable) and then continue decoding correctly.

    // 1. Create a "garbage" segment: a long string of encoded data.
    const garbage_sequence = "💖💖💖💖💖💖💖💖💖💖💖💖💖💖💖💖💖"; // 17 hearts = 51 bytes > 48

    // 2. Create a valid sequence for the letter 'A'.
    const valid_sequence_A = "💖🥺,"; // Encoded 'A'

    // 3. Construct the full stream: [GARBAGE][DELIMITER][VALID][DELIMITER]
    const delimiter = "👉👈";
    const full_encoded_string = garbage_sequence ++ delimiter ++ valid_sequence_A ++ delimiter;
    const expected_decoded_byte: u8 = '8';

    var source_reader: std.Io.Reader = .fixed(full_encoded_string);

    var decode_buffer: [16]u8 = undefined;
    var encoded_buffer: [64]u8 = undefined; // Large enough to get both sequences

    var bottom_reader = BottomReader.init(&decode_buffer, &encoded_buffer, &source_reader);

    // With the final robust logic, this should read 'A' and ignore the garbage.
    const result = try bottom_reader.reader.takeByte();

    try std.testing.expectEqual(expected_decoded_byte, result);
}

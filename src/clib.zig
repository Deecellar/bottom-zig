//! # Bottom Encoder/Decoder C API
//!
//! This module provides C-compatible bindings for encoding and decoding text
//! using the Bottom encoding scheme.

const std = @import("std");
const builtin = @import("builtin");
const options = @import("build_options");
const bottom = @import("bottom");

const max_expansion_per_byte = 48;

/// # CSlice
/// 
/// Represents a slice/array that can be passed between C and Zig
const CSlice = extern struct {
    ptr: ?[*]const u8,
    len: usize,
};

/// Global error state for C API functions
export var bottom_current_error: u8 = 0;

/// # Library Initialization
fn bottomInitLib() callconv(.c) void {
    if (builtin.os.tag == .windows) {
        if (std.os.windows.kernel32.SetConsoleOutputCP(65001) == 0) {
            bottom_current_error = 3;
        }
    }
}

/// # Text Encoding with Allocation
fn bottomEncodeAlloc(input: [*]u8, len: usize) callconv(.c) CSlice {
    const allocator = std.heap.c_allocator;
    
    // Allocate buffers
    const encode_buffer = allocator.alloc(u8, max_expansion_per_byte * 1024) catch {
        bottom_current_error = 1;
        return CSlice{ .ptr = null, .len = 0 };
    };
    defer allocator.free(encode_buffer);
    
    // Create input reader
    var input_reader: std.Io.Reader = .fixed(input[0..len]);
    
    // Create output writer
    var output_allocating = std.Io.Writer.Allocating.init(allocator);
    defer output_allocating.deinit();
    
    // Create encoder
    var encoder = bottom.BottomWriter.init(encode_buffer, &output_allocating.writer);
    
    // Stream data
    _ = input_reader.streamRemaining(&encoder.writer) catch {
        bottom_current_error = 1;
        return CSlice{ .ptr = null, .len = 0 };
    };
    
    // Flush
    encoder.writer.flush() catch {
        bottom_current_error = 1;
        return CSlice{ .ptr = null, .len = 0 };
    };
    
    // Get result and transfer ownership
    const result = output_allocating.toOwnedSlice() catch {
        bottom_current_error = 1;
        return CSlice{ .ptr = null, .len = 0 };
    };
    
    return CSlice{ .ptr = result.ptr, .len = result.len };
}

/// # Buffer Encoding
fn bottomEncodeBuf(input: [*]u8, len: usize, buf: [*]u8, buf_len: usize) callconv(.c) CSlice {
    if (buf_len < len * max_expansion_per_byte) {
        bottom_current_error = 1;
        return CSlice{ .ptr = null, .len = 0 };
    }
    
    const allocator = std.heap.c_allocator;
    
    // Allocate encode buffer
    const encode_buffer = allocator.alloc(u8, max_expansion_per_byte * 1024) catch {
        bottom_current_error = 1;
        return CSlice{ .ptr = null, .len = 0 };
    };
    defer allocator.free(encode_buffer);
    
    // Create input reader
    var input_reader: std.Io.Reader = .fixed(input[0..len]);
    
    // Create output writer using provided buffer
    var output_writer: std.Io.Writer = .fixed(buf[0..buf_len]);
    
    // Create encoder
    var encoder = bottom.BottomWriter.init(encode_buffer, &output_writer);
    
    // Stream data
    _ = input_reader.streamRemaining(&encoder.writer) catch {
        bottom_current_error = 1;
        return CSlice{ .ptr = null, .len = 0 };
    };
    
    // Flush
    encoder.writer.flush() catch {
        bottom_current_error = 1;
        return CSlice{ .ptr = null, .len = 0 };
    };
    
    const result = output_writer.buffered();
    return CSlice{ .ptr = result.ptr, .len = result.len };
}

/// # Decode With Allocation
fn bottomDecodeAlloc(input: [*]u8, len: usize) callconv(.c) CSlice {
    const allocator = std.heap.c_allocator;
    
    // Allocate buffers
    const decode_buffer = allocator.alloc(u8, 1024) catch {
        bottom_current_error = 1;
        return CSlice{ .ptr = null, .len = 0 };
    };
    defer allocator.free(decode_buffer);
    
    const encoded_buffer = allocator.alloc(u8, max_expansion_per_byte * 1024) catch {
        bottom_current_error = 1;
        return CSlice{ .ptr = null, .len = 0 };
    };
    defer allocator.free(encoded_buffer);
    
    // Create input reader
    var input_reader: std.Io.Reader = .fixed(input[0..len]);
    
    // Create decoder
    var decoder = bottom.BottomReader.init(decode_buffer, encoded_buffer, &input_reader);
    
    // Create output writer
    var output_allocating = std.Io.Writer.Allocating.init(allocator);
    defer output_allocating.deinit();
    
    // Stream data
    _ = decoder.reader.streamRemaining(&output_allocating.writer) catch {
        bottom_current_error = 2;
        return CSlice{ .ptr = null, .len = 0 };
    };
    
    // Get result and transfer ownership
    const result = output_allocating.toOwnedSlice() catch {
        bottom_current_error = 1;
        return CSlice{ .ptr = null, .len = 0 };
    };
    
    return CSlice{ .ptr = result.ptr, .len = result.len };
}

/// # Buffer Decoding
fn bottomDecodeBuf(input: [*]u8, len: usize, buf: [*]u8, buf_len: usize) callconv(.c) CSlice {
    if (buf_len < len) {
        bottom_current_error = 1;
        return CSlice{ .ptr = null, .len = 0 };
    }
    
    const allocator = std.heap.c_allocator;
    
    // Allocate buffers
    const decode_buffer = allocator.alloc(u8, 1024) catch {
        bottom_current_error = 1;
        return CSlice{ .ptr = null, .len = 0 };
    };
    defer allocator.free(decode_buffer);
    
    const encoded_buffer = allocator.alloc(u8, max_expansion_per_byte * 1024) catch {
        bottom_current_error = 1;
        return CSlice{ .ptr = null, .len = 0 };
    };
    defer allocator.free(encoded_buffer);
    
    // Create input reader
    var input_reader: std.Io.Reader = .fixed(input[0..len]);
    
    // Create decoder
    var decoder = bottom.BottomReader.init(decode_buffer, encoded_buffer, &input_reader);
    
    // Create output writer using provided buffer
    var output_writer: std.Io.Writer = .fixed(buf[0..buf_len]);
    
    // Stream data
    _ = decoder.reader.streamRemaining(&output_writer) catch {
        bottom_current_error = 2;
        return CSlice{ .ptr = null, .len = 0 };
    };
    
    const result = output_writer.buffered();
    return CSlice{ .ptr = result.ptr, .len = result.len };
}

/// # Error State Management
fn getError() callconv(.c) u8 {
    defer bottom_current_error = 0;
    return bottom_current_error;
}

// Error message constants
const error_no_error_string = "No error";
const error_not_enough_memory_string = "Not enough memory";
const error_invalid_input_string = "Invalid input";
const error_unknown_error_string = "Unknown error";
const error_windows_utf8 = "This windows terminal can't use UTF-8";

/// # Error Message Retrieval
fn getErrorString(error_code: u8) callconv(.c) CSlice {
    if (error_code == 0) {
        return CSlice{ .ptr = error_no_error_string, .len = error_no_error_string.len };
    }
    if (error_code == 1) {
        return CSlice{ .ptr = error_not_enough_memory_string, .len = error_not_enough_memory_string.len };
    }
    if (error_code == 2) {
        return CSlice{ .ptr = error_invalid_input_string, .len = error_invalid_input_string.len };
    }
    if (error_code == 3) {
        return CSlice{ .ptr = error_windows_utf8, .len = error_windows_utf8.len };
    }
    return CSlice{ .ptr = error_unknown_error_string, .len = error_unknown_error_string.len };
}

/// # Version Information
fn getVersion() callconv(.c) CSlice {
    const version = options.version;
    return CSlice{ .ptr = version.ptr, .len = version.len };
}

/// # Memory Management
fn freeSlice(slice: CSlice) callconv(.c) void {
    const allocator = std.heap.c_allocator;
    if (slice.ptr) |ptr| {
        allocator.free(ptr[0..slice.len]);
    }
}

// Export all functions with C linkage
comptime {
    @export(&bottomInitLib, .{ .name = "bottom_init_lib", .linkage = .strong });
    @export(&bottomDecodeAlloc, .{ .name = "bottom_decode_alloc", .linkage = .strong });
    @export(&bottomDecodeBuf, .{ .name = "bottom_decode_buf", .linkage = .strong });
    @export(&bottomEncodeAlloc, .{ .name = "bottom_encode_alloc", .linkage = .strong });
    @export(&bottomEncodeBuf, .{ .name = "bottom_encode_buf", .linkage = .strong });
    @export(&getError, .{ .name = "bottom_get_error", .linkage = .strong });
    @export(&getErrorString, .{ .name = "bottom_get_error_string", .linkage = .strong });
    @export(&getVersion, .{ .name = "bottom_get_version", .linkage = .strong });
    @export(&freeSlice, .{ .name = "bottom_free_slice", .linkage = .strong });
}
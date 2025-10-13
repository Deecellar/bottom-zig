//! # Bottom Encoder/Decoder C API
//!
//! This module provides C-compatible bindings for encoding and decoding text
//! using the Bottom encoding scheme.
//!
//! ## Memory Management
//! - All allocations use std.heap.c_allocator
//! - *_alloc functions return memory owned by the caller (must call bottom_free_slice)
//! - *_buf functions use caller-provided buffers (no allocation)
//!
//! ## Error Handling
//! - Errors are reported via the global bottom_current_error variable
//! - Check bottom_get_error() after each API call
//! - Error codes:
//!   0 = No error
//!   1 = Memory allocation failure or buffer too small
//!   2 = Invalid Bottom encoding (malformed input)
//!   3 = Windows console UTF-8 not supported
//!
//! ## Buffer Sizing
//! - Encoding: output buffer must be at least input_len * 48 bytes (worst-case)
//! - Decoding: output buffer must be at least input_len bytes (conservative estimate)
//! - Internal encode buffer: 48KB (max_expansion_per_byte * 1024)
//! - Internal decode buffer: 1KB

const std = @import("std");
const builtin = @import("builtin");
const options = @import("build_options");
const bottom = @import("bottom");

// Maximum bytes a single input byte can expand to when encoded.
// Used for buffer size calculations throughout the C API.
const max_expansion_per_byte = 48;

/// C-compatible slice type for passing data across FFI boundary.
///
/// ptr: Pointer to data (null indicates error)
/// len: Length of data in bytes
///
/// For *_alloc functions, caller must free with bottom_free_slice().
/// For *_buf functions, ptr points into caller-provided buffer.
const CSlice = extern struct {
    ptr: ?[*]const u8,
    len: usize,
};

/// Global error state. Thread-unsafe, so C API is not thread-safe.
/// Check with bottom_get_error() after each call. Automatically cleared
/// after reading.
export var bottom_current_error: u8 = 0;

/// Initialize the library. Must be called before any other API functions.
///
/// On Windows, attempts to set console to UTF-8 (CP65001). Sets error code 3
/// if this fails (indicating Windows Terminal or compatible console is needed).
fn bottomInitLib() callconv(.c) void {
    if (builtin.os.tag == .windows) {
        if (std.os.windows.kernel32.SetConsoleOutputCP(65001) == 0) {
            bottom_current_error = 3;
        }
    }
}

/// Encode text to Bottom format with automatic memory allocation.
///
/// input: Pointer to UTF-8 text to encode
/// len: Length of input in bytes
///
/// Returns CSlice with encoded data. Caller must call bottom_free_slice() to free.
/// On error, returns CSlice with ptr=null and sets bottom_current_error.
///
/// Internal buffer size: 48KB (max_expansion_per_byte * 1024)
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

/// Encode text to Bottom format using caller-provided buffer.
///
/// input: Pointer to UTF-8 text to encode
/// len: Length of input in bytes
/// buf: Caller-provided buffer for output
/// buf_len: Size of output buffer (must be >= len * 48)
///
/// Returns CSlice pointing into buf with encoded data length.
/// On error, returns CSlice with ptr=null and sets bottom_current_error.
/// No memory allocation; buf must be sized appropriately by caller.
fn bottomEncodeBuf(input: [*]u8, len: usize, buf: [*]u8, buf_len: usize) callconv(.c) CSlice {
    // Validate buffer size. Worst-case expansion is 48x (byte 200 = ✨✨✨,,,).
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

/// Decode Bottom-encoded text with automatic memory allocation.
///
/// input: Pointer to Bottom-encoded text
/// len: Length of input in bytes
///
/// Returns CSlice with decoded data. Caller must call bottom_free_slice() to free.
/// On error, returns CSlice with ptr=null and sets bottom_current_error.
/// Error code 2 indicates invalid Bottom encoding.
///
/// Internal buffer sizes: 1KB decode buffer, 48KB encoded buffer
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

/// Decode Bottom-encoded text using caller-provided buffer.
///
/// input: Pointer to Bottom-encoded text
/// len: Length of input in bytes
/// buf: Caller-provided buffer for output
/// buf_len: Size of output buffer (must be >= len for safety, actual output will be smaller)
///
/// Returns CSlice pointing into buf with decoded data length.
/// On error, returns CSlice with ptr=null and sets bottom_current_error.
/// Error code 2 indicates invalid Bottom encoding.
fn bottomDecodeBuf(input: [*]u8, len: usize, buf: [*]u8, buf_len: usize) callconv(.c) CSlice {
    // Conservative buffer size check: require buf_len >= input length.
    // Actual decoded output is much smaller due to Bottom's encoding expansion.
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

/// Get current error code and reset error state.
///
/// Returns the current error code and automatically resets bottom_current_error to 0.
/// Call this after each API function to check for errors.
///
/// Error codes:
/// 0 = No error
/// 1 = Memory allocation failure or buffer too small
/// 2 = Invalid Bottom encoding
/// 3 = Windows console UTF-8 not supported
fn getError() callconv(.c) u8 {
    defer bottom_current_error = 0;
    return bottom_current_error;
}

// Error message string constants for human-readable error reporting
const error_no_error_string = "No error";
const error_not_enough_memory_string = "Not enough memory";
const error_invalid_input_string = "Invalid input";
const error_unknown_error_string = "Unknown error";
const error_windows_utf8 = "This windows terminal can't use UTF-8";

/// Get human-readable error message for an error code.
///
/// error_code: The error code returned by bottom_get_error()
///
/// Returns CSlice with static error message string. Do not free this slice.
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

/// Get library version string.
///
/// Returns CSlice with static version string from build_options. Do not free.
fn getVersion() callconv(.c) CSlice {
    const version = options.version;
    return CSlice{ .ptr = version.ptr, .len = version.len };
}

/// Free memory allocated by *_alloc functions.
///
/// slice: The CSlice returned by bottom_encode_alloc or bottom_decode_alloc
///
/// IMPORTANT: Only call this for CSlices returned by *_alloc functions.
/// Do NOT call for CSlices from *_buf functions (they point to caller's buffer).
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
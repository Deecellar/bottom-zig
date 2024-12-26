//! # Bottom Encoder/Decoder C API
//!
//! This module provides C-compatible bindings for encoding and decoding text
//! using the Bottom encoding scheme.
//!
//! ## Error States
//!
//! | Code | Description |
//! |------|-------------|
//! | 0 | No error |
//! | 1 | Not enough memory |
//! | 2 | Invalid input |
//! | 3 | Windows UTF-8 console error |
//!
//! ## Example Usage
//! ```c
//! bottom_init_lib();
//! CSlice result = bottom_encode_alloc("hello", 5);
//! if (bottom_get_error() != 0) {
//!     // Handle error
//! }
//! bottom_free_slice(result);
//! ```

const std = @import("std");
const builtin = @import("builtin");
const options = @import("build_options");
const encode = @import("encoder.zig");
const decode = @import("decoder.zig");
const encoder = encode.BottomEncoder;
const decoder = decode.BottomDecoder;

/// # CSlice
/// 
/// Represents a slice/array that can be passed between C and Zig
/// 
/// ## Fields
/// - `ptr`: Pointer to the data, null if invalid
/// - `len`: Length of the data in bytes
const CSlice = extern struct {
    ptr: ?[*]const u8,
    len: usize,
};

/// Global error state for C API functions
export var bottom_current_error: u8 = 0;

/// # Library Initialization
/// 
/// Initializes the library and sets up necessary system configurations.
/// 
/// ## Platform-Specific Behavior
/// - **Windows**: Attempts to set console to UTF-8 mode
/// 
/// ## Returns
/// `void`
fn bottomInitLib() callconv(.C) void {
    if (builtin.os.tag == .windows) {
        if (std.os.windows.kernel32.SetConsoleOutputCP(65001) == 0) {
            bottom_current_error = 3;
        }
    }
    // If any other consideration can be made, use this function
}

/// # Text Encoding Functions
///
/// ## Encode with Allocation
/// Encodes input text using dynamic memory allocation
///
/// ### Parameters
/// - `input`: Pointer to input bytes
/// - `len`: Length of input
///
/// ### Returns
/// `CSlice` containing encoded result or null ptr on error
///
/// ### Errors
/// - Sets error code 1 on out of memory
fn bottomEncodeAlloc(input: [*]u8, len: usize) callconv(.C) CSlice {
    const allocator = std.heap.c_allocator;
    const res = encoder.encodeAlloc(input[0..len], allocator) catch |err| {
        if (err == error.OutOfMemory) {
            bottom_current_error = 1;
        }
        return CSlice{ .ptr = null, .len = 0 };
    };
    return CSlice{ .ptr = res.ptr, .len = res.len };
}

/// # Buffer Encoding
/// Encodes input text using a pre-allocated buffer
///
/// ## Parameters
/// | Name | Description |
/// |------|-------------|
/// | input | Input text buffer |
/// | len | Length of input in bytes |
/// | buf | Output buffer for encoded result |
/// | buf_len | Size of output buffer |
///
/// ## Returns
/// `CSlice` containing encoded result or null ptr on error
///
/// ## Errors
/// - Sets error 1 if buffer too small
///
/// ## Example
/// ```c
/// char buf[1024];
/// CSlice result = bottom_encode_buf("hello", 5, buf, sizeof(buf));
/// ```
fn bottomEncodeBuf(input: [*]u8, len: usize, buf: [*]u8, buf_len: usize) callconv(.C) CSlice {
    if (buf_len < len) {
        bottom_current_error = 1;
        return CSlice{ .ptr = null, .len = 0 };
    }
    if (buf_len < len * encoder.max_expansion_per_byte) {
        bottom_current_error = 1;
        return CSlice{ .ptr = null, .len = 0 };
    }
    const a = encoder.encode(input[0..len], buf[0..buf_len]);
    return CSlice{ .ptr = a.ptr, .len = a.len };
}

/// # Decode With Allocation
/// Decodes bottom text using dynamic memory allocation
///
/// ## Parameters
/// | Name | Description |
/// |------|-------------|
/// | input | Encoded input buffer |
/// | len | Length of input in bytes |
///
/// ## Returns
/// `CSlice` containing decoded result or null ptr on error
///
/// ## Errors
/// - Sets error 1 on allocation failure
/// - Sets error 2 on invalid input
fn bottomDecodeAlloc(input: [*]u8, len: usize) callconv(.C) CSlice {
    const allocator = std.heap.c_allocator;

    const res = decoder.decodeAlloc(input[0..len], allocator) catch |err| {
        if (err == error.OutOfMemory) {
            bottom_current_error = 1;
        } else if (err == error.invalid_input) {
            bottom_current_error = 2;
        }
        return CSlice{ .ptr = null, .len = 0 };
    };
    return CSlice{ .ptr = res.ptr, .len = res.len };
}

/// # Buffer Decoding
/// Decodes bottom text using provided buffer
///
/// ## Parameters
/// | Name | Description |
/// |------|-------------|
/// | input | Encoded input buffer |
/// | len | Input length in bytes |
/// | buf | Output buffer for decoded result |
/// | buf_len | Size of output buffer |
///
/// ## Returns
/// `CSlice` containing decoded result or null ptr on error
///
/// ## Errors
/// - Sets error 1 if buffer too small
/// - Sets error 2 on invalid input
fn bottomDecodeBuf(input: [*]u8, len: usize, buf: [*]u8, buf_len: usize) callconv(.C) CSlice {
    if (buf_len < len) {
        bottom_current_error = 1;
        return CSlice{ .ptr = null, .len = 0 };
    }
    const a = decoder.decode(input[0..len], buf[0..buf_len]) catch |err| {
        if (err == error.invalid_input) {
            bottom_current_error = 2;
        }
        return CSlice{ .ptr = null, .len = 0 };
    };
    return CSlice{ .ptr = a.ptr, .len = a.len };
}

/// # Error State Management
/// Returns and clears the current error state
/// 
/// ## Returns
/// * `u8` - Current error code (0-3)
///   - 0: No error
///   - 1: Memory error
///   - 2: Invalid input
///   - 3: Windows UTF-8 error
fn getError() callconv(.C) u8 {
    defer {
        bottom_current_error = 0;
    }
    return bottom_current_error;
}

// Error message constants
const error_no_error_string = "No error";
const error_not_enough_memory_string = "Not enough memory";
const error_invalid_input_string = "Invalid input";
const error_unknown_error_string = "Unknown error";
const error_windows_utf8 = "This windows terminal can't use UTF-8";

/// # Error Message Retrieval
/// Returns a human-readable error message for the given error code
///
/// ## Parameters
/// * `error_code`: `u8` - Error code to get message for
///
/// ## Returns
/// * `CSlice` - Contains the corresponding error message string
fn getErrorString(error_code: u8) callconv(.C) CSlice {
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
/// Returns the library version string
///
/// ## Returns
/// * `CSlice` - Contains the version string
fn getVersion() callconv(.C) CSlice {
    const version = options.version;
    return CSlice{ .ptr = version.ptr, .len = version.len };
}

/// # Memory Management
/// Frees memory allocated by encode/decode functions
///
/// ## Parameters
/// * `slice`: `CSlice` - The slice to deallocate
///
/// ## Notes
/// Uses the C allocator for compatibility with C calling convention
fn freeSlice(slice: CSlice) callconv(.C) void {
    const allocator = std.heap.c_allocator;
    if (slice.ptr) |ptr| {
        encoder.encodeDealloc(allocator, ptr[0..slice.len]);
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

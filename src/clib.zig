const std = @import("std");
const builtin = @import("builtin");
const options = @import("build_options");
const encode = @import("encoder.zig");
const decode = @import("decoder.zig");
const encoder = encode.BottomEncoder;
const decoder = decode.BottomDecoder;

const CSlice = extern struct {
    ptr: ?[*]const u8,
    len: usize,
};
/// Error code 0 - no error
/// Error code 1 = not enough memory
/// Error code 2 = Invalid Input
export var bottom_current_error: u8 = 0;

fn bottomInitLib() callconv(.C) void {
    if (builtin.os.tag == .windows) {
        if (std.os.windows.kernel32.SetConsoleOutputCP(65001) == 0) {
            bottom_current_error = 3;
        }
    }
    // If any other consideration can be made, use this function
}

fn bottomEncodeAlloc(input: [*]u8, len: usize) callconv(.C) CSlice {
    var allocator = std.heap.c_allocator;
    var res = encoder.encodeAlloc(input[0..len], allocator) catch |err| {
        if (err == error.OutOfMemory) {
            bottom_current_error = 1;
        }
        return CSlice{ .ptr = null, .len = 0 };
    };
    return CSlice{ .ptr = res.ptr, .len = res.len };
}

fn bottomEncodeBuf(input: [*]u8, len: usize, buf: [*]u8, buf_len: usize) callconv(.C) CSlice {
    if (buf_len < len) {
        bottom_current_error = 1;
        return CSlice{ .ptr = null, .len = 0 };
    }
    if (buf_len < len * encoder.max_expansion_per_byte) {
        bottom_current_error = 1;
        return CSlice{ .ptr = null, .len = 0 };
    }
    var a = encoder.encode(input[0..len], buf[0..buf_len]);
    return CSlice{ .ptr = a.ptr, .len = a.len };
}

fn bottomDecodeAlloc(input: [*]u8, len: usize) callconv(.C) CSlice {
    var allocator = std.heap.c_allocator;

    var res = decoder.decodeAlloc(input[0..len], allocator) catch |err| {
        if (err == error.OutOfMemory) {
            bottom_current_error = 1;
        } else if (err == error.invalid_input) {
            bottom_current_error = 2;
        }
        return CSlice{ .ptr = null, .len = 0 };
    };
    return CSlice{ .ptr = res.ptr, .len = res.len };
}

fn bottomDecodeBuf(input: [*]u8, len: usize, buf: [*]u8, buf_len: usize) callconv(.C) CSlice {
    if (buf_len < len) {
        bottom_current_error = 1;
        return CSlice{ .ptr = null, .len = 0 };
    }
    var a = decoder.decode(input[0..len], buf[0..buf_len]) catch |err| {
        if (err == error.invalid_input) {
            bottom_current_error = 2;
        }
        return CSlice{ .ptr = null, .len = 0 };
    };
    return CSlice{ .ptr = a.ptr, .len = a.len };
}

fn getError() callconv(.C) u8 {
    defer {
        bottom_current_error = 0;
    }
    return bottom_current_error;
}

const error_no_error_string = "No error";
const error_not_enough_memory_string = "Not enough memory";
const error_invalid_input_string = "Invalid input";
const error_unknown_error_string = "Unknown error";
const error_windows_utf8 = "This windows terminal can't use UTF-8";

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

fn getVersion() callconv(.C) CSlice {
    const version = options.version;
    return CSlice{ .ptr = version.ptr, .len = version.len };
}

fn freeSlice(slice: CSlice) callconv(.C) void {
    var allocator = std.heap.c_allocator;

    allocator.free(slice.ptr.?[0..slice.len]);
}

comptime {
    @export(bottomInitLib, .{ .name = "bottom_init_lib", .linkage = .Strong });
    @export(bottomDecodeAlloc, .{ .name = "bottom_decode_alloc", .linkage = .Strong });
    @export(bottomDecodeBuf, .{ .name = "bottom_decode_buf", .linkage = .Strong });
    @export(bottomEncodeAlloc, .{ .name = "bottom_encode_alloc", .linkage = .Strong });
    @export(bottomEncodeBuf, .{ .name = "bottom_encode_buf", .linkage = .Strong });
    @export(getError, .{ .name = "bottom_get_error", .linkage = .Strong });
    @export(getErrorString, .{ .name = "bottom_get_error_string", .linkage = .Strong });
    @export(getVersion, .{ .name = "bottom_get_version", .linkage = .Strong });
    @export(freeSlice, .{ .name = "bottom_free_slice", .linkage = .Strong });
}

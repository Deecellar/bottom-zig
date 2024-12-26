//! # WebAssembly Bottom Encoding Interface
//! 
//! Provides a WebAssembly interface for the bottom-zig encoder/decoder library.
//! Enables web applications to encode/decode bottom text through JavaScript.
//!
//! ## Architecture
//! - Uses WASM memory allocator
//! - Handles text encoding/decoding in chunks
//! - Provides error handling and reporting
//! - Exposes C-style interface for JavaScript
//!
//! ## Usage Example
//! ```js
//! // Initialize WASM module
//! _start();
//! 
//! // Encode text
//! setText("hello");
//! encode();
//! getResult(); // Returns bottom encoding
//! 
//! // Decode bottom text
//! setText("🥺👉👈");
//! decode();
//! getResult(); // Returns original text
//! ```

const std = @import("std");
const encoder = @import("encoder.zig");
const decoder = @import("decoder.zig");

/// Global allocator for WASM memory management
var globalAllocator: std.mem.Allocator = undefined;

/// Exception tracking for error handling
var exception: std.ArrayList([]const u8) = undefined;

/// Logging scope for the WASM module
const scoped = std.log.scoped(.WasmBottomProgram);

/// Buffer size for text processing (128KB)
const buffer_size = 128 * 1024;

/// Error states for JavaScript interaction
const RestartState = enum(u32) {
    bottomify_failed = 1,
    regress_failed = 2, 
    generic_error = 3,
    panic = 4,
};

/// Current error state 
var current_state: RestartState = .generic_error;

/// Initialize the WASM module
/// Sets up memory allocator and exception handling
export fn _start() void {
    globalAllocator = std.heap.wasm_allocator;
    exception = std.ArrayList([]const u8).init(globalAllocator);
}

/// # Bottom Text Decoder
/// Decodes bottom-encoded text into regular UTF-8
///
/// ## Implementation
/// - Processes input in chunks
/// - Uses pre-allocated buffers
/// - Reports errors through RestartState
export fn decode() void {
    var temp: []const u8 = &@as([1]u8, undefined);
    current_state = .regress_failed;
    const len = getTextLen();
    if (len > std.math.maxInt(usize)) {
        scoped.err("Input Too Long", .{});
        return;
    }
    const text = getText()[0..len];
    const buffer: []u8 = globalAllocator.alloc(u8, encoder.BottomEncoder.max_expansion_per_byte * buffer_size) catch |err| {
        scoped.err("Failed with err: {any}", .{err});
        restart(@intFromEnum(current_state));
        return;
    };
    defer globalAllocator.free(buffer);
    const bufferRegress: []u8 = globalAllocator.alloc(u8, buffer_size) catch |err| {
        scoped.err("Failed with err: {any}", .{err});
        restart(@intFromEnum(current_state));
        return;
    };
    defer globalAllocator.free(bufferRegress);

    var bufferInput = std.io.fixedBufferStream(text);
    setResult("", 0);
    while (temp.len != 0) {
        temp = (bufferInput.reader().readUntilDelimiterOrEof(buffer, "👈"[4]) catch |err| {
            scoped.err("Failed with err: {any}", .{err});
            restart(@intFromEnum(current_state));
            return;
        }) orelse &@as([0]u8, undefined);
        if (temp.len > 0) {
            const outbuffer: []u8 = decoder.BottomDecoder.decode(temp, bufferRegress) catch |err| {
                scoped.err("Failed with err: {any}", .{err});
                return;
            };
            appendResult(outbuffer.ptr, @truncate(outbuffer.len));
        }
    }
    hideException();
}

/// # Text Encoder 
/// Encodes regular text into bottom encoding
///
/// ## Implementation
/// - Processes input in chunks
/// - Uses pre-allocated buffers
/// - Reports errors through RestartState
export fn encode() void {
    current_state = .bottomify_failed;
    const len = getTextLen();
    if (len > std.math.maxInt(usize)) {
        const err = error.input_too_long;

        const message = std.fmt.allocPrint(globalAllocator, "Failed with err: {any}", .{err}) catch |err2| {
            scoped.err("Failed with err: {any}", .{err});
            scoped.err("Failed with err: {any}", .{err2});
            restart(@intFromEnum(current_state));
            return;
        };
        appendException(message.ptr, @truncate(message.len));
        return;
    }
    const text = getText()[0..len];
    var buffer: []u8 = globalAllocator.alloc(u8, buffer_size) catch |err| {
        scoped.err("Failed with err: {any}", .{err});
        restart(@intFromEnum(current_state));
        return;
    };
    defer globalAllocator.free(buffer);
    const bufferBottom: []u8 = globalAllocator.alloc(u8, encoder.BottomEncoder.max_expansion_per_byte * buffer_size) catch |err| {
        scoped.err("Failed with err: {any}", .{err});
        restart(@intFromEnum(current_state));
        return;
    };
    defer encoder.BottomEncoder.encodeDealloc(globalAllocator, bufferBottom);
    setResult("", 0);
    var bufferInput = std.io.fixedBufferStream(text);
    var size: usize = 1;
    while (size != 0) {
        size = bufferInput.read(buffer) catch |err| {
            scoped.err("Failed with err: {any}", .{err});
            restart(@intFromEnum(current_state));
            return;
        };
        if (size > 0) {
            const outbuffer: []u8 = encoder.BottomEncoder.encode(buffer[0..size], bufferBottom);
            appendResult(outbuffer.ptr, @truncate(outbuffer.len));
        }
    }

    hideException();
}

/// External JavaScript interface functions
extern fn setResult(ptr: [*]const u8, len: u32) void;
extern fn appendResult(ptr: [*]const u8, len: u32) void;
extern fn appendException(ptr: [*]const u8, len: u32) void;
extern fn hideException() void;
extern fn getText() [*]const u8;
extern fn getTextLen() u32;
extern fn restart(status: u32) void;
pub extern fn logus(ptr: [*]const u8, len: u32) void;

/// Standard options configuration
pub const std_options = blk: {
    var default_options: std.Options = .{};
    default_options.logFn = logFn;
    break :blk default_options;
};

/// # Logging Function
/// Handles error reporting and logging for the WASM module
///
/// ## Parameters
/// - `message_level`: Log severity level
/// - `scope`: Logging scope
/// - `format`: Message format string
/// - `args`: Format arguments
pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    current_state = .generic_error;
    const message = std.fmt.allocPrint(globalAllocator, format, args) catch |err| {
        logus("failed on error:", "failed on error:".len);
        logus(@errorName(err).ptr, @errorName(err).len);
        restart(@intFromEnum(current_state));

        return;
    };
    const to_print = std.fmt.allocPrint(globalAllocator, "{s}-{s}: {s}", .{ @tagName(scope), message_level.asText(), message }) catch |err| {
        logus("failed on error:", "failed on error:".len);
        logus(@errorName(err).ptr, @errorName(err).len);
        restart(@intFromEnum(current_state));

        return;
    };
    appendException(to_print.ptr, @truncate(to_print.len));
    logus(to_print.ptr, @truncate(to_print.len));
    globalAllocator.free(message);
    globalAllocator.free(to_print);
}

/// # Panic Handler
/// Manages unrecoverable errors in the WASM module
///
/// ## Parameters
/// - `msg`: Error message
/// - `stackTrace`: Optional stack trace
/// - `return_address`: Optional return address
pub fn panic(msg: []const u8, stackTrace: ?*std.builtin.StackTrace, return_address: ?usize) noreturn {
    current_state = .panic;
    restart(@intFromEnum(current_state));
    var stack_trace_print: ?[]u8 = null;
    if (stackTrace != null) {
        stack_trace_print = std.fmt.allocPrint(globalAllocator, "{?} {?}", .{ stackTrace, return_address }) catch |err| {
            logus("failed on error:", "failed on error:".len);
            logus(@errorName(err).ptr, @errorName(err).len);
            restart(@intFromEnum(current_state));

            trap();
        };
    }

    const message = std.fmt.allocPrint(globalAllocator, "{s}", .{msg}) catch |err| {
        logus("failed on error:", "failed on error:".len);
        logus(@errorName(err).ptr, @errorName(err).len);
        restart(@intFromEnum(current_state));

        trap();
    };
    const to_print = std.fmt.allocPrint(globalAllocator, "{s}", .{message}) catch |err| {
        logus("failed on error:", "failed on error:".len);
        logus(@errorName(err).ptr, @errorName(err).len);
        restart(@intFromEnum(current_state));
        trap();
    };
    logus(to_print.ptr, @truncate(to_print.len));
    globalAllocator.free(message);
    globalAllocator.free(to_print);
    if (stack_trace_print != null) {
        globalAllocator.free(stack_trace_print.?);
    }
    trap();
}

/// Traps execution in debug mode
inline fn trap() noreturn {
    while (true) {
        @breakpoint();
    }
}

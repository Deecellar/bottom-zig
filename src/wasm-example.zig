//! # WebAssembly Bottom Encoding Interface
//!
//! Provides a WebAssembly interface for the bottom-zig encoder/decoder library.
//! Enables web applications to encode/decode bottom text through JavaScript.
//!
//! ## Memory Management Strategy
//! Static buffers instead of dynamic allocation because:
//! - Avoids allocation failures in resource-constrained WASM environment
//! - Eliminates GC pressure and repeated allocation overhead
//! - Matches CLI implementation for consistency
//! - Prevents expensive module restart cycles
//!
//! ## Error Handling Philosophy
//! Errors logged via appendException() because:
//! - Provides detailed error context to JavaScript UI
//! - RestartState enum allows graceful error recovery
//! - Panics reserved for unrecoverable state corruption only

const std = @import("std");
const bottom = @import("bottom");

/// WASM allocator for dynamic data that exceeds buffer capacity
var globalAllocator: std.mem.Allocator = undefined;

const scoped = std.log.scoped(.WasmBottomProgram);

/// Buffer sizes match CLI implementation for consistent behavior
const buffer_size = 128 * 1024;
const max_expansion_per_byte = 48;

/// Static buffers reduce allocation overhead and prevent restart cycles.
/// For data > 128KB, JavaScript must chunk it and call processChunk() repeatedly.
var decode_buffer: [buffer_size]u8 = undefined;
var encoded_buffer: [max_expansion_per_byte * buffer_size]u8 = undefined;
var output_buffer: [buffer_size]u8 = undefined;
var input_buffer: [buffer_size]u8 = undefined;
var encode_buffer: [max_expansion_per_byte * buffer_size]u8 = undefined;
/// Shared input buffer for JavaScript to write each chunk into
var input_text_buffer: [buffer_size]u8 = undefined;

/// State for multi-chunk processing
const ProcessingState = struct {
    output_allocating: std.Io.Writer.Allocating = undefined,
    initialized: bool = false,
};
var decode_state: ProcessingState = .{};
var encode_state: ProcessingState = .{};

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
export fn _start() void {
    globalAllocator = std.heap.wasm_allocator;
}

/// Initialize decoder for chunked processing. Must call before decodeChunk().
export fn decodeStart() void {
    current_state = .regress_failed;
    if (decode_state.initialized) {
        decode_state.output_allocating.deinit();
    }
    decode_state.output_allocating = std.Io.Writer.Allocating.init(globalAllocator);
    decode_state.initialized = true;
}

/// Process a chunk of bottom-encoded data. Call decodeStart() first.
/// Returns 0 on success, error code otherwise.
export fn decodeChunk(chunk_len: u32) u32 {
    current_state = .regress_failed;
    if (!decode_state.initialized) {
        scoped.err("Must call decodeStart() before decodeChunk()", .{});
        return @intFromEnum(current_state);
    }
    if (chunk_len > buffer_size) {
        scoped.err("Chunk too large (max {d} bytes)", .{buffer_size});
        return @intFromEnum(current_state);
    }

    const text = input_text_buffer[0..chunk_len];
    var input_reader: std.Io.Reader = .fixed(text);
    var decoder = bottom.BottomReader.init(&decode_buffer, &encoded_buffer, &input_reader);

    _ = decoder.reader.streamRemaining(&decode_state.output_allocating.writer) catch |err| {
        scoped.err("Failed to decode chunk: {any}", .{err});
        return @intFromEnum(current_state);
    };

    return 0;
}

/// Finalize decoding and return result. Cleans up state.
export fn decodeFinish() void {
    if (!decode_state.initialized) {
        scoped.err("Must call decodeStart() before decodeFinish()", .{});
        return;
    }
    defer {
        decode_state.output_allocating.deinit();
        decode_state.initialized = false;
    }

    const result = decode_state.output_allocating.writer.buffered();
    setResult(result.ptr, @truncate(result.len));
    hideException();
}

/// Single-shot decode for backwards compatibility with small inputs
export fn decode() void {
    current_state = .regress_failed;
    const len = getTextLen();
    if (len > buffer_size) {
        scoped.err("Input too large ({d} bytes). Use chunked API: decodeStart/Chunk/Finish", .{len});
        return;
    }

    decodeStart();
    const result = decodeChunk(len);
    if (result != 0) {
        if (decode_state.initialized) {
            decode_state.output_allocating.deinit();
            decode_state.initialized = false;
        }
        return;
    }
    decodeFinish();
}

/// Initialize encoder for chunked processing. Must call before encodeChunk().
export fn encodeStart() void {
    current_state = .bottomify_failed;
    if (encode_state.initialized) {
        encode_state.output_allocating.deinit();
    }
    encode_state.output_allocating = std.Io.Writer.Allocating.init(globalAllocator);
    encode_state.initialized = true;
}

/// Process a chunk of plain text data. Call encodeStart() first.
/// Returns 0 on success, error code otherwise.
export fn encodeChunk(chunk_len: u32) u32 {
    current_state = .bottomify_failed;
    if (!encode_state.initialized) {
        scoped.err("Must call encodeStart() before encodeChunk()", .{});
        return @intFromEnum(current_state);
    }
    if (chunk_len > buffer_size) {
        scoped.err("Chunk too large (max {d} bytes)", .{buffer_size});
        return @intFromEnum(current_state);
    }

    const text = input_text_buffer[0..chunk_len];
    var input_reader: std.Io.Reader = .fixed(text);
    var encoder = bottom.BottomWriter.init(&encode_buffer, &encode_state.output_allocating.writer);

    _ = input_reader.streamRemaining(&encoder.writer) catch |err| {
        scoped.err("Failed to encode chunk: {any}", .{err});
        return @intFromEnum(current_state);
    };

    encoder.writer.flush() catch |err| {
        scoped.err("Failed to flush encoder: {any}", .{err});
        return @intFromEnum(current_state);
    };

    return 0;
}

/// Finalize encoding and return result. Cleans up state.
export fn encodeFinish() void {
    if (!encode_state.initialized) {
        scoped.err("Must call encodeStart() before encodeFinish()", .{});
        return;
    }
    defer {
        encode_state.output_allocating.deinit();
        encode_state.initialized = false;
    }

    const result = encode_state.output_allocating.writer.buffered();
    setResult(result.ptr, @truncate(result.len));
    hideException();
}

/// Single-shot encode for backwards compatibility with small inputs
export fn encode() void {
    current_state = .bottomify_failed;
    const len = getTextLen();
    if (len > buffer_size) {
        scoped.err("Input too large ({d} bytes). Use chunked API: encodeStart/Chunk/Finish", .{len});
        return;
    }

    encodeStart();
    const result = encodeChunk(len);
    if (result != 0) {
        if (encode_state.initialized) {
            encode_state.output_allocating.deinit();
            encode_state.initialized = false;
        }
        return;
    }
    encodeFinish();
}

/// Get pointer to input text buffer for JavaScript to write to
export fn getInputBuffer() [*]u8 {
    return &input_text_buffer;
}

/// Get the maximum size of the input buffer
export fn getInputBufferSize() u32 {
    return buffer_size;
}

/// External JavaScript interface functions (implemented in JS, called from WASM)
///
/// setResult: Pass encoded/decoded result back to JavaScript
/// appendResult: Append additional data to result (for streaming)
/// appendException: Report error message to JavaScript UI
/// hideException: Clear error display
/// getText: Get pointer to input text from JavaScript (deprecated, use getInputBuffer)
/// getTextLen: Get length of input text from JavaScript
/// restart: Signal error state to JavaScript (triggers UI update)
/// logus: Console logging from WASM to JavaScript
extern fn setResult(ptr: [*]const u8, len: u32) void;
extern fn appendResult(ptr: [*]const u8, len: u32) void;
extern fn appendException(ptr: [*]const u8, len: u32) void;
extern fn hideException() void;
extern fn getText() [*]const u8;
extern fn getTextLen() u32;
extern fn restart(status: u32) void;
pub extern fn logus(ptr: [*]const u8, len: u32) void;

/// Standard options configuration
pub const std_options: std.Options = .{
    .logFn = logFn,
};

/// # Logging Function
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
    defer globalAllocator.free(message);
    
    const to_print = std.fmt.allocPrint(globalAllocator, "{s}-{s}: {s}", .{ 
        @tagName(scope), 
        message_level.asText(), 
        message 
    }) catch |err| {
        logus("failed on error:", "failed on error:".len);
        logus(@errorName(err).ptr, @errorName(err).len);
        restart(@intFromEnum(current_state));
        return;
    };
    defer globalAllocator.free(to_print);
    
    appendException(to_print.ptr, @truncate(to_print.len));
    logus(to_print.ptr, @truncate(to_print.len));
}

/// # Panic Handler
pub fn panic(msg: []const u8, stackTrace: ?*std.builtin.StackTrace, return_address: ?usize) noreturn {
    current_state = .panic;
    
    if (stackTrace) |st| {
        const stack_trace_print = std.fmt.allocPrint(globalAllocator, "{any} {any}", .{ st, return_address }) catch {
            logus("failed to format stack trace", "failed to format stack trace".len);
            restart(@intFromEnum(current_state));
            trap();
        };
        defer globalAllocator.free(stack_trace_print);
        logus(stack_trace_print.ptr, @truncate(stack_trace_print.len));
    }
    
    logus(msg.ptr, @truncate(msg.len));
    restart(@intFromEnum(current_state));
    trap();
}

/// Traps execution
inline fn trap() noreturn {
    while (true) {
        @breakpoint();
    }
}
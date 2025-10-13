//! # WebAssembly Bottom Encoding Interface
//! 
//! Provides a WebAssembly interface for the bottom-zig encoder/decoder library.
//! Enables web applications to encode/decode bottom text through JavaScript.

const std = @import("std");
const bottom = @import("bottom");

/// Global allocator for WASM memory management
var globalAllocator: std.mem.Allocator = undefined;

/// Logging scope for the WASM module
const scoped = std.log.scoped(.WasmBottomProgram);

/// Buffer size for text processing (128KB)
const buffer_size = 128 * 1024;
const max_expansion_per_byte = 48;

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

/// # Bottom Text Decoder
/// Decodes bottom-encoded text into regular UTF-8
export fn decode() void {
    current_state = .regress_failed;
    const len = getTextLen();
    if (len > std.math.maxInt(usize)) {
        scoped.err("Input Too Long", .{});
        return;
    }
    const text = getText()[0..len];
    
    const decode_buffer = globalAllocator.alloc(u8, buffer_size) catch |err| {
        scoped.err("Failed to allocate decode buffer: {any}", .{err});
        restart(@intFromEnum(current_state));
        return;
    };
    defer globalAllocator.free(decode_buffer);
    
    const encoded_buffer = globalAllocator.alloc(u8, max_expansion_per_byte * buffer_size) catch |err| {
        scoped.err("Failed to allocate encoded buffer: {any}", .{err});
        restart(@intFromEnum(current_state));
        return;
    };
    defer globalAllocator.free(encoded_buffer);
    
    const output_buffer = globalAllocator.alloc(u8, buffer_size) catch |err| {
        scoped.err("Failed to allocate output buffer: {any}", .{err});
        restart(@intFromEnum(current_state));
        return;
    };
    defer globalAllocator.free(output_buffer);
    
    // Create input reader from text
    var input_reader: std.Io.Reader = .fixed(text);
    
    // Create decoder
    var decoder = bottom.BottomReader.init(decode_buffer, encoded_buffer, &input_reader);
    
    // Create output writer (allocating)
    var output_allocating = std.Io.Writer.Allocating.init(globalAllocator);
    defer output_allocating.deinit();
    
    // Stream all data from decoder to output
    _ = decoder.reader.streamRemaining(&output_allocating.writer) catch |err| {
        scoped.err("Failed to decode: {any}", .{err});
        restart(@intFromEnum(current_state));
        return;
    };
    
    const result = output_allocating.writer.buffered();
    setResult(result.ptr, @truncate(result.len));
    hideException();
}

/// # Text Encoder 
/// Encodes regular text into bottom encoding
export fn encode() void {
    current_state = .bottomify_failed;
    const len = getTextLen();
    if (len > std.math.maxInt(usize)) {
        scoped.err("Input Too Long", .{});
        restart(@intFromEnum(current_state));
        return;
    }
    const text = getText()[0..len];
    
    const input_buffer = globalAllocator.alloc(u8, buffer_size) catch |err| {
        scoped.err("Failed to allocate input buffer: {any}", .{err});
        restart(@intFromEnum(current_state));
        return;
    };
    defer globalAllocator.free(input_buffer);
    
    const encode_buffer = globalAllocator.alloc(u8, max_expansion_per_byte * buffer_size) catch |err| {
        scoped.err("Failed to allocate encode buffer: {any}", .{err});
        restart(@intFromEnum(current_state));
        return;
    };
    defer globalAllocator.free(encode_buffer);
    
    // Create input reader from text
    var input_reader: std.Io.Reader = .fixed(text);
    
    // Create output writer (allocating)
    var output_allocating = std.Io.Writer.Allocating.init(globalAllocator);
    defer output_allocating.deinit();
    
    // Create encoder
    var encoder = bottom.BottomWriter.init(encode_buffer, &output_allocating.writer);
    
    // Stream all data from input to encoder
    _ = input_reader.streamRemaining(&encoder.writer) catch |err| {
        scoped.err("Failed to read input: {any}", .{err});
        restart(@intFromEnum(current_state));
        return;
    };
    
    // Flush encoder
    encoder.writer.flush() catch |err| {
        scoped.err("Failed to flush encoder: {any}", .{err});
        restart(@intFromEnum(current_state));
        return;
    };
    
    const result = output_allocating.writer.buffered();
    setResult(result.ptr, @truncate(result.len));
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
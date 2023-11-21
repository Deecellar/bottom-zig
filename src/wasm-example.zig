const std = @import("std");
const encoder = @import("encoder.zig");
const decoder = @import("decoder.zig");
var globalAllocator: std.mem.Allocator = undefined;
var exception: std.ArrayList([]const u8) = undefined;
const scoped = std.log.scoped(.WasmBottomProgram);
const buffer_size = 128 * 1024;
const RestartState = enum(u32) {
    bottomify_failed = 1,
    regress_failed = 2,
    generic_error = 3,
    panic = 4,
};
var current_state: RestartState = .generic_error;

export fn _start() void {
    globalAllocator = std.heap.wasm_allocator;
    exception = std.ArrayList([]const u8).init(globalAllocator);
}

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
    defer globalAllocator.free(bufferBottom);
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

extern fn setResult(ptr: [*]const u8, len: u32) void;
extern fn appendResult(ptr: [*]const u8, len: u32) void;
extern fn appendException(ptr: [*]const u8, len: u32) void;
extern fn hideException() void;
extern fn getText() [*]const u8;
extern fn getTextLen() u32;
extern fn restart(status: u32) void;
pub extern fn logus(ptr: [*]const u8, len: u32) void;
pub const std_options = struct {
    pub fn logFn(
        comptime message_level: std.log.Level,
        comptime scope: @Type(.EnumLiteral),
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
};

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

inline fn trap() noreturn {
    while (true) {
        @breakpoint();
    }
}

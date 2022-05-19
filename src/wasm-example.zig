const std = @import("std");
const encoder = @import("encoder.zig");
const decoder = @import("decoder.zig");
var globalAllocator: std.mem.Allocator = undefined;
var exception: std.ArrayList([]const u8) = undefined;
const scoped = std.log.scoped(.WasmBottomProgram);
const RestartState = enum(u32) {
    bottomify_failed = 1,
    regress_failed = 2,
    generic_error = 3,
    panic = 4,
};
var current_state: RestartState = .generic_error;

export fn _start() void {
    globalAllocator = std.heap.page_allocator;
    exception = std.ArrayList([]const u8).init(globalAllocator);
}

export fn decode() void {
    current_state = .regress_failed;
    var len = getTextLen();
    if(len > std.math.maxInt(usize)) {
        var err = error.input_too_long;
        var message = std.fmt.allocPrint(globalAllocator, "Failed with err: {any}", .{err}) catch |err2| {
            scoped.err("Failed with err: {any}", .{err});
            scoped.err("Failed with err: {any}", .{err2});
            restart(@enumToInt(current_state));
            return;
        };
        appendException(message.ptr, @truncate(u32, message.len));
        return;
    }
    var text = getText()[0..len];
    var decoded = decoder.BottomDecoder.decodeAlloc(text, globalAllocator) catch |err| {
        var message = std.fmt.allocPrint(globalAllocator, "Failed with err: {any}", .{err}) catch |err2| {
            scoped.err("Failed with err: {any}", .{err});
            scoped.err("Failed with err: {any}", .{err2});
            restart(@enumToInt(current_state));
            return;
        };
        appendException(message.ptr, @truncate(u32, message.len));
        return;
    };
    defer globalAllocator.free(decoded);
    setResult(decoded.ptr, decoded.len);
    hideException();
}
export fn encode() void {
    current_state = .bottomify_failed;
    var len = getTextLen();
    if(len > std.math.maxInt(usize)) {
        var err = error.input_too_long;

        var message = std.fmt.allocPrint(globalAllocator, "Failed with err: {any}", .{err}) catch |err2| {
            scoped.err("Failed with err: {any}", .{err});
            scoped.err("Failed with err: {any}", .{err2});
            restart(@enumToInt(current_state));
            return;
        };
        appendException(message.ptr, @truncate(u32, message.len));
        return;
    }
    var text = getText()[0..len];
    var encoded = encoder.BottomEncoder.encodeAlloc(text, globalAllocator) catch |err| {
        var message = std.fmt.allocPrint(globalAllocator, "Failed with err: {any}", .{err}) catch |err2| {
            scoped.err("Failed with err: {any}", .{err});
            scoped.err("Failed with err: {any}", .{err2});
            restart(@enumToInt(current_state));
            return;
        };
        appendException(message.ptr, @truncate(u32, message.len));

        globalAllocator.free(message);
        return;
    };
    defer globalAllocator.free(encoded);
    setResult(encoded.ptr, @truncate(u32, encoded.len));
    hideException();
}

extern fn setResult(ptr: [*]const u8, len: u32) void;
extern fn appendException(ptr: [*]const u8, len: u32) void;
extern fn hideException() void;
extern fn getText() [*]const u8;
extern fn getTextLen() u32;
extern fn restart(status: u32) void;
pub extern fn logus(ptr: [*]const u8, len: u32) void;

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    current_state = .generic_error;
    var message = std.fmt.allocPrint(globalAllocator, format, args) catch |err| {
        logus("failed on error:", "failed on error:".len);
        logus(@errorName(err).ptr, @errorName(err).len);
        restart(@enumToInt(current_state));

        return;
    };
    var to_print = std.fmt.allocPrint(globalAllocator, "{s}-{s}: {s}", .{ @tagName(scope), message_level.asText(), message }) catch |err| {
        logus("failed on error:", "failed on error:".len);
        logus(@errorName(err).ptr, @errorName(err).len);
        restart(@enumToInt(current_state));

        return;
    };
    logus(to_print.ptr, @truncate(u32, to_print.len));
    globalAllocator.free(message);
    globalAllocator.free(to_print);
}

pub fn panic(msg: []const u8, stackTrace: ?*std.builtin.StackTrace) noreturn {
    current_state = .panic;
    restart(@enumToInt(current_state));
    var stack_trace_print: ?[]u8 = null;
    if (stackTrace != null) {
        stack_trace_print = std.fmt.allocPrint(globalAllocator, "{s}", .{stackTrace}) catch |err| {
            logus("failed on error:", "failed on error:".len);
            logus(@errorName(err).ptr, @errorName(err).len);
            restart(@enumToInt(current_state));

            trap();
        };
    }

    var message = std.fmt.allocPrint(globalAllocator, "{s}", .{msg}) catch |err| {
        logus("failed on error:", "failed on error:".len);
        logus(@errorName(err).ptr, @errorName(err).len);
        restart(@enumToInt(current_state));

        trap();
    };
    var to_print = std.fmt.allocPrint(globalAllocator, "{s}", .{message}) catch |err| {
        logus("failed on error:", "failed on error:".len);
        logus(@errorName(err).ptr, @errorName(err).len);
        restart(@enumToInt(current_state));
        trap();
    };
    logus(to_print.ptr, @truncate(u32, to_print.len));
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


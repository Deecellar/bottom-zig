const std = @import("std");
const encoder = @import("encoder.zig");
const decoder = @import("decoder.zig");
var globalAllocator: std.mem.Allocator = undefined;
var exception: std.ArrayList([]const u8) = undefined;
const scoped = std.log.scoped(.WasmBottomProgram);

export fn _start() void {
    globalAllocator = std.heap.page_allocator;
    exception = std.ArrayList([]const u8).init(globalAllocator);
}

export fn decode() void {
    var text = getText()[0..getTextLen()];
    var decoded = decoder.BottomDecoder.decodeAlloc(text, globalAllocator) catch |err| {
        var message = std.fmt.allocPrint(globalAllocator, "Failed with err: {any}", .{err}) catch |err2| {
            scoped.err("Failed with err: {any}", .{err});
            scoped.err("Failed with err: {any}", .{err2});
            return;
        };
        appendException(message.ptr, @truncate(u32, message.len));
        return;
    };
    setResult(decoded.ptr, decoded.len);
    hideException();
}
export fn encode() void {
    var text = getText()[0..getTextLen()];
    var encoded = encoder.BottomEncoder.encodeAlloc(text, globalAllocator) catch |err| {
        var message = std.fmt.allocPrint(globalAllocator, "Failed with err: {any}", .{err}) catch |err2| {
            scoped.err("Failed with err: {any}", .{err});
            scoped.err("Failed with err: {any}", .{err2});
            return;
        };
        appendException(message.ptr, @truncate(u32, message.len));

        globalAllocator.free(message);
        return;
    };
    setResult(encoded.ptr, @truncate(u32, encoded.len));
    hideException();
}

extern fn setResult(ptr: [*]const u8, len: u32) void;
extern fn appendException(ptr: [*]const u8, len: u32) void;
extern fn hideException() void;
extern fn getText() [*]const u8;
extern fn getTextLen() u32;
pub extern fn logus(ptr: [*]const u8, len: u32) void;

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    var message = std.fmt.allocPrint(globalAllocator, format, args) catch |err| {
        logus("failed on error:", "failed on error:".len);
        logus(@errorName(err).ptr, @errorName(err).len);
        return;
    };
    var to_print = std.fmt.allocPrint(globalAllocator, "{s}-{s}: {s}", .{ @tagName(scope), message_level.asText(), message }) catch |err| {
        logus("failed on error:", "failed on error:".len);
        logus(@errorName(err).ptr, @errorName(err).len);
        return;
    };
    logus(to_print.ptr, @truncate(u32, to_print.len));
    globalAllocator.free(message);
    globalAllocator.free(to_print);
}

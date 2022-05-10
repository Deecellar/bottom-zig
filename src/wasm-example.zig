const std = @import("std");
const encoder = @import("encoder.zig");
const decoder = @import("decoder.zig");

var globalAllocator: std.mem.Allocator = undefined;
var exception: std.ArrayList([]const u8) = undefined;

export fn _start() void {
    globalAllocator = std.heap.page_allocator;
    exception = std.ArrayList([]const u8).init(globalAllocator);
}

export fn decode() void {
    var text = std.mem.span(getText());
    var decoded = decoder.BottomDecoder.decodeAlloc(text, globalAllocator) catch |err| {
        var message = std.fmt.allocPrint(globalAllocator, "Failed with err: {any}", .{err}) catch |err2| {
            logus("failed on error:", "failed on error:".len);
            std.log.err("Failed with err: {any}", .{err});
            std.log.err("Failed with err: {any}", .{err2});
            return;
        };
        appendException(message.ptr, @truncate(u32, message.len));
        return;
    };
    setResult(decoded.ptr, decoded.len);
    hideException();
}
export fn encode() void {
    var text = std.mem.span(getText());
    var encoded = encoder.BottomEncoder.encodeAlloc(text, globalAllocator) catch |err| {
        var message = std.fmt.allocPrint(globalAllocator, "Failed with err: {any}", .{err}) catch |err2| {
            logus("failed on error:", "failed on error:".len);
            std.log.err("Failed with err: {any}", .{err});
            std.log.err("Failed with err: {any}", .{err2});
            return;
        };
        appendException(message.ptr, @truncate(u32, message.len));

        globalAllocator.free(message);
        return;
    };
    setResult(encoded.ptr, encoded.len);
    hideException();
}

extern fn setResult(ptr: [*]const u8, len: u32) void;
extern fn appendException(ptr: [*]const u8, len: u32) void;
extern fn hideException() void;
extern fn getText() [*:0]const u8;
pub extern fn logus(ptr: [*]const u8, len: u32) void;

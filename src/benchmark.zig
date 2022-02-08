const std = @import("std");
const encode = @import("encoder.zig");
const decode = @import("decoder.zig");
// Make proper Benchmarking
pub fn main() !void {
    var tiem: std.time.Timer = undefined;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var string: []u8 = try gpa.allocator().alloc(u8, 1024 * 1024 * 10);
    var string2: []u8 = try gpa.allocator().alloc(u8, 1024 * 1024 * 10);
    var buffer: []u8 = try gpa.allocator().alloc(u8, 1024 * 1024 * 400);
    var rand = std.rand.DefaultPrng.init(491249);
    rand.fill(string);
    var accum: u64 = 0;
    tiem = try std.time.Timer.start();
    _ = encode.BottomEncoder.encode(string, buffer) catch unreachable;
    accum = tiem.lap();
    try std.io.getStdOut().writer().print("speed {d}\n", .{accum});
    tiem = try std.time.Timer.start();
    _ = decode.BottomDecoder.decode(buffer, string2) catch unreachable;
    accum = tiem.lap();
    try std.io.getStdOut().writer().print("speed {d}\n", .{accum});
    tiem.reset();
    try std.testing.expectEqualStrings(string, string2);
}
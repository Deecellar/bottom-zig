const std = @import("std");
const encode = @import("encoder.zig");
const decode = @import("decoder.zig");
// Make proper Benchmarking
pub fn main() !void {
    var time: std.time.Timer = undefined;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    const string: []u8 = try gpa.allocator().alloc(u8, 1024 * 1024 * 10);
    var string2: []u8 = try gpa.allocator().alloc(u8, 1024 * 1024 * 10);
    var buffer: []u8 = try gpa.allocator().alloc(u8, 1024 * 1024 * 400);
    var rand = std.rand.DefaultPrng.init(491249);
    rand.fill(string);
    var accum: u64 = 0;
    time = try std.time.Timer.start();
    buffer = encode.BottomEncoder.encode(string, buffer);
    accum = time.lap();
    try std.io.getStdOut().writer().print("speed {d}\n", .{accum / std.time.ns_per_ms});
    const size = string.len / 40;
    rand.fill(buffer[0..size]);
    const out = try encode.BottomEncoder.encodeAlloc(buffer[0..size], gpa.allocator());
    time.reset();
    string2 = try decode.BottomDecoder.decode(out, string2);
    accum = time.lap();
    try std.io.getStdOut().writer().print("speed {d}\n", .{accum / std.time.ns_per_ms});
    time.reset();
}

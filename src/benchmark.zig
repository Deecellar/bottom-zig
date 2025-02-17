const std = @import("std");

const decode = @import("decoder.zig");
const encode = @import("encoder.zig");

const BenchConfig = struct {
    iterations: usize = 10,
    warmup_runs: usize = 3,
    sizes: []const usize = &[_]usize{ 1024, 1024 * 1024, 10 * 1024 * 1024 },
};

const BenchResult = struct {
    input_size: usize,
    output_size: usize,
    min_ns: u64,
    max_ns: u64,
    avg_ns: u64,
    throughput_mbs: f64,

    fn formatDuration(ns: u64, writer: anytype) !void {
        if (ns < std.time.ns_per_ms) {
            try writer.print("{d}ns", .{ns});
        } else {
            try writer.print("{d}ms", .{ns / std.time.ns_per_ms});
        }
    }
};

const Benchmark = struct {
    config: BenchConfig,
    allocator: std.mem.Allocator,
    rng: std.Random.DefaultPrng,

    pub fn init(allocator: std.mem.Allocator, config: BenchConfig) Benchmark {
        var buffer: [8]u8 = undefined;
        const random_seed: u64 = seed: {
            std.posix.getrandom(&buffer) catch break :seed @bitCast(std.time.microTimestamp());
            break :seed @bitCast(buffer);
        };
        return .{
            .config = config,
            .allocator = allocator,
            .rng = std.Random.DefaultPrng.init(random_seed),
        };
    }

    fn runSingleBench(self: *Benchmark, data: []const u8, comptime op: enum { Encode, Decode }) !BenchResult {
        var timer = try std.time.Timer.start();
        var times = std.ArrayList(u64).init(self.allocator);
        defer times.deinit();

        // Arena for warmup runs
        var arena = std.heap.ArenaAllocator.init(self.allocator);

        // Warmup runs
        for (0..self.config.warmup_runs) |_| {
            if (op == .Encode) {
                _ = try encode.BottomEncoder.encodeAlloc(data, arena.allocator());
            } else {
                _ = try decode.BottomDecoder.decodeAlloc(data, arena.allocator());
            }
        }
        arena.deinit();
        var decoded_data: []const u8 = undefined;
        // Actual benchmark runs
        for (0..self.config.iterations) |_| {
            const buffer = try self.allocator.alloc(u8, data.len * if (op == .Encode) encode.BottomEncoder.max_expansion_per_byte else 1);
            defer self.allocator.free(buffer);

            timer.reset();
            if (op == .Encode) {
                decoded_data = encode.BottomEncoder.encode(data, buffer);
            } else {
                decoded_data = try decode.BottomDecoder.decode(data, buffer);
            }
            try times.append(timer.lap()); // Store raw nanoseconds
        }

        // Calculate statistics
        var min: u64 = std.math.maxInt(u64);
        var max: u64 = 0;
        var sum: u64 = 0;

        for (times.items) |t| {
            min = @min(min, t);
            max = @max(max, t);
            sum += t;
        }

        const output_size = if (op == .Encode)
            data.len * encode.BottomEncoder.max_expansion_per_byte
        else
            decoded_data.len;

        const input_size = if (op == .Encode) data.len else output_size;

        const avg = sum / times.items.len;
        const throughput = @as(f64, @floatFromInt(input_size)) / (@as(f64, @floatFromInt(avg)) / 1_000_000_000.0) / 1024.0 / 1024.0;

        return BenchResult{
            .input_size = input_size,
            .output_size = output_size,
            .min_ns = min,
            .max_ns = max,
            .avg_ns = avg,
            .throughput_mbs = throughput,
        };
    }
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = BenchConfig{};
    var benchmark = Benchmark.init(allocator, config);

    const stdout = std.io.getStdOut().writer();
    try stdout.print("\nRunning Bottom encoding/decoding benchmarks...\n", .{});

    for (config.sizes) |size| {
        const data = try allocator.alloc(u8, size);
        defer allocator.free(data);
        benchmark.rng.random().bytes(data);

        try stdout.print("\nBenchmarking size: {d} bytes\n", .{size});

        const encode_result = try benchmark.runSingleBench(data, .Encode);
        try stdout.print("Encode: min=", .{});
        try BenchResult.formatDuration(encode_result.min_ns, stdout);
        try stdout.print(" max=", .{});
        try BenchResult.formatDuration(encode_result.max_ns, stdout);
        try stdout.print(" avg=", .{});
        try BenchResult.formatDuration(encode_result.avg_ns, stdout);
        try stdout.print(" throughput={d:.2}MB/s\n", .{encode_result.throughput_mbs});

        const encoded = try encode.BottomEncoder.encodeAlloc(data, allocator);
        defer encode.BottomEncoder.encodeDealloc(allocator, encoded);

        const decode_result = try benchmark.runSingleBench(encoded, .Decode);
        try stdout.print("Decode: min=", .{});
        try BenchResult.formatDuration(decode_result.min_ns, stdout);
        try stdout.print(" max=", .{});
        try BenchResult.formatDuration(decode_result.max_ns, stdout);
        try stdout.print(" avg=", .{});
        try BenchResult.formatDuration(decode_result.avg_ns, stdout);
        try stdout.print(" throughput={d:.2}MB/s\n", .{decode_result.throughput_mbs});
    }
}

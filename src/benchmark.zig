//! # Bottom Encoding Benchmark Suite
//!
//! Measures encoding/decoding performance across various data sizes with
//! configurable buffer sizes and iteration counts. Provides min/max/avg
//! timing statistics and throughput measurements.

const std = @import("std");
const Io = std.Io;
const encoder_writer = @import("encoder_writer.zig");
const decoder_reader = @import("decoder_reader.zig");

const BenchConfig = struct {
    // Number of timed iterations per benchmark. 10 provides stable results
    // without excessive runtime. Increase for more precision.
    iterations: usize = 10,

    // Warmup runs to stabilize CPU caches and branch predictors before timing.
    // 3 runs is sufficient to reach steady-state performance on modern CPUs.
    warmup_runs: usize = 3,

    // Test data sizes: 1KB, 1MB, 10MB, 50MB, 100MB
    // Covers range from cache-resident to memory-bound workloads.
    // TODO: Add 1GB test size for long-running stress testing.
    sizes: []const usize = &[_]usize{ 1024, 1024 * 1024, 10 * 1024 * 1024, 50 * 1024 * 1024 , 100 * 1024 * 1024 },

    // Buffer sizes for benchmark runs. Not tuned for optimal performance.
    writer_buffer_size: usize = 64 * 1024,
    reader_buffer_size: usize = 64 * 1024,

    // Decoder encoded buffer: 64KB * 12 = 768KB
    // TODO: Verify this sizing is adequate for worst-case encoding expansion.
    reader_encoded_buffer_size: usize = 64 * 1024 * 12,
};

const BenchResult = struct {
    input_size: usize,
    output_size: usize,
    min_ns: u64,
    max_ns: u64,
    avg_ns: u64,
    throughput_mbs: f64,

    fn formatDuration(ns: u64, writer: *std.Io.Writer) !void {
        if (ns < std.time.ns_per_ms) {
            try writer.print("{d}ns", .{ns});
        } else if (ns < std.time.ns_per_s) {
            try writer.print("{d:.2}ms", .{@as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(std.time.ns_per_ms))});
        } else {
            try writer.print("{d:.2}s", .{@as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(std.time.ns_per_s))});
        }
    }
};

const Benchmark = struct {
    config: BenchConfig,
    allocator: std.mem.Allocator,
    io: Io,
    rng: std.Random.DefaultPrng,
    pub fn init(allocator: std.mem.Allocator, io: Io, config: BenchConfig) Benchmark {
        var seed_buf: [8]u8 = undefined;
        std.Io.random(io, &seed_buf);
        const random_seed: u64 = @bitCast(seed_buf);
        return .{
            .config = config,
            .allocator = allocator,
            .io = io,
            .rng = std.Random.DefaultPrng.init(random_seed),
        };
    }

    fn benchEncode(self: *Benchmark, data: []const u8) !BenchResult {
        var times: std.ArrayList(u64) = .empty;
        defer times.deinit(self.allocator);

        // Warmup runs
        for (0..self.config.warmup_runs) |_| {
            var sink_writer = std.Io.Writer.Allocating.init(self.allocator);
            defer sink_writer.deinit();

            const encoder_buffer = try self.allocator.alloc(u8, self.config.writer_buffer_size);
            defer self.allocator.free(encoder_buffer);

            var encoder = encoder_writer.BottomWriter.init(encoder_buffer, &sink_writer.writer);

            try encoder.writer.writeAll(data);
            try encoder.writer.flush();
        }

        var output_size: usize = 0;

        // Actual benchmark runs
        for (0..self.config.iterations) |_| {
            var sink_writer = std.Io.Writer.Allocating.init(self.allocator);
            defer sink_writer.deinit();

            const encoder_buffer = try self.allocator.alloc(u8, self.config.writer_buffer_size);
            defer self.allocator.free(encoder_buffer);

            var encoder = encoder_writer.BottomWriter.init(encoder_buffer, &sink_writer.writer);

            const start_ts = Io.Clock.Timestamp.now(self.io, .awake);
            try encoder.writer.writeAll(data);
            try encoder.writer.flush();
            const elapsed: u64 = @intCast(start_ts.untilNow(self.io).raw.nanoseconds);

            output_size = sink_writer.written().len;
            try times.append(self.allocator, elapsed);
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

        const avg = sum / times.items.len;
        const throughput = @as(f64, @floatFromInt(output_size)) / (@as(f64, @floatFromInt(avg)) / 1_000_000_000.0) / 1024.0 / 1024.0;

        return BenchResult{
            .input_size = data.len,
            .output_size = output_size,
            .min_ns = min,
            .max_ns = max,
            .avg_ns = avg,
            .throughput_mbs = throughput,
        };
    }

    fn benchDecode(self: *Benchmark, encoded_data: []const u8) !BenchResult {
        var times: std.ArrayList(u64) = .empty;
        defer times.deinit(self.allocator);

        // Warmup runs
        for (0..self.config.warmup_runs) |_| {
            var source_reader: std.Io.Reader = .fixed(encoded_data);

            const decode_buffer = try self.allocator.alloc(u8, self.config.reader_buffer_size);
            defer self.allocator.free(decode_buffer);

            const encoded_buffer = try self.allocator.alloc(u8, self.config.reader_encoded_buffer_size);
            defer self.allocator.free(encoded_buffer);

            var decoder = decoder_reader.BottomReader.init(decode_buffer, encoded_buffer, &source_reader);

            _ = try decoder.reader.allocRemaining(self.allocator, .unlimited);
        }

        var output_size: usize = 0;

        // Actual benchmark runs
        for (0..self.config.iterations) |_| {
            var source_reader: std.Io.Reader = .fixed(encoded_data);

            const decode_buffer = try self.allocator.alloc(u8, self.config.reader_buffer_size);
            defer self.allocator.free(decode_buffer);

            const encoded_buffer = try self.allocator.alloc(u8, self.config.reader_encoded_buffer_size);
            defer self.allocator.free(encoded_buffer);

            var decoder = decoder_reader.BottomReader.init(decode_buffer, encoded_buffer, &source_reader);

            const start_ts = Io.Clock.Timestamp.now(self.io, .awake);
            const result = try decoder.reader.allocRemaining(self.allocator, .unlimited);
            const elapsed: u64 = @intCast(start_ts.untilNow(self.io).raw.nanoseconds);
            output_size = result.len;
            self.allocator.free(result);

            try times.append(self.allocator, elapsed);
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

        const avg = sum / times.items.len;
        const throughput = @as(f64, @floatFromInt(encoded_data.len)) / (@as(f64, @floatFromInt(avg)) / 1_000_000_000.0) / 1024.0 / 1024.0;

        return BenchResult{
            .input_size = encoded_data.len,
            .output_size = output_size,
            .min_ns = min,
            .max_ns = max,
            .avg_ns = avg,
            .throughput_mbs = throughput,
        };
    }
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    const config = BenchConfig{};
    var benchmark = Benchmark.init(allocator, init.io, config);
    var stdout_buffer: [0x100]u8 = undefined;
    var stdout_file_writer = Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;
    try stdout.print("\nRunning Bottom encoding/decoding benchmarks (streaming)...\n", .{});
    try stdout.print("Writer buffer: {d} bytes, Reader buffer: {d} bytes, Encoded buffer: {d} bytes\n", .{
        config.writer_buffer_size,
        config.reader_buffer_size,
        config.reader_encoded_buffer_size,
    });

    for (config.sizes) |size| {
        const data = try allocator.alloc(u8, size);
        defer allocator.free(data);
        benchmark.rng.random().bytes(data);

        try stdout.print("\n--- Benchmarking size: {d} bytes ---\n", .{size});

        // Benchmark encoding
        const encode_result = try benchmark.benchEncode(data);
        try stdout.print("Encode: min=", .{});
        try BenchResult.formatDuration(encode_result.min_ns, stdout);
        try stdout.print(" max=", .{});
        try BenchResult.formatDuration(encode_result.max_ns, stdout);
        try stdout.print(" avg=", .{});
        try BenchResult.formatDuration(encode_result.avg_ns, stdout);
        try stdout.print(" throughput={d:.2}MB/s (output: {d} bytes)\n", .{ encode_result.throughput_mbs, encode_result.output_size });

        // Create encoded data for decoding benchmark
        var sink_writer = std.Io.Writer.Allocating.init(allocator);
        defer sink_writer.deinit();

        const encoder_buffer = try allocator.alloc(u8, config.writer_buffer_size);
        defer allocator.free(encoder_buffer);

        var encoder = encoder_writer.BottomWriter.init(encoder_buffer, &sink_writer.writer);
        try encoder.writer.writeAll(data);
        try encoder.writer.flush();

        const encoded = sink_writer.written();

        // Benchmark decoding
        const decode_result = try benchmark.benchDecode(encoded);
        try stdout.print("Decode: min=", .{});
        try BenchResult.formatDuration(decode_result.min_ns, stdout);
        try stdout.print(" max=", .{});
        try BenchResult.formatDuration(decode_result.max_ns, stdout);
        try stdout.print(" avg=", .{});
        try BenchResult.formatDuration(decode_result.avg_ns, stdout);
        try stdout.print(" throughput={d:.2}MB/s (output: {d} bytes)\n", .{ decode_result.throughput_mbs, decode_result.output_size });

        // Calculate compression ratio
        const ratio = @as(f64, @floatFromInt(encode_result.output_size)) / @as(f64, @floatFromInt(encode_result.input_size));
        try stdout.print("Compression ratio: {d:.2}x (encoded size / original size)\n", .{ratio});
    }

    try stdout.print("\nBenchmark complete!\n", .{});
}

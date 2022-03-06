const std = @import("std");
pub fn getAllPkg(comptime T: type) CalculatePkg(T) {
    const info: std.builtin.TypeInfo = @typeInfo(T);
    const declarations: []const std.builtin.TypeInfo.Declaration = info.Struct.decls;
    var pkgs: CalculatePkg(T) = undefined;
    var index: usize = 0;
    inline for (declarations) |d| {
        if (@TypeOf(@field(T, d.name)) == std.build.Pkg) {
            pkgs[index] = @field(T, d.name);
            index += 1;
        }
    }
    return pkgs;
}
fn CalculatePkg(comptime T: type) type {
    const info: std.builtin.TypeInfo = @typeInfo(T);
    const declarations: []const std.builtin.TypeInfo.Declaration = info.Struct.decls;
    var count: usize = 0;
    for (declarations) |d| {
        if (@TypeOf(@field(T, d.name)) == std.build.Pkg) {
            count += 1;
        }
    }
    return [count]std.build.Pkg;
}
pub fn build(b: *std.build.Builder) void {
    const pkgs = struct {
        const bottom = std.build.Pkg{
            .name = "bottom",
            .path = .{ .path = "bottom.zig" },
            .dependencies = &.{vector},
        };

        const args = std.build.Pkg{
            .name = "zig-args",
            .path = .{ .path = "vendors/zig-args/args.zig" },
        };
    };
    const packages = getAllPkg(pkgs);

    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const use_c: bool = b.option(bool, "use_c", "Add C as the default allocator, much faster but uses libc (defaults to false)") orelse false;

    var options = b.addOptions();
    options.addOption(bool, "use_c", use_c);
    options.addOption([]const u8, "version", "v0.0.2");
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("bottom-zig", "src/main.zig");
    for (packages) |p| {
        exe.addPackage(p);
    }
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addOptions("build_options", options);
    if (use_c) {
        exe.linkLibC();
    }
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the Bottom Encoder/Decoder");
    run_step.dependOn(&run_cmd.step);

    var exe_tests = b.addTest("src/main.zig");
    exe_tests.setBuildMode(mode);
    exe_tests.addPackage(pkgs.bottom);
    const test_step = b.step("test-exe", "Run unit tests for the CLI App");
    test_step.dependOn(&exe_tests.step);

    const lib = b.addStaticLibrary("bottom-zig", "bottom.zig");
    lib.setTarget(target);
    lib.addPackage(pkgs.vector);
    lib.setBuildMode(mode);
    lib.addOptions("build_options", options);
    if (use_c) {
        lib.linkLibC();
    }
    lib.install();

    const exe2 = b.addExecutable("benchmark", "src/benchmark.zig");
    exe2.addPackage(pkgs.bottom);
    exe2.addPackage(pkgs.vector);
    exe2.setTarget(target);
    exe2.setBuildMode(.ReleaseFast);
    exe2.install();

    const benchmark_step = b.step("benchmark", "Run benchmarks");
    benchmark_step.dependOn(&exe2.step);

    const run_cmd2 = exe2.run();
    run_cmd2.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd2.addArgs(args);
    }

    const run_step2 = b.step("run-benchmark", "Run the Bottom Encoder/Decoder benchmark");
    run_step2.dependOn(&run_cmd2.step);

    const test_lib = b.addTest("bottom.zig");
    test_lib.setBuildMode(mode);
    test_lib.addPackage(pkgs.vector);

    const test_lib_step = b.step("test-lib", "Run unit tests for the Library");
    test_lib_step.dependOn(&test_lib.step);
}

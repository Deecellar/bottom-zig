const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const use_c: bool = b.option(bool, "use_c", "Add C as the default allocator, much faster but uses libc (defaults to false)") orelse false;
    var options = b.addOptions();
    options.addOption(bool, "use_c", use_c);
    options.addOption([]const u8, "version", "v0.0.1");
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("bottom-zig", "src/main.zig");
    exe.addPackagePath("bottom", "bottom.zig");
    exe.addPackagePath("args", "vendors/zig-args/args.zig");
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

    const test_step = b.step("test-exe", "Run unit tests for the CLI App");
    test_step.dependOn(&exe_tests.step);

    const lib = b.addStaticLibrary("bottom-zig", "bottom.zig");
    lib.setTarget(target);
    lib.setBuildMode(mode);
    lib.addOptions("build_options", options);
    if (use_c) {
        lib.linkLibC();
    }
    lib.install();

    const test_lib = b.addTest("bottom.zig");
    test_lib.setBuildMode(mode);

    const test_lib_step = b.step("test-lib", "Run unit tests for the Library");
    test_lib_step.dependOn(&test_lib.step);
}

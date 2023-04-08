const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const args = std.build.dependency(b, "args", .{});
    const module    = b.addModule("bottom-zig",.{
        .source_file = .{ .path = "bottom.zig" },
        .dependencies = &.{},
    });

    const use_c: bool = b.option(bool, "use_c", "Add C as the default allocator, much faster but uses libc (defaults to false)") orelse false;

    var options = b.addOptions();
    options.addOption(bool, "use_c", use_c);
    options.addOption([]const u8, "version", "v0.0.3");
    const mode = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const install_lib_step = b.step("install-lib", "Install library only");

    const exe = b.addExecutable(std.build.ExecutableOptions{ .name = "bottom-zig", .root_source_file = .{ .path = "src/main.zig" }, .optimize = mode, .target = target });
    exe.addModule("zig-args", args.module("args"));
    exe.addModule("bottom", module);
    exe.addOptions("build_options", options);
    if (use_c) {
        exe.linkLibC();
    }
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |arg| {
        run_cmd.addArgs(arg);
    }

    const run_step = b.step("run", "Run the Bottom Encoder/Decoder");
    run_step.dependOn(&run_cmd.step);

    var exe_tests = b.addTest(std.build.TestOptions{ .name = "bottom-test", .root_source_file = .{ .path = "src/main.zig" }, .optimize = mode, .target = target });
    exe.addModule("bottom", module);
    const test_step = b.step("test-exe", "Run unit tests for the CLI App");
    test_step.dependOn(&exe_tests.step);

    const lib = b.addStaticLibrary(.{ .name = "bottom-zig", .root_source_file = .{ .path = "src/clib.zig" }, .optimize = mode, .target = target });
    lib.addOptions("build_options", options);
        lib.linkLibC();
    lib.install(); // Only works in install

    const slib = b.addSharedLibrary(.{ .name = "bottom-zig", .root_source_file = .{ .path = "src/clib.zig" }, .optimize = mode, .target = target });
    slib.addOptions("build_options", options);
        slib.linkLibC();
    slib.install(); // Only works in install


    const header_include = b.addInstallHeaderFile("include/bottom.h", "bottom/bottom.h");

    install_lib_step.dependOn(&slib.step);
    const install_only_shared = b.addInstallArtifact(slib);
    install_lib_step.dependOn(&install_only_shared.step);
    install_lib_step.dependOn(&lib.step);
    const install_only = b.addInstallArtifact(lib);
    install_lib_step.dependOn(&install_only.step);
    const wasm_shared = b.addSharedLibrary(.{ .name = "bottom-zig", .root_source_file = .{ .path = "src/wasm-example.zig" }, .optimize = .ReleaseSmall, .target = std.zig.CrossTarget{ .abi = .musl, .os_tag = .freestanding, .cpu_arch = .wasm32 } });
    wasm_shared.strip = true;
    wasm_shared.rdynamic = true;

    const wasm_shared_step = b.step("wasm-shared", "Build the WASM example");
    wasm_shared_step.dependOn(&wasm_shared.step);

    const install_to_public = b.addInstallArtifact(wasm_shared);
    wasm_shared_step.dependOn(&install_to_public.step);

    const exe2 = b.addExecutable(std.build.ExecutableOptions{ .name = "benchmark", .root_source_file = .{ .path = "src/benchmark.zig" }, .optimize = .ReleaseFast, .target = target });
    exe.addModule("bottom", module);
    exe2.install();

    

    const clib_exe = b.addExecutable(std.build.ExecutableOptions{ .name = "clib", .optimize = mode, .target = target });
    clib_exe.linkLibC();
    clib_exe.addLibraryPath(b.lib_dir);
    clib_exe.linkSystemLibrary("bottom-zig");
    clib_exe.addIncludePath(b.h_dir);
    clib_exe.addCSourceFile("src/example.c", &.{});
    clib_exe.install();

    clib_exe.step.dependOn(&lib.step);
    clib_exe.step.dependOn(&header_include.step);

    const benchmark_step = b.step("benchmark", "Run benchmarks");
    benchmark_step.dependOn(&exe2.step);

    const run_cmd2 = exe2.run();
    run_cmd2.step.dependOn(b.getInstallStep());
    if (b.args) |arg| {
        run_cmd2.addArgs(arg);
    }

    const run_step2 = b.step("run-benchmark", "Run the Bottom Encoder/Decoder benchmark");
    run_step2.dependOn(&run_cmd2.step);

    const test_lib = b.addTest(std.build.TestOptions{ .name = "bottom-test-lib", .root_source_file = .{ .path = "src/main.zig" }, .optimize = mode, .target = target });

    const test_lib_step = b.step("test-lib", "Run unit tests for the Library");
    test_lib_step.dependOn(&test_lib.step);
}

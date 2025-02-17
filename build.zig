const std = @import("std");

pub fn build(b: *std.Build) void {
    // Setup and configuration
    const args = std.Build.dependency(b, "args", .{});
    const module = b.addModule("bottom-zig", .{
        .root_source_file = b.path("bottom.zig"),
    });
    var options = b.addOptions();
    options.addOption([]const u8, "version", "v0.0.6");
    const mode = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    // Main executable
    const exe = b.addExecutable(std.Build.ExecutableOptions{ .name = "bottom-zig", .root_source_file = b.path("src/main.zig"), .optimize = mode, .target = target });
    exe.root_module.addImport("zig-args", args.module("args"));
    exe.root_module.addImport("bottom", module);
    exe.root_module.addOptions("build_options", options);
    b.installArtifact(exe);

    // Run command setup
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |arg| {
        run_cmd.addArgs(arg);
    }
    const run_step = b.step("run", "Run the Bottom Encoder/Decoder");
    run_step.dependOn(&run_cmd.step);

    // Tests
    var exe_tests = b.addTest(std.Build.TestOptions{ .name = "bottom-test", .root_source_file = b.path("src/main.zig"), .optimize = mode, .target = target });
    exe.root_module.addImport("bottom", module);
    const test_step = b.step("test-exe", "Run unit tests for the CLI App");
    test_step.dependOn(&exe_tests.step);

    // Library builds
    const install_lib_step = b.step("install-lib", "Install library only");

    const lib = b.addStaticLibrary(.{ .name = "bottomz", .root_source_file = b.path("src/clib.zig"), .optimize = mode, .target = target });
    lib.root_module.addOptions("build_options", options);
    lib.linkLibC();
    b.installArtifact(lib);

    const slib = b.addSharedLibrary(.{ .name = "bottomz", .root_source_file = b.path("src/clib.zig"), .optimize = mode, .target = target });
    slib.root_module.addOptions("build_options", options);
    slib.linkLibC();
    b.installArtifact(slib);

    // Library installation
    const header_include = b.addInstallHeaderFile(b.path("include/bottom.h"), "bottom/bottom.h");
    install_lib_step.dependOn(&slib.step);
    const install_only_shared = b.addInstallArtifact(slib, .{});
    install_lib_step.dependOn(&install_only_shared.step);
    install_lib_step.dependOn(&lib.step);
    const install_only = b.addInstallArtifact(lib, .{});
    install_lib_step.dependOn(&install_only.step);

    // WASM build
    const wasm_shared = b.addExecutable(.{ .name = "bottom-zig", .root_source_file = b.path("src/wasm-example.zig"), .optimize = .ReleaseSmall, .target = b.resolveTargetQuery(.{ .abi = .musl, .os_tag = .freestanding, .cpu_arch = .wasm32 }) });
    wasm_shared.root_module.strip = true;
    wasm_shared.rdynamic = true;
    wasm_shared.entry = .disabled;
    wasm_shared.export_table = true;

    const wasm_shared_step = b.step("wasm-shared", "Build the WASM example");
    wasm_shared_step.dependOn(&wasm_shared.step);
    const install_to_public = b.addInstallArtifact(wasm_shared, .{});
    wasm_shared_step.dependOn(&install_to_public.step);

    // Benchmark executable
    const exe2 = b.addExecutable(std.Build.ExecutableOptions{ .name = "benchmark", .root_source_file = b.path("src/benchmark.zig"), .optimize = .ReleaseFast, .target = target });
    exe.root_module.addImport("bottom", module);
    b.installArtifact(exe2);

    // C library example
    const clib_exe = b.addExecutable(std.Build.ExecutableOptions{ .name = "clib", .optimize = mode, .target = target });
    clib_exe.linkLibC();
    clib_exe.addLibraryPath(b.path(b.pathJoin(&.{ std.fs.path.relative(b.allocator, b.build_root.path.?, b.install_prefix) catch @panic("OOM"), "lib" })));
    clib_exe.linkSystemLibrary("bottomz");
    clib_exe.addIncludePath(b.path(b.pathJoin(&.{ std.fs.path.relative(b.allocator, b.build_root.path.?, b.install_prefix) catch @panic("OOM"), "include" })));
    clib_exe.addCSourceFile(.{
        .file = b.path("src/example.c"),
        .flags = &.{},
    });
    b.installArtifact(clib_exe);

    clib_exe.step.dependOn(&lib.step);
    clib_exe.step.dependOn(&slib.step);
    clib_exe.step.dependOn(&header_include.step);

    // Benchmark steps
    const benchmark_step = b.step("benchmark", "Run benchmarks");
    benchmark_step.dependOn(&exe2.step);

    const run_cmd2 = b.addRunArtifact(exe2);
    run_cmd2.step.dependOn(b.getInstallStep());
    if (b.args) |arg| {
        run_cmd2.addArgs(arg);
    }

    const run_step2 = b.step("run-benchmark", "Run the Bottom Encoder/Decoder benchmark");
    run_step2.dependOn(&run_cmd2.step);

    // Library tests
    const test_lib = b.addTest(std.Build.TestOptions{ .name = "bottom-test-lib", .root_source_file = b.path("src/main.zig"), .optimize = mode, .target = target });

    const test_lib_step = b.step("test-lib", "Run unit tests for the Library");
    test_lib_step.dependOn(&test_lib.step);
}

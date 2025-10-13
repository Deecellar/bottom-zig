const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target and optimization options from command-line flags
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // External dependency: zig-args for CLI argument parsing
    // Fetched from build.zig.zon package manifest
    const args_dep = b.dependency("args", .{
        .target = target,
        .optimize = optimize,
    });

    // Build-time configuration options embedded into binaries
    const build_opts = b.addOptions();
    build_opts.addOption([]const u8, "version", "v0.1.0");

    // Library module that consumers can import as `@import("bottom")`
    const bottom_mod = b.addModule("bottom", .{
        .root_source_file = b.path("bottom.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "bottom-zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig-args", .module = args_dep.module("args") },
                .{ .name = "bottom",   .module = bottom_mod },
            },
        }),
    });
    exe.root_module.addOptions("build_options", build_opts);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the Bottom Encoder/Decoder");
    run_step.dependOn(&run_cmd.step);

    // Test both the CLI module and the library module independently
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const lib_tests = b.addTest(.{
        .root_module = bottom_mod,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);

    const test_all = b.step("test", "Run all tests");
    test_all.dependOn(&run_exe_tests.step);
    test_all.dependOn(&run_lib_tests.step);

    // C-compatible libraries for FFI usage
    const static_lib = b.addLibrary(.{
        .name = "bottomz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/clib.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{ .{ .name = "bottom", .module = bottom_mod },  },

        }),
        .linkage = .static,
    });
    static_lib.root_module.addOptions("build_options", build_opts);
    static_lib.linkLibC();
    b.installArtifact(static_lib);

    const shared_lib = b.addLibrary(.{
        .name = "bottomz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/clib.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{ .{ .name = "bottom", .module = bottom_mod },  },

        }),
        .linkage = .dynamic,
    });
    shared_lib.root_module.addOptions("build_options", build_opts);
    shared_lib.linkLibC();
    b.installArtifact(shared_lib);

    // Install C header to zig-out/include/bottom/bottom.h
    const header_install = b.addInstallHeaderFile(
        b.path("include/bottom.h"),
        "bottom/bottom.h",
    );

    const install_lib_step = b.step("install-lib", "Install library only (static+shared+headers)");
    install_lib_step.dependOn(&static_lib.step);
    install_lib_step.dependOn(&shared_lib.step);
    install_lib_step.dependOn(&header_install.step);

    // WebAssembly target requires specific configuration for JavaScript interop
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
        .abi = .musl,
    });

    const wasm_example = b.addExecutable(.{
        .name = "bottom-zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/wasm-example.zig"),
            .target = wasm_target,
            .optimize = .ReleaseSmall, // Minimize binary size for web
            .imports = &.{
                .{ .name = "bottom", .module = bottom_mod },
            },
        }),
    });
    // Strip debug symbols to reduce WASM binary size for faster downloads
    wasm_example.root_module.strip = true;
    // Export dynamic symbols for JavaScript interop
    wasm_example.rdynamic = true;
    // No _start function - JavaScript provides the entry point
    wasm_example.entry = .disabled;
    // Export function table for JavaScript to call WASM functions
    wasm_example.export_table = true;

    const wasm_step = b.step("wasm-shared", "Build the WASM example");
    wasm_step.dependOn(&wasm_example.step);
    const wasm_install = b.addInstallArtifact(wasm_example, .{});
    wasm_step.dependOn(&wasm_install.step);

    // Benchmark always uses ReleaseFast regardless of -Doptimize flag
    const bench = b.addExecutable(.{
        .name = "benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/benchmark.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "bottom", .module = bottom_mod },
            },
        }),
    });
    b.installArtifact(bench);

    const bench_step = b.step("benchmark", "Build benchmark");
    bench_step.dependOn(&bench.step);

    const run_bench = b.addRunArtifact(bench);
    run_bench.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_bench.addArgs(args);
    const run_bench_step = b.step("run-benchmark", "Run the Bottom Encoder/Decoder benchmark");
    run_bench_step.dependOn(&run_bench.step);

    // C example demonstrates FFI by linking against the installed C library
    const clib_exe = b.addExecutable(.{
        .name = "clib",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    clib_exe.linkLibC();

    // Dependencies must be built before C example links against them
    clib_exe.step.dependOn(&static_lib.step);
    clib_exe.step.dependOn(&shared_lib.step);
    clib_exe.step.dependOn(&header_install.step);

    // Point to zig-out for installed headers and libraries
    const inc_dir = b.pathJoin(&.{ b.install_prefix, "include" });
    const lib_dir = b.pathJoin(&.{ b.install_prefix, "lib" });

    clib_exe.root_module.addIncludePath(.{ .cwd_relative = inc_dir });
    clib_exe.root_module.addLibraryPath(.{ .cwd_relative = lib_dir });
    clib_exe.linkSystemLibrary("bottomz");

    clib_exe.addCSourceFile(.{
        .file = b.path("src/example.c"),
        .flags = &.{},
    });

    b.installArtifact(clib_exe);
}

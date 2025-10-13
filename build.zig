const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard flags
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // External deps (new style)
    // Replace "args" with your build.zig.zon package name if different.
    const args_dep = b.dependency("args", .{
        .target = target,
        .optimize = optimize,
    });

    // Build options
    const build_opts = b.addOptions();
    build_opts.addOption([]const u8, "version", "v0.1.0");

    // Library module that consumers can import as `@import("bottom")`
    const bottom_mod = b.addModule("bottom", .{
        .root_source_file = b.path("bottom.zig"),
        .target = target, // enables using this as a test root later
    });

    // -----------------------
    // Main executable (CLI)
    // -----------------------
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

    // `zig build run -- <args…>`
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the Bottom Encoder/Decoder");
    run_step.dependOn(&run_cmd.step);

    // -----------------------
    // Tests
    // -----------------------
    // CLI module tests (tests inside src/main.zig’s module)
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // Library tests: test the bottom module directly
    const lib_tests = b.addTest(.{
        .root_module = bottom_mod,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);

    const test_all = b.step("test", "Run all tests");
    test_all.dependOn(&run_exe_tests.step);
    test_all.dependOn(&run_lib_tests.step);

    // -----------------------
    // Libraries (C ABI)
    // -----------------------
    // Static lib
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

    // Shared lib
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

    // Headers (newer API spells it `installHeaderFile`)
    // Installs to: zig-out/include/bottom/bottom.h
    const header_install = b.addInstallHeaderFile(
        b.path("include/bottom.h"),
        "bottom/bottom.h",
    );

    

    // Convenience step to install only libs/headers
    const install_lib_step = b.step("install-lib", "Install library only (static+shared+headers)");
    install_lib_step.dependOn(&static_lib.step);
    install_lib_step.dependOn(&shared_lib.step);
    install_lib_step.dependOn(&header_install.step);

    // -----------------------
    // WASM example (no start)
    // -----------------------
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
            .optimize = .ReleaseSmall,
            .imports = &.{
                .{ .name = "bottom", .module = bottom_mod },
            },
        }),
    });
    wasm_example.root_module.strip = true;
    wasm_example.rdynamic = true;
    wasm_example.entry = .disabled;
    wasm_example.export_table = true;

    const wasm_step = b.step("wasm-shared", "Build the WASM example");
    wasm_step.dependOn(&wasm_example.step);
    const wasm_install = b.addInstallArtifact(wasm_example, .{});
    wasm_step.dependOn(&wasm_install.step);

    // -----------------------
    // Benchmark executable
    // -----------------------
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

    // -----------------------
    // C example that links installed lib
    // -----------------------
    const clib_exe = b.addExecutable(.{
        .name = "clib",
        .root_module = b.createModule(.{
            // no Zig root source file, this is a C example
            .target = target,
            .optimize = optimize,
        }),

    });
    clib_exe.linkLibC();

    // Ensure libs and header are installed before building the C example
    clib_exe.step.dependOn(&static_lib.step);
    clib_exe.step.dependOn(&shared_lib.step);
    clib_exe.step.dependOn(&header_install.step);

    // Point include/lib paths at the install prefix (zig-out by default)
    // NOTE: This assumes you keep the default prefix (zig-out/).
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

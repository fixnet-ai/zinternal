//! build.zig - Build script for zinternal
//!
//! Pure Zig library providing cross-platform utilities for applications.
//!
//! Build commands:
//!   zig build              - Build and run unit tests (default)
//!   zig build test         - Build test_runner to bin/{os}/
//!   zig build all          - Build static libraries for all targets
//!   zig build all-tests    - Build test_runner for all targets
//!
//! Output structure:
//!   zig-out/
//!   ├── lib/{target}/      # Static libraries
//!   └── bin/{target}/      # Test executables

const std = @import("std");
const framework = @import("build_tools/build_framework.zig");

// ==================== Project Configuration ====================

const c_sources = &[_][]const u8{
    "src/logger.c",
};

const cflags = &[_][]const u8{
    "-std=c99",
    "-Wall",
    "-Wextra",
    "-O2",
};

const cinclude_dirs = &[_][]const u8{
    "src",
};

const zig_modules = &[_]framework.ZigModule{
    .{
        .name = "errors",
        .file = "src/errors.zig",
    },
    .{
        .name = "platform",
        .file = "src/platform.zig",
        .deps = &[_][]const u8{"errors"},
    },
    .{
        .name = "logger",
        .file = "src/logger.zig",
    },
    .{
        .name = "config",
        .file = "src/config.zig",
    },
    .{
        .name = "signal",
        .file = "src/signal.zig",
        .deps = &[_][]const u8{ "platform", "logger" },
    },
    .{
        .name = "app",
        .file = "src/app.zig",
        .deps = &[_][]const u8{ "platform", "logger", "signal", "config" },
    },
};

const test_files = &[_]framework.TestSpec{
    .{
        .name = "test_unit",
        .desc = "Unit tests for zinternal modules",
        .file = "tests/test_unit.zig",
        .exe_name = null,
    },
    .{
        .name = "test_runner",
        .desc = "Integration tests for zinternal",
        .file = "tests/test_runner.zig",
        .exe_name = "test_runner",
    },
};

const config = framework.ProjectConfig{
    .name = "zinternal",
    .root_source_file = std.Build.LazyPath{ .cwd_relative = "src/logger.zig" },
    .c_sources = c_sources,
    .cflags = cflags,
    .cinclude_dirs = cinclude_dirs,
    .zig_modules = zig_modules,
    .test_files = test_files,
};

// ==================== Build Functions ====================

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build native static library
    const lib = framework.buildNativeLib(b, target, optimize, config);
    b.installArtifact(lib);

    // Build unit tests (default step)
    framework.buildUnitTests(b, target, optimize, config);

    // Build test_runner to bin/{os}/ (test step)
    framework.buildTestRunner(b, target, optimize, config);

    // Build all targets (no tests)
    const all_targets_step = b.step("all", "Build static libraries for all supported targets");
    const build_all = framework.buildAllTargets(b, optimize, config, &framework.standard_targets, &framework.standard_target_names);
    all_targets_step.dependOn(build_all);

    // Build all test_runner targets
    const all_tests_step = b.step("all-tests", "Build test_runner for all supported targets");
    const build_all_tests = framework.buildAllTests(b, optimize, config, &framework.standard_targets, &framework.standard_target_names);
    all_tests_step.dependOn(build_all_tests);
}

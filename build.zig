//! build.zig - Build script for zinternal
//!
//! Pure Zig library providing cross-platform utilities for applications.
//!
//! Build commands:
//!   zig build              - Build and run unit tests (default)
//!   zig build test         - Build and run integration tests
//!   zig build build-all    - Build for all supported targets

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
        .exe_name = "zinternal_test",
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

    // === Unit Tests (default) ===
    const unit_test = b.addTest(.{
        .root_source_file = b.path("tests/test_unit.zig"),
        .target = target,
        .optimize = optimize,
    });
    addModuleImportsToTest(b, unit_test);
    const run_unit_test = b.addRunArtifact(unit_test);
    b.default_step.dependOn(&run_unit_test.step);

    // === Integration Tests ===
    const test_runner = b.addExecutable(.{
        .name = "zinternal_test",
        .root_source_file = b.path("tests/test_runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_runner.linkLibC();
    addModuleImportsToTest(b, test_runner);
    const run_test_runner = b.addRunArtifact(test_runner);
    const test_step = b.step("test", "Run integration tests");
    test_step.dependOn(&run_test_runner.step);

    // === Build All Targets (no tests) ===
    const all_targets_step = b.step("all", "Build for all supported targets");
    const build_all = framework.buildAllTargets(b, optimize, config, &framework.standard_targets, &framework.standard_target_names);
    all_targets_step.dependOn(build_all);
}

/// Add module imports to test executable
fn addModuleImportsToTest(b: *std.Build, testArtifact: *std.Build.Step.Compile) void {
    const modules = framework.createModules(b, config);
    var iter = modules.map.iterator();
    while (iter.next()) |entry| {
        testArtifact.root_module.addImport(entry.key_ptr.*, entry.value_ptr.*);
    }
}

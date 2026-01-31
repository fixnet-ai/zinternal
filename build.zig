//! build.zig - Build script for zinternal
//!
//! Pure Zig library providing cross-platform utilities for applications.
//!
//! Build commands:
//!   zig build          - Build and run unit tests (default)
//!   zig build test     - Build and run integration tests

const std = @import("std");

// ==================== Test Specifications ====================

const tests = &.{
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

// ==================== Build Functions ====================

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // === 1. Export Zig Modules ===
    const errors_mod = b.addModule("errors", .{
        .root_source_file = b.path("src/errors.zig"),
    });

    const platform_mod = b.addModule("platform", .{
        .root_source_file = b.path("src/platform.zig"),
    });
    platform_mod.addImport("errors", errors_mod);

    const logger_mod = b.addModule("logger", .{
        .root_source_file = b.path("src/logger.zig"),
    });

    const config_mod = b.addModule("config", .{
        .root_source_file = b.path("src/config.zig"),
    });

    const signal_mod = b.addModule("signal", .{
        .root_source_file = b.path("src/signal.zig"),
    });
    signal_mod.addImport("platform", platform_mod);
    signal_mod.addImport("logger", logger_mod);

    const app_mod = b.addModule("app", .{
        .root_source_file = b.path("src/app.zig"),
    });
    app_mod.addImport("platform", platform_mod);
    app_mod.addImport("logger", logger_mod);
    app_mod.addImport("signal", signal_mod);
    app_mod.addImport("config", config_mod);

    // === 2. Unit Tests (default) ===
    const unit_test = b.addTest(.{
        .root_source_file = b.path("tests/test_unit.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add module imports to unit test
    unit_test.root_module.addImport("errors", errors_mod);
    unit_test.root_module.addImport("platform", platform_mod);
    unit_test.root_module.addImport("logger", logger_mod);
    unit_test.root_module.addImport("config", config_mod);
    unit_test.root_module.addImport("signal", signal_mod);

    const run_unit_test = b.addRunArtifact(unit_test);
    b.default_step.dependOn(&run_unit_test.step);

    // === 3. Integration Tests (test_runner) ===
    const test_runner = b.addExecutable(.{
        .name = "zinternal_test",
        .root_source_file = b.path("tests/test_runner.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add module imports to test runner
    test_runner.root_module.addImport("errors", errors_mod);
    test_runner.root_module.addImport("platform", platform_mod);
    test_runner.root_module.addImport("logger", logger_mod);
    test_runner.root_module.addImport("config", config_mod);
    test_runner.root_module.addImport("signal", signal_mod);
    test_runner.root_module.addImport("app", app_mod);

    const run_test_runner = b.addRunArtifact(test_runner);
    const test_step = b.step("test", "Run integration tests");
    test_step.dependOn(&run_test_runner.step);
}

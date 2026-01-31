//! build.zig - Build script for zinternal
//!
//! Pure Zig library providing cross-platform utilities for applications.
//!
//! Build commands:
//!   zig build              - Build and run unit tests (default)
//!   zig build test         - Build and run integration tests
//!   zig build build-all    - Build for all supported targets

const std = @import("std");

// ==================== C Source Files ====================

const c_sources = &[_][]const u8{
    "src/logger.c",
};

const cflags = &[_][]const u8{
    "-std=c17",
    "-Wall",
    "-Wextra",
    "-O2",
};

// ==================== Sysroot Detection ====================

/// iOS SDK paths (pre-computed at build startup)
var g_ios_sysroot: ?[]const u8 = null;
var g_ios_sim_sysroot: ?[]const u8 = null;
var g_android_sysroot: ?[]const u8 = null;

/// Compute SDK path using xcrun
fn computeSdkPath(allocator: std.mem.Allocator, sdk_name: []const u8) ?[]const u8 {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "xcrun", "--sdk", sdk_name, "--show-sdk-path" },
    }) catch {
        return null;
    };
    defer {
        allocator.free(result.stderr);
        allocator.free(result.stdout);
    }
    if (result.term == .Exited and result.term.Exited == 0) {
        const trimmed = std.mem.trim(u8, result.stdout, " \n\r");
        if (trimmed.len > 0) {
            return allocator.dupe(u8, trimmed) catch null;
        }
    }
    return null;
}

/// Compute Android sysroot from ANDROID_NDK environment variable
fn computeAndroidSysroot(allocator: std.mem.Allocator, env_map: *const std.process.EnvMap) ?[]const u8 {
    const ndk_path = env_map.get("ANDROID_NDK") orelse return null;
    const suffix = "/toolchains/llvm/prebuilt/darwin-x86_64/sysroot";
    return std.mem.concat(allocator, u8, &[_][]const u8{ ndk_path, suffix }) catch null;
}

/// Get sysroot path for cross-compilation targets
fn getSysroot(target: std.Target) ?[]const u8 {
    switch (target.os.tag) {
        .ios => {
            // Use simulator SDK for simulator ABI, otherwise device SDK
            if (target.abi == .simulator) {
                return g_ios_sim_sysroot;
            }
            return g_ios_sysroot;
        },
        .linux => {
            // Android uses abi == .android
            if (target.abi == .android) {
                return g_android_sysroot;
            }
            return null;
        },
        else => {
            return null;
        },
    }
}

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
    // Pre-compute SDK paths
    g_ios_sysroot = computeSdkPath(b.allocator, "iphoneos");
    g_ios_sim_sysroot = computeSdkPath(b.allocator, "iphonesimulator");
    g_android_sysroot = computeAndroidSysroot(b.allocator, &b.graph.env_map);

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
    test_runner.linkLibC();  // test_runner needs libc for integration tests

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

    // === 4. Native Static Library ===
    const native_lib = b.addStaticLibrary(.{
        .name = "zinternal",
        .root_source_file = b.path("src/logger.zig"), // Dummy - not actually used
        .target = target,
        .optimize = optimize,
    });

    // Add C source files for native build
    native_lib.root_module.addCSourceFiles(.{
        .files = c_sources,
        .flags = cflags,
    });
    native_lib.root_module.addIncludePath(b.path("src"));
    native_lib.linkLibC();

    // Add all modules
    native_lib.root_module.addImport("errors", errors_mod);
    native_lib.root_module.addImport("platform", platform_mod);
    native_lib.root_module.addImport("logger", logger_mod);
    native_lib.root_module.addImport("config", config_mod);
    native_lib.root_module.addImport("signal", signal_mod);
    native_lib.root_module.addImport("app", app_mod);

    // Install native library
    b.installArtifact(native_lib);

    // === 5. Build All Targets ===
    const build_all_step = b.step("build-all", "Build for all supported targets");

    // Define all supported targets using Target.Query
    const all_targets = [_]std.Target.Query{
        // Desktop platforms
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
        .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
        .{ .cpu_arch = .x86_64, .os_tag = .macos },
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
        .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
        .{ .cpu_arch = .aarch64, .os_tag = .windows, .abi = .gnu },  // Windows ARM64

        // Mobile platforms
        .{ .cpu_arch = .aarch64, .os_tag = .ios },
        .{ .cpu_arch = .x86_64, .os_tag = .ios, .abi = .simulator },  // iOS x86_64 simulator
        .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .android },
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .android },  // Android x86_64 simulator
    };

    // Target name mapping for output directory
    const target_names = [_][]const u8{
        "x86_64-linux-gnu",
        "aarch64-linux-gnu",
        "x86_64-macos",
        "aarch64-macos",
        "x86_64-windows-gnu",
        "arm64-windows-gnu",

        "aarch64-ios",
        "x86_64-ios-sim",
        "aarch64-linux-android",
        "x86_64-linux-android",
    };

    for (all_targets, target_names) |target_query, _| {
        const resolved_target = b.resolveTargetQuery(target_query);

        const lib = b.addStaticLibrary(.{
            .name = "zinternal",
            .root_source_file = b.path("src/logger.zig"), // Dummy - not actually used
            .target = resolved_target,
            .optimize = optimize,
        });

        // Get sysroot for cross-compilation targets (iOS and Android)
        const sysroot = getSysroot(resolved_target.result);

        // Build cflags with optional sysroot
        if (sysroot) |path| {
            lib.root_module.addCSourceFiles(.{
                .files = c_sources,
                .flags = &[_][]const u8{ "-std=c17", "-Wall", "-Wextra", "-O2", "-isysroot", path },
            });
            // Add sysroot include path for system headers (stdio.h, etc.)
            const sysroot_include = std.fs.path.join(b.allocator, &[_][]const u8{ path, "usr/include" }) catch unreachable;
            defer b.allocator.free(sysroot_include);
            lib.root_module.addSystemIncludePath(.{ .cwd_relative = sysroot_include });

            // Android requires arch-specific include path
            if (resolved_target.result.abi == .android) {
                const arch_name = switch (resolved_target.result.cpu.arch) {
                    .aarch64 => "aarch64-linux-android",
                    .x86_64 => "x86_64-linux-android",
                    else => "",
                };
                if (arch_name.len > 0) {
                    const arch_include = std.fs.path.join(b.allocator, &[_][]const u8{ path, "usr/include", arch_name }) catch unreachable;
                    defer b.allocator.free(arch_include);
                    lib.root_module.addSystemIncludePath(.{ .cwd_relative = arch_include });
                }
            }
        } else {
            lib.root_module.addCSourceFiles(.{
                .files = c_sources,
                .flags = cflags,
            });
        }

        lib.root_module.addIncludePath(b.path("src"));
        lib.linkLibC();  // Link libc for C source compilation

        // Add all modules
        lib.root_module.addImport("errors", errors_mod);
        lib.root_module.addImport("platform", platform_mod);
        lib.root_module.addImport("logger", logger_mod);
        lib.root_module.addImport("config", config_mod);
        lib.root_module.addImport("signal", signal_mod);
        lib.root_module.addImport("app", app_mod);

        // Install to default lib directory (target subdirectory is not supported with static library)
        const install_step = b.addInstallArtifact(lib, .{});
        build_all_step.dependOn(&install_step.step);
    }
}

//! build_framework.zig - Cross-platform build framework
//!
//! Reusable build utilities for Zig projects with C code.
//! Provides sysroot detection, platform targets, and unified build flow.
//!
//! Usage:
//!   const framework = @import("build_tools/build_framework.zig");
//!
//!   pub fn build(b: *std.Build) void {
//!       const target = b.standardTargetOptions(.{});
//!       const optimize = b.standardOptimizeOption(.{});
//!
//!       // Define your project configuration
//!       const config = framework.ProjectConfig{
//!           .name = "myproject",
//!           .root_source_file = b.path("src/main.zig"),
//!           .c_sources = &[_][]const u8{"src/lib.c"},
//!           .cflags = &[_][]const u8{"-std=c17", "-O2"},
//!           .cinclude_dirs = &[_][]const u8{"src"},
//!           .zig_modules = &[_]framework.ZigModule{},
//!       };
//!
//!       framework.build(b, target, optimize, config);
//!   }

const std = @import("std");

// ==================== SDK Sysroots (Hard-coded for macOS) ====================

/// iOS device SDK sysroot (hard-coded for macOS)
const g_ios_sysroot = "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.0.sdk";

/// iOS simulator SDK sysroot (hard-coded for macOS)
const g_ios_sim_sysroot = "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.0.sdk";

/// Android NDK sysroot format (needs ANDROID_NDK env var)
/// Format: {ANDROID_NDK}/toolchains/llvm/prebuilt/darwin-x86_64/sysroot
const g_android_suffix = "/toolchains/llvm/prebuilt/darwin-x86_64/sysroot";

/// Get Android sysroot path
fn getAndroidSysroot(env_map: *const std.process.EnvMap) ?[]const u8 {
    const ndk_path = env_map.get("ANDROID_NDK") orelse return null;
    return std.mem.concat(std.heap.page_allocator, u8, &[_][]const u8{ ndk_path, g_android_suffix }) catch null;
}

/// Get sysroot path for cross-compilation targets
pub fn getSysroot(target: std.Target, env_map: *const std.process.EnvMap) ?[]const u8 {
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
                return getAndroidSysroot(env_map);
            }
            return null;
        },
        else => {
            return null;
        },
    }
}

// ==================== Platform Targets ====================

/// Standard cross-platform targets for desktop and mobile
pub const standard_targets = [_]std.Target.Query{
    // Desktop platforms
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .x86_64, .os_tag = .macos },
    .{ .cpu_arch = .aarch64, .os_tag = .macos },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .windows, .abi = .gnu },

    // Mobile platforms
    .{ .cpu_arch = .aarch64, .os_tag = .ios },
    .{ .cpu_arch = .x86_64, .os_tag = .ios, .abi = .simulator },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .android },
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .android },
};

/// Target name mapping for output directory
pub const standard_target_names = [_][]const u8{
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

// ==================== Configuration Types ====================

/// Zig module definition
pub const ZigModule = struct {
    name: []const u8,
    file: []const u8,
    deps: []const []const u8 = &.{},
};

/// Project configuration
pub const ProjectConfig = struct {
    name: []const u8,
    root_source_file: std.Build.LazyPath,
    c_sources: []const []const u8,
    cflags: []const []const u8,
    cinclude_dirs: []const []const u8,
    zig_modules: []const ZigModule,
    test_files: []const TestSpec = &.{},
};

/// Test specification
pub const TestSpec = struct {
    name: []const u8,
    desc: []const u8,
    file: []const u8,
    exe_name: ?[]const u8,
};

// ==================== Build Functions ====================

/// Add C source files with optional sysroot flags
fn addCSourceFilesWithSysroot(
    lib: *std.Build.Step.Compile,
    allocator: std.mem.Allocator,
    c_sources: []const []const u8,
    sysroot: []const u8,
    resolved_target: std.Build.ResolvedTarget,
) void {
    // Build flags with sysroot
    lib.root_module.addCSourceFiles(.{
        .files = c_sources,
        .flags = &[_][]const u8{ "-std=c17", "-Wall", "-Wextra", "-O2", "-isysroot", sysroot },
    });

    // Add sysroot include path for system headers
    const sysroot_include = std.fs.path.join(allocator, &[_][]const u8{ sysroot, "usr/include" }) catch unreachable;
    defer allocator.free(sysroot_include);
    lib.root_module.addSystemIncludePath(.{ .cwd_relative = sysroot_include });

    // Android requires arch-specific include path
    if (resolved_target.result.abi == .android) {
        const arch_name = switch (resolved_target.result.cpu.arch) {
            .aarch64 => "aarch64-linux-android",
            .x86_64 => "x86_64-linux-android",
            else => "",
        };
        if (arch_name.len > 0) {
            const arch_include = std.fs.path.join(allocator, &[_][]const u8{ sysroot, "usr/include", arch_name }) catch unreachable;
            defer allocator.free(arch_include);
            lib.root_module.addSystemIncludePath(.{ .cwd_relative = arch_include });
        }
    }
}

/// Add C source files for native build (no sysroot)
fn addCSourceFilesNative(lib: *std.Build.Step.Compile, c_sources: []const []const u8, cflags: []const []const u8) void {
    lib.root_module.addCSourceFiles(.{
        .files = c_sources,
        .flags = cflags,
    });
}

/// Create all Zig modules and return them indexed by name (aligned for macOS)
pub fn createModules(b: *std.Build, config: ProjectConfig) align(16) struct {
    map: std.StringHashMap(*std.Build.Module),
} {
    var map = std.StringHashMap(*std.Build.Module).init(b.allocator);

    // First pass: create all modules without dependencies
    for (config.zig_modules) |mod| {
        const zmod = b.addModule(mod.name, .{
            .root_source_file = b.path(mod.file),
        });
        map.put(mod.name, zmod) catch unreachable;
    }

    // Second pass: add dependencies (after all modules are created)
    for (config.zig_modules) |mod| {
        const zmod = map.get(mod.name).?;
        for (mod.deps) |dep| {
            if (map.get(dep)) |dep_mod| {
                zmod.addImport(dep, dep_mod);
            }
        }
    }

    return .{ .map = map };
}

/// Build native library with modules
pub fn buildNativeLib(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    config: ProjectConfig,
) *std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = config.name,
        .root_source_file = config.root_source_file,
        .target = target,
        .optimize = optimize,
    });

    // Add C sources
    lib.root_module.addCSourceFiles(.{
        .files = config.c_sources,
        .flags = config.cflags,
    });

    // Add include paths
    for (config.cinclude_dirs) |dir| {
        lib.root_module.addIncludePath(.{ .cwd_relative = dir });
    }
    lib.linkLibC();

    // Add Zig modules
    const modules = createModules(b, config);
    var iter = modules.map.iterator();
    while (iter.next()) |entry| {
        lib.root_module.addImport(entry.key_ptr.*, entry.value_ptr.*);
    }

    return lib;
}

/// Build cross-platform libraries for all targets
pub fn buildAllTargets(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    config: ProjectConfig,
    targets: []const std.Target.Query,
    target_names: []const []const u8,
) *std.Build.Step {
    const build_all_step = b.step("build-all", "Build for all supported targets");

    for (targets, target_names) |target_query, _| {
        const resolved_target = b.resolveTargetQuery(target_query);

        const lib = b.addStaticLibrary(.{
            .name = config.name,
            .root_source_file = config.root_source_file,
            .target = resolved_target,
            .optimize = optimize,
        });

        // Add C sources with sysroot detection
        if (getSysroot(resolved_target.result, &b.graph.env_map)) |sysroot| {
            addCSourceFilesWithSysroot(lib, b.allocator, config.c_sources, sysroot, resolved_target);
        } else {
            addCSourceFilesNative(lib, config.c_sources, config.cflags);
        }

        // Add include paths
        for (config.cinclude_dirs) |dir| {
            lib.root_module.addIncludePath(.{ .cwd_relative = dir });
        }
        lib.linkLibC();

        // Add Zig modules
        const modules = createModules(b, config);
        var iter = modules.map.iterator();
        while (iter.next()) |entry| {
            lib.root_module.addImport(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Install artifact
        const install_step = b.addInstallArtifact(lib, .{});
        build_all_step.dependOn(&install_step.step);
    }

    return build_all_step;
}

/// Main build function - implements standard build flow
pub fn build(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    config: ProjectConfig,
) void {
    // Build native library
    const lib = buildNativeLib(b, target, optimize, config);
    b.installArtifact(lib);

    // Build all targets if configured
    _ = buildAllTargets(b, optimize, config, &standard_targets, &standard_target_names);
}

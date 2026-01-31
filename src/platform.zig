//! platform.zig - Cross-platform abstraction layer
//!
//! Provides platform-specific constants, types, and utilities:
//! - Platform detection (Linux/macOS/Windows)
//! - Aligned allocator (16-byte aligned for macOS x86_64 compatibility)
//! - Error code mapping (see errors.zig for full implementation)
//! - GPA memory management
//!
//! All modules should import this for cross-platform support.

const std = @import("std");
const builtin = @import("builtin");
const errors = @import("errors");

// Increase compile-time branch quota for large switch statements
comptime {
    @setEvalBranchQuota(200000);
}

// ==================== Platform Detection ====================

/// Check if running on Linux
pub const is_linux = builtin.target.os.tag == .linux;

/// Check if running on macOS
pub const is_macos = builtin.target.os.tag == .macos;

/// Check if running on Windows
pub const is_windows = builtin.target.os.tag == .windows;

/// Check if running on POSIX-compatible system
pub const is_posix = is_linux or is_macos;

/// Check if running on Android
pub const is_android = builtin.target.os.tag == .linux and builtin.abi == .android;

/// Check if running on iOS
pub const is_ios = builtin.target.os.tag == .ios;

/// Check if running on mobile platform (iOS or Android)
pub const is_mobile = is_ios or is_android;

// ==================== Signal Constants (POSIX Standard) ====================

pub const SIGINT: c_int = 2;   // Ctrl+C
pub const SIGTERM: c_int = 15; // kill command
pub const SIGHUP: c_int = 1;   // Terminal hangup
pub const SIGQUIT: c_int = 3;  // Ctrl+\
pub const SIGKILL: c_int = 9;  // Force kill
pub const SIGUSR1: c_int = 10; // User-defined 1
pub const SIGUSR2: c_int = 12; // User-defined 2

// ==================== CPU Architecture ====================

/// Check if CPU supports affinity (Linux only)
pub const has_cpu_affinity = is_linux;

/// CPU architecture type
pub const Arch = enum {
    x86_64,
    aarch64,
    arm,
    riscv64,
    other,
};

/// Get current CPU architecture
pub fn getArch() Arch {
    const cpu_arch = builtin.cpu.arch;
    return switch (cpu_arch) {
        .x86_64 => .x86_64,
        .aarch64 => .aarch64,
        .arm => .arm,
        .riscv64 => .riscv64,
        else => .other,
    };
}

// ==================== OS Type ====================

/// Operating system type
pub const OSType = enum {
    linux,
    macos,
    windows,
    other,
};

/// Get current operating system type
pub fn getOSType() OSType {
    return switch (builtin.os.tag) {
        .linux => if (builtin.abi == .android) .other else .linux,
        .macos => .macos,
        .windows => .windows,
        else => .other,
    };
}

/// Get platform info string (e.g., "linux-x86_64")
pub fn getPlatformInfo() []const u8 {
    const os = getOSType();
    const arch = getArch();
    const os_name = switch (os) {
        .linux => "linux",
        .macos => "macos",
        .windows => "windows",
        .other => "unknown",
    };
    const arch_name = switch (arch) {
        .x86_64 => "x86_64",
        .aarch64 => "aarch64",
        .arm => "arm",
        .riscv64 => "riscv64",
        .other => "unknown",
    };
    // Use a static buffer to avoid allocation
    var buf: [32]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, "{s}-{s}", .{ os_name, arch_name }) catch "unknown-unknown";
    return result;
}

// ==================== Memory Allocator ====================

/// GPA type (only used in Debug mode)
pub const Gpa = std.heap.GeneralPurposeAllocator(.{
    .stack_trace_frames = 12,
    .never_unmap = true,
});

/// GPA instance
var gpa: Gpa = .{};

/// GPA enabled flag
/// Pre-GPA phase: use page_allocator, no release, no leak detection
/// GPA phase: use GPA, detect leaks
pub var gpa_enabled: bool = false;

/// Alignment required for atomic operations on macOS x86_64
const REQUIRED_ALIGNMENT: usize = if (is_macos and builtin.cpu.arch == .x86_64) 16 else 8;

/// Aligned allocator wrapper
/// Ensures all allocated memory is properly aligned
/// Required on macOS x86_64 for HashMap atomic operations (CMPXCHG16B)
pub const AlignedAllocator = struct {
    child_allocator: std.mem.Allocator,
    alignment: usize,

    const Self = @This();

    pub fn init(child_allocator: std.mem.Allocator, alignment: usize) Self {
        return .{
            .child_allocator = child_allocator,
            .alignment = alignment,
        };
    }

    pub fn allocator(self: *Self) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    fn alloc(
        ctx: *anyopaque,
        len: usize,
        ptr_align: u8,
        ret_addr: usize,
    ) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const final_alignment = @max(self.alignment, ptr_align);
        return self.child_allocator.rawAlloc(len, @intCast(final_alignment), ret_addr);
    }

    fn resize(
        ctx: *anyopaque,
        buf: []u8,
        buf_align: u8,
        new_len: usize,
        ret_addr: usize,
    ) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const final_alignment = @max(self.alignment, buf_align);
        return self.child_allocator.rawResize(buf, @intCast(final_alignment), new_len, ret_addr);
    }

    fn free(
        ctx: *anyopaque,
        buf: []u8,
        buf_align: u8,
        ret_addr: usize,
    ) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const final_alignment = @max(self.alignment, buf_align);
        return self.child_allocator.rawFree(buf, @intCast(final_alignment), ret_addr);
    }
};

/// Aligned GPA instance
var g_aligned_gpa: ?AlignedAllocator = null;

/// Aligned page allocator instance
var g_aligned_page: ?AlignedAllocator = null;

/// Current memory allocator (runtime-switchable, always uses aligned allocator)
/// Pre-GPA phase: page_allocator + aligned wrapper
/// GPA phase (Debug): gpa.allocator() + aligned wrapper
/// GPA phase (Release): page_allocator + aligned wrapper
pub var allocator: std.mem.Allocator = undefined;

/// Initialize the default allocator
///
/// **Determined at compile time**:
/// - Debug mode: automatically enable GPA (memory leak detection)
/// - Release mode: use page_allocator (performance first)
///
/// **Always use aligned allocator** to ensure proper memory alignment:
/// - macOS x86_64: 16-byte alignment (required by HashMap atomic operations)
/// - Other platforms: 8-byte alignment
pub fn initAllocator() void {
    if (builtin.mode == .Debug) {
        // Debug mode: use GPA + aligned wrapper, auto-enable memory leak detection
        gpa_enabled = true;
        if (g_aligned_gpa == null) {
            g_aligned_gpa = AlignedAllocator.init(gpa.allocator(), REQUIRED_ALIGNMENT);
        }
        allocator = g_aligned_gpa.?.allocator();
    } else {
        // Release mode: use page_allocator + aligned wrapper
        if (g_aligned_page == null) {
            g_aligned_page = AlignedAllocator.init(std.heap.page_allocator, REQUIRED_ALIGNMENT);
        }
        allocator = g_aligned_page.?.allocator();
    }
}

/// Report GPA memory leaks (only valid in Debug mode)
///
/// Call before program exit to print memory leak detection report
///
/// Returns:
/// - true: no memory leaks
/// - false: memory leaks detected
pub fn reportLeaks() bool {
    if (builtin.mode != .Debug) {
        // Release mode doesn't use GPA, return directly
        return true;
    }

    std.debug.print("=== GPA Memory Leak Detection ===\n", .{});
    const result = gpa.deinit();
    if (result == .ok) {
        std.debug.print("[OK] No memory leaks detected\n", .{});
        return true;
    } else if (result == .leak) {
        std.debug.print("[FAIL] Memory leaks detected!\n", .{});
        return false;
    }
    return true;
}

/// Get aligned allocator for atomic containers
/// This is a convenience function that returns the current allocator
/// which is already aligned for atomic operations.
pub inline fn alignedAllocator() std.mem.Allocator {
    return allocator;
}

// ==================== Error Code Re-exports ====================

// Re-export from errors module for backward compatibility
pub usingnamespace errors;

// ==================== Compile-time Verification ====================

comptime {
    // Verify critical constants
    std.debug.assert(SIGINT == 2);
    std.debug.assert(SIGTERM == 15);
}

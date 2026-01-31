//! test_framework.zig - Shared Test Framework
//!
//! Provides common testing utilities for all zinternal projects.
//!
//! Usage:
//! ```zig
//! const test_framework = @import("test_framework");
//!
//! fn testScenario() bool {
//!     // Initialize test environment
//!     test_framework.initTestEnv();
//!     defer {
//!         if (!test_framework.deinitTestEnv()) {
//!             return false;
//!         }
//!     }
//!
//!     // Test logic
//!     // ...
//!
//!     return true;
//! }
//!
//! pub fn main() !void {
//!     var ctx = test_framework.TestContext{};
//!
//!     ctx.start("Test Scenario");
//!     if (testScenario()) {
//!         ctx.pass();
//!     } else {
//!         ctx.fail("Scenario failed", .{});
//!     }
//!
//!     ctx.summary();
//!
//!     if (!ctx.allPassed()) {
//!         std.process.exit(1);
//!     }
//! }
//! ```
//!

const std = @import("std");
const platform = @import("platform");

// ==================== GPA Instance ====================

// Global GPA instance for memory leak detection
var g_gpa: std.heap.GeneralPurposeAllocator(.{
    .stack_trace_frames = 12,
    .never_unmap = true,
}) = .{};
var g_allocator: std.mem.Allocator = undefined;
var g_initialized: bool = false;

// ==================== Test Context ====================

/// TestContext - Context for tracking test results
///
/// Used in black-box/integration tests to track and report test results.
pub const TestContext = struct {
    total: u32 = 0,
    passed: u32 = 0,
    failed: u32 = 0,

    /// Start a new test
    pub fn start(self: *TestContext, name: []const u8) void {
        self.total += 1;
        std.debug.print("[{d:>3}] Testing: {s}...\n", .{ self.total, name });
    }

    /// Mark current test as passed
    pub fn pass(self: *TestContext) void {
        self.passed += 1;
        std.debug.print("  PASSED\n", .{});
    }

    /// Mark current test as failed with message
    pub fn fail(self: *TestContext, comptime msg: []const u8, args: anytype) void {
        self.failed += 1;
        std.debug.print("  FAILED: " ++ msg ++ "\n", args);
    }

    /// Print test summary
    pub fn summary(self: *const TestContext) void {
        std.debug.print("\n=== Test Summary ===\n", .{});
        std.debug.print("Total:  {d}\n", .{self.total});
        std.debug.print("Passed: {d}\n", .{self.passed});
        std.debug.print("Failed: {d}\n", .{self.failed});

        if (self.failed == 0) {
            std.debug.print("\nAll tests passed!\n", .{});
        } else {
            std.debug.print("\n{d} tests failed!\n", .{self.failed});
        }
    }

    /// Check if all tests passed
    pub fn allPassed(self: *const TestContext) bool {
        return self.failed == 0;
    }
};

// ==================== Test Environment ====================

/// Initialize test environment (GPA)
///
/// Sets up the testing environment with GPA for memory leak detection.
pub fn initTestEnv() void {
    if (!g_initialized) {
        g_allocator = g_gpa.allocator();
        g_initialized = true;
    }
}

/// Deinitialize test environment and check for memory leaks
///
/// Cleans up the test environment and reports memory leaks.
///
/// Returns:
///   - true: No memory leaks detected
///   - false: Memory leaks detected
pub fn deinitTestEnv() bool {
    if (!g_initialized) return true;

    const result = g_gpa.deinit();
    g_initialized = false;

    if (result == .ok) {
        std.debug.print("[OK] No memory leaks\n", .{});
        return true;
    } else {
        std.debug.print("[FAIL] Memory leaks detected!\n", .{});
        return false;
    }
}

/// Get GPA allocator for tests
///
/// Returns the GPA allocator instance for use in tests.
pub fn allocator() std.mem.Allocator {
    return g_allocator;
}

// ==================== Assertion Helpers ====================

/// Assert that condition is true
pub fn assert(condition: bool, msg: []const u8) bool {
    if (!condition) {
        std.debug.print("  ASSERTION FAILED: {s}\n", .{msg});
    }
    return condition;
}

/// Assert that two values are equal
pub fn assertEqual(comptime T: type, expected: T, actual: T, msg: []const u8) bool {
    if (expected != actual) {
        std.debug.print("  ASSERTION FAILED: {s} (expected {any}, got {any})\n", .{ msg, expected, actual });
        return false;
    }
    return true;
}

/// Assert that two slices are equal
pub fn assertSliceEqual(expected: []const u8, actual: []const u8, msg: []const u8) bool {
    if (!std.mem.eql(u8, expected, actual)) {
        std.debug.print("  ASSERTION FAILED: {s}\n", .{msg});
        std.debug.print("    Expected: {s}\n", .{expected});
        std.debug.print("    Actual:   {s}\n", .{actual});
        return false;
    }
    return true;
}

/// Assert that value is within range
pub fn assertInRange(comptime T: type, min: T, max: T, value: T, msg: []const u8) bool {
    if (value < min or value > max) {
        std.debug.print("  ASSERTION FAILED: {s} (expected {any}..{any}, got {any})\n", .{ msg, min, max, value });
        return false;
    }
    return true;
}

/// Assert that pointer is not null
pub fn assertNotNull(ptr: anytype, msg: []const u8) bool {
    if (ptr == null) {
        std.debug.print("  ASSERTION FAILED: {s} (null pointer)\n", .{msg});
        return false;
    }
    return true;
}

/// Assert that error occurred
pub fn assertError(err: anyerror, expected_err: anyerror, msg: []const u8) bool {
    if (err != expected_err) {
        std.debug.print("  ASSERTION FAILED: {s} (expected {any}, got {any})\n", .{ msg, expected_err, err });
        return false;
    }
    return true;
}

// ==================== Test Utilities ====================

/// Create a temporary directory
pub fn createTempDir(prefix: []const u8) !std.fs.Dir {
    const tmp_dir = std.fs.cwd().makeOpenPath("tmp", .{}) catch |e| {
        if (e == error.PathAlreadyExists) {
            return std.fs.cwd().openDir("tmp", .{}) catch return error.TempDirFailed;
        }
        return error.TempDirFailed;
    };

    // Create unique subdirectory
    const rand_bytes = std.crypto.random.bytes(6) catch return error.TempDirFailed;
    var subdir_name: [12]u8 = undefined;
    _ = std.fmt.bufPrint(&subdir_name, "{s}-", .{prefix}) catch return error.TempDirFailed;
    std.mem.copy(u8, subdir_name[prefix.len + 1 ..], &rand_bytes);

    return tmp_dir.makeOpenPath(subdir_name[0..], .{}) catch return error.TempDirFailed;
}

/// Generate random bytes
pub fn randomBytes(buf: []u8) void {
    std.crypto.random.bytes(buf);
}

/// Generate random u32 in range
pub fn randomU32(min: u32, max: u32) u32 {
    const range = max - min + 1;
    return min + @as(u32, @intCast(std.crypto.random.int(u64) % range));
}

/// Sleep for specified milliseconds
pub fn sleep(ms: u64) void {
    std.time.sleep(ms * std.time.ns_per_ms);
}

/// Format timestamp for logging
pub fn timestamp() ![]const u8 {
    var tv: std.posix.timespec = undefined;
    std.posix.clock_gettime(std.posix.CLOCK.REAL, &tv) catch return "unknown";

    const epoch_secs = @as(u64, @intCast(tv.tv_sec));
    const hours = (epoch_secs / 3600) % 24;
    const minutes = (epoch_secs / 60) % 60;
    const seconds = epoch_secs % 60;

    var buf: [32]u8 = undefined;
    const len = std.fmt.bufPrint(&buf, "{d:02}:{d:02}:{d:02}", .{ hours, minutes, seconds }) catch return "error";
    return buf[0..len];
}

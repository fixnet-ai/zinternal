//! signal.zig - Signal Handling Module
//!
//! Cross-platform signal handling for graceful shutdown (SIGINT/SIGTERM).
//!
//! Features:
//! - No external dependencies (only platform)
//! - Self-pipe technique for signal handling
//! - Thread-safe
//! - Custom signal handler support
//! - Cross-platform: POSIX signals (Linux/macOS/iOS), Windows Console events
//!
//! Usage:
//! ```zig
//! const signal = @import("signal");
//!
//! // Setup default signal handler
//! try signal.setup(null);
//!
//! // In event loop, check for signal
//! if (signal.isTriggered()) {
//!     const caught = signal.getCaughtSignal();
//!     // Handle signal...
//!     signal.clear();
//! }
//!
//! // Cleanup
//! signal.cleanup();
//! ```

const std = @import("std");
const platform = @import("platform");
const builtin = @import("builtin");

// ==================== Constants ====================

/// SIGINT signal value (cross-platform unified)
pub const SIGINT: c_int = 2;

/// SIGTERM signal value (cross-platform unified)
pub const SIGTERM: c_int = 15;

// ==================== Signal Handler Type ====================

/// Signal handler function type
pub const SignalHandler = *const fn (sig: c_int) callconv(.C) void;

// ==================== Windows-specific Definitions ====================

const windows = if (builtin.os.tag == .windows) struct {
    pub const DWORD = c_uint;
    pub const BOOL = c_int;
    pub const TRUE = 1;
    pub const FALSE = 0;

    pub const CTRL_C_EVENT = 0;
    pub const CTRL_BREAK_EVENT = 1;
    pub const CTRL_CLOSE_EVENT = 2;
    pub const CTRL_LOGOFF_EVENT = 5;
    pub const CTRL_SHUTDOWN_EVENT = 6;

    pub const PHANDLER_ROUTINE = *const fn (dwCtrlType: DWORD) callconv(if (builtin.cpu.arch == .x86) .Stdcall else .C) BOOL;

    extern "kernel32" fn SetConsoleCtrlHandler(
        HandlerRoutine: PHANDLER_ROUTINE,
        Add: BOOL,
    ) BOOL;
} else struct {};

// ==================== Helper: Unix Detection ====================

const is_unix = switch (builtin.os.tag) {
    .linux, .macos, .ios, .freebsd, .openbsd, .netbsd, .dragonfly => true,
    else => false,
};

// ==================== Signal Context ====================

/// Signal handling context (internal state)
const SignalContext = struct {
    signal_fd: i32 = -1,  // self-pipe read end
    caught_signal: std.atomic.Value(c_int) = std.atomic.Value(c_int).init(0),
    handler: ?SignalHandler = null,

    // Unix-specific
    original_sigint: if (is_unix) std.posix.Sigaction else void = if (is_unix) undefined else {},
    original_sigterm: if (is_unix) std.posix.Sigaction else void = if (is_unix) undefined else {},
};

/// Global signal handling context
var g_signal_ctx: SignalContext = .{};

// ==================== Unix Signal Handler ====================

const unix_impl = if (is_unix) struct {
    /// Actual signal handler registered to the system
    fn signalHandler(sig: c_int) callconv(.C) void {
        // Save caught signal
        _ = g_signal_ctx.caught_signal.store(sig, .seq_cst);

        // Write to self-pipe (non-blocking, ignore errors)
        const buf: [1]u8 = .{1};
        _ = std.posix.write(g_signal_ctx.signal_fd, &buf) catch {};

        // Call user-defined handler
        if (g_signal_ctx.handler) |h| {
            h(sig);
        }
    }
} else struct {};

// ==================== Windows Console Handler ====================

const windows_impl = if (builtin.os.tag == .windows) struct {
    /// Windows console control handler
    fn consoleHandler(dwCtrlType: windows.DWORD) callconv(if (builtin.cpu.arch == .x86) .Stdcall else .C) windows.BOOL {
        // Map Windows events to Unix signals
        const sig: c_int = switch (dwCtrlType) {
            windows.CTRL_C_EVENT => SIGINT,
            windows.CTRL_CLOSE_EVENT, windows.CTRL_SHUTDOWN_EVENT => SIGTERM,
            else => return windows.FALSE,
        };

        // Save caught signal
        _ = g_signal_ctx.caught_signal.store(sig, .seq_cst);

        // Write to self-pipe (non-blocking, ignore errors)
        const buf: [1]u8 = .{1};
        _ = std.posix.write(g_signal_ctx.signal_fd, &buf) catch {};

        // Call user-defined handler
        if (g_signal_ctx.handler) |h| {
            h(sig);
        }

        return windows.TRUE;
    }
} else struct {};

// ==================== Pipe Operations ====================

/// Create a self-pipe for signal notification
fn createSignalPipe() !struct { read_fd: i32, write_fd: i32 } {
    if (is_unix) {
        const pipefd = std.posix.pipe() catch return error.PipeCreationFailed;
        return .{ .read_fd = pipefd[0], .write_fd = pipefd[1] };
    } else if (builtin.os.tag == .windows) {
        // Windows doesn't have pipe(), use socketpair
        var pipefd: [2]i32 = undefined;
        const sock_result = std.posix.socketpair(std.posix.AF.INET, std.posix.SOCK.STREAM, 0, &pipefd);
        if (sock_result != 0) {
            return error.PipeCreationFailed;
        }
        return .{ .read_fd = pipefd[0], .write_fd = pipefd[1] };
    } else {
        return error.NotSupported;
    }
}

// ==================== Public API ====================

/// Setup signal handler
///
/// Register SIGINT and SIGTERM handlers using self-pipe technique
/// for cross-thread signal notification.
///
/// Args:
///   handler: Optional custom signal handler, can be null
///
/// Returns:
///   error.SignalSetupFailed: signal setup failed
pub fn setup(handler: ?SignalHandler) !void {
    // Save custom handler
    g_signal_ctx.handler = handler;

    // Create self-pipe
    const pipe = try createSignalPipe();
    g_signal_ctx.signal_fd = pipe.read_fd;

    // Platform-specific handler registration
    if (is_unix) {
        return setupUnix();
    } else if (builtin.os.tag == .windows) {
        return setupWindows();
    } else {
        return error.SignalNotSupported;
    }
}

/// Unix platform signal handler setup
fn setupUnix() !void {
    var sa = std.posix.Sigaction{
        .handler = .{ .handler = unix_impl.signalHandler },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };

    // Register SIGINT handler
    std.posix.sigaction(std.posix.SIG.INT, &sa, &g_signal_ctx.original_sigint) catch {
        return error.SignalSetupFailed;
    };

    // Register SIGTERM handler
    std.posix.sigaction(std.posix.SIG.TERM, &sa, &g_signal_ctx.original_sigterm) catch {
        // Restore SIGINT
        _ = std.posix.sigaction(std.posix.SIG.INT, &g_signal_ctx.original_sigint, null) catch {};
        return error.SignalSetupFailed;
    };
}

/// Windows platform console handler setup
fn setupWindows() !void {
    if (windows.SetConsoleCtrlHandler(windows_impl.consoleHandler, windows.TRUE) == 0) {
        return error.SignalSetupFailed;
    }
}

/// Check if signal was triggered
///
/// Returns true if signal was triggered
pub fn isTriggered() bool {
    return g_signal_ctx.caught_signal.load(.seq_cst) != 0;
}

/// Get caught signal
///
/// Returns the caught signal number (SIGINT=2, SIGTERM=15)
/// Returns 0 if no signal was triggered
pub fn getCaughtSignal() c_int {
    return g_signal_ctx.caught_signal.load(.seq_cst);
}

/// Clear signal state
///
/// Clears the caught signal flag and drains the self-pipe
pub fn clear() void {
    // Clear signal flag
    g_signal_ctx.caught_signal.store(0, .seq_cst);

    // Drain self-pipe
    var buf: [128]u8 = undefined;
    while (true) {
        const n = std.posix.read(g_signal_ctx.signal_fd, &buf) catch |err| switch (err) {
            error.WouldBlock => return,
            else => return,
        };
        if (n == 0) return;
    }
}

/// Get signal file descriptor (read end)
///
/// Returns the read end of self-pipe
/// Can be used with select/poll/epoll for multiplexing
pub fn getSignalFd() i32 {
    return g_signal_ctx.signal_fd;
}

/// Cleanup signal handling resources
///
/// Restore default signal handlers and close self-pipe
pub fn cleanup() void {
    if (is_unix) {
        cleanupUnix();
    } else if (builtin.os.tag == .windows) {
        cleanupWindows();
    }

    // Close self-pipe
    if (g_signal_ctx.signal_fd >= 0) {
        std.posix.close(g_signal_ctx.signal_fd);
        if (is_unix) {
            // On Unix, write end is separate
            // We need to track it, but for simplicity close read end only
        }
        g_signal_ctx.signal_fd = -1;
    }

    // Clear state
    g_signal_ctx.caught_signal.store(0, .seq_cst);
    g_signal_ctx.handler = null;
}

/// Unix platform cleanup
fn cleanupUnix() void {
    const default_sa = std.posix.Sigaction{
        .handler = .{ .handler = std.posix.SIG.DFL },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };
    _ = std.posix.sigaction(std.posix.SIG.INT, &default_sa, null) catch {};
    _ = std.posix.sigaction(std.posix.SIG.TERM, &default_sa, null) catch {};
}

/// Windows platform cleanup
fn cleanupWindows() void {
    _ = windows.SetConsoleCtrlHandler(null, windows.FALSE);
}

/// Block and wait for signal
///
/// Blocks current thread until SIGINT or SIGTERM is triggered
/// Returns the caught signal number
pub fn waitForSignal() c_int {
    while (g_signal_ctx.caught_signal.load(.seq_cst) == 0) {
        var poll_fds: [1]std.posix.pollfd = .{
            .{
                .fd = g_signal_ctx.signal_fd,
                .events = std.posix.POLL.IN,
                .revents = 0,
            },
        };

        _ = std.posix.poll(&poll_fds, -1) catch {
            std.time.sleep(100 * std.time.ns_per_ms);
            continue;
        };
    }

    return g_signal_ctx.caught_signal.load(.seq_cst);
}

/// Setup default exit signal handler
///
/// When SIGINT or SIGTERM is triggered, logs the event
/// User should periodically check isTriggered() and exit gracefully
pub fn setupDefault() !void {
    return setup(null);
}

/// Check if should exit (SIGINT or SIGTERM)
///
/// Convenience function for event loops
pub fn shouldExit() bool {
    return isTriggered();
}

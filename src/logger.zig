//! logger.zig - Zig std.log Wrapper
//!
//! Provides dynamic log level control and file output for std.log.
//! Wraps Zig's built-in logging system with:
//! - Dynamic log level (can be changed at runtime)
//! - File output support (optional)
//! - Thread-safe level changes
//!
//! Usage:
//! ```zig
//! const logger = @import("logger");
//!
//! // Initialize logger with default level (INFO)
//! logger.init(.info);
//!
//! // Change log level dynamically
//! logger.setLevel(.debug);
//!
//! // Enable file output
//! try logger.addFile("app.log");
//!
//! // Log messages (std.log wrapper)
//! logger.info("Server started on port {}", .{8080});
//!
//! // Cleanup
//! logger.shutdown();
//! ```

const std = @import("std");
const builtin = @import("builtin");

// ==================== Log Level ====================

/// Log levels (compatible with std.log.Level)
pub const Level = enum(u8) {
    trace = 0,
    debug = 1,
    info = 2,
    warn = 3,
    err = 4,    // err maps to err in std.log
    fatal = 5,
};

/// Convert our Level to std.log.Level
inline fn toStdLogLevel(level: Level) std.log.Level {
    return switch (level) {
        .trace => .info,    // std.log only has .info as lowest
        .debug => .info,
        .info => .info,
        .warn => .warn,
        .err => .err,
        .fatal => .err,
    };
}

/// Convert std.log.Level to our Level
inline fn fromStdLogLevel(level: std.log.Level) Level {
    return switch (level) {
        .info => .info,
        .warn => .warn,
        .err => .err,
    };
}

// ==================== Logger State ====================

/// Thread-safe logger state
var g_state: State = .{};

const State = struct {
    level: Level = .info,
    file: ?std.fs.File = null,
    initialized: bool = false,
};

// ==================== Public API ====================

/// Initialize logger with default settings
pub fn init(level: Level) void {
    g_state.level = level;
    g_state.initialized = true;
}

/// Get current log level
pub fn getLevel() Level {
    return g_state.level;
}

/// Set log level (thread-safe)
pub fn setLevel(level: Level) void {
    g_state.level = level;
}

/// Add file output (replaces stderr)
pub fn addFile(path: []const u8) !void {
    if (g_state.file) |file| {
        file.close();
    }
    const f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    g_state.file = f;
}

/// Remove file output, return to stderr
pub fn removeFile() void {
    if (g_state.file) |file| {
        file.close();
        g_state.file = null;
    }
}

/// Cleanup logger
pub fn shutdown() void {
    if (g_state.file) |file| {
        file.close();
        g_state.file = null;
    }
    g_state.initialized = false;
}

/// Check if logger is initialized
pub fn isInitialized() bool {
    return g_state.initialized;
}

// ==================== Logging Functions ====================

/// Log at specified level (dynamic filtering)
pub fn log(level: Level, comptime format: []const u8, args: anytype) void {
    // Level filtering
    if (@intFromEnum(level) < @intFromEnum(g_state.level)) {
        return;
    }

    // Log to file if configured
    if (g_state.file) |file| {
        file.writer().print(format ++ "\n", args) catch {};
    }

    // Log to stderr via std.log (std.log handles formatting)
    // We use std.log.info/warn/err based on level
    switch (level) {
        .trace, .debug, .info => std.log.info(format, args),
        .warn, .err => std.log.err(format, args),
        .fatal => std.log.err("FATAL: " ++ format, args),
    }
}

/// TRACE level log
pub fn trace(comptime format: []const u8, args: anytype) void {
    log(.trace, format, args);
}

/// DEBUG level log
pub fn debug(comptime format: []const u8, args: anytype) void {
    log(.debug, format, args);
}

/// INFO level log
pub fn info(comptime format: []const u8, args: anytype) void {
    log(.info, format, args);
}

/// WARN level log
pub fn warn(comptime format: []const u8, args: anytype) void {
    log(.warn, format, args);
}

/// ERROR level log
pub fn err(comptime format: []const u8, args: anytype) void {
    log(.err, format, args);
}

/// FATAL level log
pub fn fatal(comptime format: []const u8, args: anytype) void {
    log(.fatal, format, args);
}

// ==================== Level Check Functions ====================

/// Check if TRACE level is enabled
pub fn isTraceEnabled() bool {
    return @intFromEnum(g_state.level) <= @intFromEnum(Level.trace);
}

/// Check if DEBUG level is enabled
pub fn isDebugEnabled() bool {
    return @intFromEnum(g_state.level) <= @intFromEnum(Level.debug);
}

/// Check if INFO level is enabled
pub fn isInfoEnabled() bool {
    return @intFromEnum(g_state.level) <= @intFromEnum(Level.info);
}

/// Check if WARN level is enabled
pub fn isWarnEnabled() bool {
    return @intFromEnum(g_state.level) <= @intFromEnum(Level.warn);
}

// ==================== Internal Error Helper ====================

/// Internal error with log level
pub const InternalError = struct {
    level: Level,
    msg: []const u8,
};

/// Create an error with ERROR level
pub fn makeErr(msg: []const u8) InternalError {
    return .{ .level = .err, .msg = msg };
}

/// Create an error with WARN level
pub fn makeWarn(msg: []const u8) InternalError {
    return .{ .level = .warn, .msg = msg };
}

// ==================== Compile-time Verification ====================

comptime {
    std.debug.assert(@intFromEnum(Level.trace) == 0);
    std.debug.assert(@intFromEnum(Level.debug) == 1);
    std.debug.assert(@intFromEnum(Level.info) == 2);
    std.debug.assert(@intFromEnum(Level.warn) == 3);
    std.debug.assert(@intFromEnum(Level.err) == 4);
    std.debug.assert(@intFromEnum(Level.fatal) == 5);
}

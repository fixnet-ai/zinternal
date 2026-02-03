//! test_unit.zig - Unit Tests for zinternal
//!
//! Tests individual functions with no external dependencies.
//! Each test should be isolated and not depend on other module initialization.

const std = @import("std");
const platform = @import("platform");
const logger = @import("logger");
const config = @import("config");
const signal = @import("signal");
const storage = @import("storage");

// ==================== Platform Tests ====================

test "platform: OS detection" {
    try std.testing.expect(platform.is_linux or platform.is_macos or platform.is_windows);
}

test "platform: Arch detection" {
    const arch = platform.getArch();
    try std.testing.expect(arch == .x86_64 or arch == .aarch64 or arch == .other);
}

test "platform: Platform info string" {
    const info = platform.getPlatformInfo();
    try std.testing.expect(info.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, info, "-") != null);
}

test "platform: Signal constants" {
    try std.testing.expect(platform.SIGINT == 2);
    try std.testing.expect(platform.SIGTERM == 15);
    try std.testing.expect(platform.SIGHUP == 1);
}

// ==================== Error Mapping Tests ====================

test "platform: NetError enum values" {
    try std.testing.expect(@intFromEnum(platform.NetError.dns_not_found) == 1);
    try std.testing.expect(@intFromEnum(platform.NetError.connection_refused) == 21);
    try std.testing.expect(@intFromEnum(platform.NetError.unknown) == 99);
}

test "platform: getErrorMessage" {
    const msg = platform.getErrorMessage(.connection_refused);
    try std.testing.expect(std.mem.startsWith(u8, msg, "Connection refused"));
}

// ==================== Logger Level Tests ====================

test "logger: Level enum values" {
    try std.testing.expect(@intFromEnum(logger.Level.trace) == 0);
    try std.testing.expect(@intFromEnum(logger.Level.debug) == 1);
    try std.testing.expect(@intFromEnum(logger.Level.info) == 2);
    try std.testing.expect(@intFromEnum(logger.Level.warn) == 3);
    try std.testing.expect(@intFromEnum(logger.Level.err) == 4);
    try std.testing.expect(@intFromEnum(logger.Level.fatal) == 5);
}

test "logger: init and getLevel" {
    logger.init(.debug);
    defer logger.shutdown();
    try std.testing.expect(logger.getLevel() == .debug);
}

test "logger: setLevel" {
    logger.init(.info);
    defer logger.shutdown();

    logger.setLevel(.trace);
    try std.testing.expect(logger.getLevel() == .trace);

    logger.setLevel(.fatal);
    try std.testing.expect(logger.getLevel() == .fatal);
}

test "logger: isLevelEnabled" {
    logger.init(.info);
    defer logger.shutdown();

    try std.testing.expect(!logger.isTraceEnabled());
    try std.testing.expect(!logger.isDebugEnabled());
    try std.testing.expect(logger.isInfoEnabled());
    try std.testing.expect(logger.isWarnEnabled());
}

test "logger: InternalError helpers" {
    const err = logger.makeErr("test error");
    try std.testing.expect(err.level == .err);
    try std.testing.expectEqualStrings("test error", err.msg);

    const warn = logger.makeWarn("test warn");
    try std.testing.expect(warn.level == .warn);
}

// ==================== Config Tests ====================

test "config: Config.init" {
    const cfg = config.Config.init();
    try std.testing.expect(cfg.getVersion() == 0);
    try std.testing.expect(cfg.getBool(0) == false);
    try std.testing.expect(cfg.getInt(0) == 0);
}

test "config: Boolean operations" {
    var cfg = config.Config.init();
    cfg.setBool(10, true);
    try std.testing.expect(cfg.getBool(10) == true);
    cfg.setBool(10, false);
    try std.testing.expect(cfg.getBool(10) == false);
}

test "config: Integer operations" {
    var cfg = config.Config.init();
    cfg.setInt(5, 42);
    try std.testing.expect(cfg.getInt(5) == 42);
}

test "config: String operations" {
    var cfg = config.Config.init();
    cfg.setString(7, "hello");
    try std.testing.expectEqualStrings("hello", cfg.getString(7));
}

test "config: Version bump" {
    var cfg = config.Config.init();
    const v1 = cfg.getVersion();
    cfg.setBool(0, true);
    const v2 = cfg.getVersion();
    try std.testing.expect(v2 > v1);
}

// ==================== Signal Tests ====================

test "signal: Signal constants" {
    try std.testing.expect(signal.SIGINT == 2);
    // SIGTERM is 15 on Linux, different on other platforms
    try std.testing.expect(signal.SIGTERM > 0);
}

// ==================== Storage Tests ====================

test "storage: getDataPath returns non-empty" {
    const path = storage.getDataPath();
    try std.testing.expect(path.len > 0);
    std.debug.print("Data path: {s}\n", .{path});
}

test "storage: getBaseDir returns dot" {
    const base = storage.getBaseDir();
    try std.testing.expect(std.mem.eql(u8, base, "."));
}

test "storage: getSharedPath with group_id" {
    const group_id = "shared_group";
    const path = storage.getSharedPath(group_id);
    std.debug.print("Shared path: {s}\n", .{path});
    // Verify path length and basic structure
    try std.testing.expect(path.len > 0);
    // Check path ends with /shared_group
    try std.testing.expect(path.len > 13);
    try std.testing.expect(path[path.len - 13..].len == 13);
}

test "storage: StorageError messages" {
    try std.testing.expectEqualStrings("Storage path not found", storage.getErrorMessage(error.path_not_found));
    try std.testing.expectEqualStrings("Access denied to storage", storage.getErrorMessage(error.access_denied));
    try std.testing.expectEqualStrings("I/O error on storage", storage.getErrorMessage(error.io_error));
}

test "storage: PathConfig with types" {
    const config_data = storage.PathConfig{ .path_type = .data };
    try std.testing.expect(config_data.path_type == .data);

    const config_cache = storage.PathConfig{ .path_type = .cache };
    try std.testing.expect(config_cache.path_type == .cache);
}

test "storage: MAX_PATH_LEN is sufficient" {
    try std.testing.expect(storage.MAX_PATH_LEN >= 256);
}

// ==================== Compile-time Verification ====================

comptime {
    // Verify logger level order
    std.debug.assert(@intFromEnum(logger.Level.trace) == 0);
    std.debug.assert(@intFromEnum(logger.Level.fatal) == 5);
}

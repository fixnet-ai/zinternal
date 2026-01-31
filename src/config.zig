//! config.zig - Lock-free Configuration Storage
//!
//! Lock-free concurrent configuration storage using atomic variables.
//! Supports three data types: bool, u64, and string (fixed 256 bytes).
//!
//! Design principles:
//! - Framework layer provides generic storage mechanism, not config items
//! - Application layer defines config items and their IDs
//! - All operations are atomic, thread-safe
//!
//! Usage:
//! ```zig
//! const config = @import("config");
//!
//! // Define config item IDs
//! pub const AppConfigId = enum(u8) {
//!     dns_enabled = 0,
//!     proxy_port = 1,
//!     log_level = 2,
//! };
//!
//! // Set/get values
//! config.setBool(@intFromEnum(AppConfigId.dns_enabled), true);
//! config.setInt(@intFromEnum(AppConfigId.proxy_port), 1080);
//! ```
//!

const std = @import("std");

// ==================== Constants ====================

/// Maximum number of config items (u8 keys: 0-255)
pub const MAX_CONFIG_ITEMS: usize = 256;

/// Maximum string length
pub const MAX_STRING_SIZE: usize = 256;

// ==================== Config Storage ====================

/// Lock-free configuration table
/// Supports three data types: bool, u64, string
/// All operations are atomic and thread-safe
pub const Config = struct {
    /// Atomic bool array (1-byte aligned)
    bool_values: [MAX_CONFIG_ITEMS]std.atomic.Value(bool) align(1),

    /// Atomic integer array (16-byte aligned for cmpxchg16b requirement)
    int_values: [MAX_CONFIG_ITEMS]std.atomic.Value(u64) align(16),

    /// String storage (fixed size, no heap allocation)
    string_storage: [MAX_CONFIG_ITEMS][MAX_STRING_SIZE]u8,

    /// String lengths (atomically updated)
    string_lengths: [MAX_CONFIG_ITEMS]std.atomic.Value(u16) align(2),

    /// Config version number (atomically updated)
    version: std.atomic.Value(u64) align(16),

    const Self = @This();

    /// Initialize config table
    pub fn init() Self {
        var config: Self = undefined;

        // Initialize bool values
        for (&config.bool_values) |*val| {
            val.* = std.atomic.Value(bool).init(false);
        }

        // Initialize int values
        for (&config.int_values) |*val| {
            val.* = std.atomic.Value(u64).init(0);
        }

        // Initialize string lengths
        for (&config.string_lengths) |*len| {
            len.* = std.atomic.Value(u16).init(0);
        }

        // Initialize version
        config.version = std.atomic.Value(u64).init(0);

        return config;
    }

    // ==================== Bool Operations ====================

    /// Set bool value (atomic operation)
    /// Uses monotonic memory order (fastest, no cross-thread sync needed)
    pub fn setBool(self: *Self, key: u8, value: bool) void {
        self.bool_values[key].store(value, .monotonic);
        self.bumpVersion();
    }

    /// Get bool value (atomic read)
    pub fn getBool(self: *const Self, key: u8) bool {
        return self.bool_values[key].load(.monotonic);
    }

    // ==================== Integer Operations ====================

    /// Set integer value (atomic operation)
    pub fn setInt(self: *Self, key: u8, value: u64) void {
        self.int_values[key].store(value, .monotonic);
        self.bumpVersion();
    }

    /// Get integer value (atomic read)
    pub fn getInt(self: *const Self, key: u8) u64 {
        return self.int_values[key].load(.monotonic);
    }

    // ==================== String Operations ====================

    /// Set string value (atomic length update)
    /// Strategy: copy string content first, then atomically update length
    /// This ensures readers see either old value or new value, never partial
    pub fn setString(self: *Self, key: u8, value: []const u8) void {
        // Copy string content
        const copy_len = @min(value.len, MAX_STRING_SIZE);
        @memcpy(self.string_storage[key][0..copy_len], value[0..copy_len]);

        // Atomically update length
        self.string_lengths[key].store(@as(u16, @intCast(copy_len)), .monotonic);
        self.bumpVersion();
    }

    /// Get string value (atomic length read)
    pub fn getString(self: *const Self, key: u8) []const u8 {
        const len = self.string_lengths[key].load(.monotonic);
        return self.string_storage[key][0..len];
    }

    // ==================== Version Management ====================

    /// Increment config version number (atomic operation)
    fn bumpVersion(self: *Self) void {
        _ = self.version.fetchAdd(1, .monotonic);
    }

    /// Get config version number
    pub fn getVersion(self: *const Self) u64 {
        return self.version.load(.monotonic);
    }
};

// ==================== Global Singleton ====================

/// Global config singleton
/// Critical: global variable must be explicitly aligned for internal atomic variables
var g_config: Config align(16) = undefined;
var g_config_initialized: bool = false;

/// Initialize global config system
pub fn initialize() void {
    if (g_config_initialized) {
        return;
    }
    g_config = Config.init();
    g_config_initialized = true;
}

/// Check if initialized
pub fn isInitialized() bool {
    return g_config_initialized;
}

/// Get global config reference
pub fn get() *Config {
    return &g_config;
}

// ==================== Convenience Functions ====================

/// Set bool value (global convenience function)
pub fn setBool(key: u8, value: bool) void {
    g_config.setBool(key, value);
}

/// Get bool value (global convenience function)
pub fn getBool(key: u8) bool {
    return g_config.getBool(key);
}

/// Set integer value (global convenience function)
pub fn setInt(key: u8, value: u64) void {
    g_config.setInt(key, value);
}

/// Get integer value (global convenience function)
pub fn getInt(key: u8) u64 {
    return g_config.getInt(key);
}

/// Set string value (global convenience function)
pub fn setString(key: u8, value: []const u8) void {
    g_config.setString(key, value);
}

/// Get string value (global convenience function)
pub fn getString(key: u8) []const u8 {
    return g_config.getString(key);
}

/// Get config version (global convenience function)
pub fn getVersion() u64 {
    return g_config.getVersion();
}

//! storage.zig - Cross-platform Storage Path Abstraction
//!
//! Provides unified storage access across platforms:
//! - Win/Mac/Linux: Executable directory ("./" as abstraction)
//! - Android: App's internal files directory via Environment
//! - iOS: App's Documents directory via Environment
//! - Shared: Cross-process shared directory for App + Extension
//!
//! Usage:
//! ```zig
//! const storage = @import("storage");
//!
//! // Get data path ("./" on desktop, platform-specific on mobile)
//! const path = storage.getDataPath();
//!
//! // Open file relative to data path
//! const file = try storage.openFile("config.json", .{});
//!
//! // Shared directory for App + Extension
//! const shared_path = storage.getSharedPath("com.example.shared");
//! ```

const std = @import("std");
const builtin = @import("builtin");

// Re-export platform detection from platform module
const platform = @import("platform");
const is_linux = platform.is_linux;
const is_macos = platform.is_macos;
const is_windows = platform.is_windows;
const is_android = platform.is_android;
const is_ios = platform.is_ios;
const is_mobile = platform.is_mobile;
const is_posix = platform.is_posix;

// ==================== Storage Error Codes ====================

/// Unified storage errors
pub const StorageError = error{
    // Path errors (1-10)
    path_not_found,
    path_invalid,
    path_too_long,

    // Permission errors (11-20)
    access_denied,
    read_only,

    // I/O errors (21-30)
    io_error,
    disk_full,
    file_exists,
    file_not_found,

    // Platform errors (31-40)
    jni_error,
    platform_not_supported,
    shared_dir_failed,

    // Unknown error (99)
    unknown,
};

/// Map Zig std.errors to StorageError
pub fn mapError(err: anyerror) StorageError {
    return switch (err) {
        error.PathNotFound => error.path_not_found,
        error.InvalidUtf8, error.InvalidPath => error.path_invalid,
        error.NameTooLong => error.path_too_long,
        error.AccessDenied => error.access_denied,
        error.ReadOnlyFileSystem => error.read_only,
        error.IO => error.io_error,
        error.NoSpaceLeft => error.disk_full,
        error.PathAlreadyExists => error.file_exists,
        error.FileNotFound => error.file_not_found,
        else => error.unknown,
    };
}

/// Get friendly error message
pub fn getErrorMessage(err: StorageError) []const u8 {
    return switch (err) {
        error.path_not_found => "Storage path not found",
        error.path_invalid => "Invalid storage path",
        error.path_too_long => "Storage path too long",
        error.access_denied => "Access denied to storage",
        error.read_only => "Storage is read-only",
        error.io_error => "I/O error on storage",
        error.disk_full => "Storage disk is full",
        error.file_exists => "File already exists",
        error.file_not_found => "File not found",
        error.jni_error => "JNI operation failed",
        error.platform_not_supported => "Platform not supported",
        error.shared_dir_failed => "Shared directory operation failed",
        error.unknown => "Unknown storage error",
    };
}

// ==================== Path Types ====================

/// Storage path type
pub const PathType = enum {
    data,       // App's private data directory
    cache,      // Cache directory (may be cleared by OS)
    documents,  // User documents (iOS)
    library,    // App library directory (iOS)
    shared,     // App Group shared container
};

/// Storage path configuration
pub const PathConfig = struct {
    path_type: PathType = .data,
};

// ==================== Path Buffer ====================

/// Maximum path length for storage operations
pub const MAX_PATH_LEN = 256;

/// Thread-local path buffer for getDataPath
threadlocal var g_path_buf: [MAX_PATH_LEN]u8 = undefined;

// ==================== Core API ====================

/// Get the data path for the current platform
/// Returns "./" on desktop (executable directory), platform-specific path on mobile
pub fn getDataPath() []const u8 {
    if (is_mobile) {
        return getMobileDataPath();
    }
    return getDesktopDataPath();
}

/// Get the base directory abstraction (".")
pub fn getBaseDir() []const u8 {
    return ".";
}

/// Get shared directory path for cross-process communication
/// Used by App + Extension to share configuration
pub fn getSharedPath(group_id: []const u8) []const u8 {
    var buf: [MAX_PATH_LEN]u8 = undefined;
    return getSharedPathInto(&buf, group_id);
}

/// Get shared path into provided buffer
pub fn getSharedPathInto(buf: []u8, group_id: []const u8) []const u8 {
    if (is_mobile) {
        return getMobileSharedPath(buf, group_id);
    }
    return getDesktopSharedPath(buf, group_id);
}

// ==================== Desktop Platform Implementation ====================

fn getDesktopDataPath() []const u8 {
    // Desktop platforms use executable directory as "./" abstraction
    return std.fs.selfExeDirPath(&g_path_buf) catch "./";
}

fn getDesktopSharedPath(buf: []u8, group_id: []const u8) []const u8 {
    // First get the executable directory
    const exe_path = std.fs.selfExeDirPath(&g_path_buf) catch "./";
    const exe_dir = if (std.mem.startsWith(u8, exe_path, "./")) exe_path else exe_path;
    const exe_dir_len = exe_dir.len;

    const subpath = "/shared/";
    const needed = exe_dir_len + subpath.len + group_id.len;
    if (needed >= buf.len) {
        return "./";
    }

    @memcpy(buf[0..exe_dir_len], exe_dir);
    @memcpy(buf[exe_dir_len..][0..subpath.len], subpath);
    @memcpy(buf[exe_dir_len + subpath.len..][0..group_id.len], group_id);

    return buf[0..needed];
}

// ==================== Mobile Platform Implementation ====================

fn getMobileDataPath() []const u8 {
    if (is_android) {
        return getAndroidDataPath();
    } else if (is_ios) {
        return getIosDataPath();
    }
    return "./";
}

fn getAndroidDataPath() []const u8 {
    // Try environment variables first
    const data_dir = std.os.getenv("ANDROID_DATA") orelse "/data";
    const package_name = std.os.getenv("ANDROID_PACKAGE_NAME") orelse "com.unknown.app";

    const result = std.fmt.bufPrint(&g_path_buf, "{s}/data/{s}/files", .{ data_dir, package_name }) catch {
        return "./";
    };
    return result;
}

fn getIosDataPath() []const u8 {
    // iOS apps have a sandboxed Documents directory
    // Can be accessed via HOME environment variable on simulator
    const home = std.os.getenv("HOME") orelse "./";

    const result = std.fmt.bufPrint(&g_path_buf, "{s}/Documents", .{home}) catch {
        return "./";
    };
    return result;
}

fn getMobileSharedPath(buf: []u8, group_id: []const u8) []const u8 {
    if (is_android) {
        return getAndroidSharedPath(buf, group_id);
    } else if (is_ios) {
        return getIosSharedPath(buf, group_id);
    }
    return "./";
}

fn getAndroidSharedPath(buf: []u8, group_id: []const u8) []const u8 {
    // Android: Use external storage for shared data
    // Path: /sdcard/Android/data/{pkg}/files/shared/{group_id}
    const external = std.os.getenv("EXTERNAL_STORAGE") orelse "/sdcard";
    const package_name = std.os.getenv("ANDROID_PACKAGE_NAME") orelse "com.unknown.app";

    const result = std.fmt.bufPrint(
        buf,
        "{s}/Android/data/{s}/files/shared/{s}",
        .{ external, package_name, group_id },
    ) catch {
        return "./";
    };

    return result;
}

fn getIosSharedPath(buf: []u8, group_id: []const u8) []const u8 {
    // iOS: Use App Group container or Documents directory
    // For Extension sharing, App Group is required
    const home = std.os.getenv("HOME") orelse "./";

    // Try to use App Group if available (via CFBundleIdentifier-like path)
    // Fallback to Documents/shared/{group_id}
    const result = std.fmt.bufPrint(
        buf,
        "{s}/Documents/shared/{s}",
        .{ home, group_id },
    ) catch {
        return "./";
    };

    return result;
}

// ==================== File Operations ====================

/// File open options
pub const OpenOptions = struct {
    read: bool = true,
    write: bool = false,
    create: bool = false,
    truncate: bool = false,
    append: bool = false,
};

pub fn openFile(rel_path: []const u8, options: OpenOptions) StorageError!std.fs.File {
    const abs_path = try resolvePath(rel_path);

    return std.fs.File.openPathAbsolute(abs_path, .{
        .read = options.read,
        .write = options.write,
        .mode = if (options.create) blk: {
            break :blk if (options.truncate) .truncate else .exclusive;
        } else {},
    }) catch |err| return mapError(err);
}

pub fn readFile(allocator: std.mem.Allocator, rel_path: []const u8) StorageError![]const u8 {
    const abs_path = try resolvePath(rel_path);

    return std.fs.cwd().readFileAlloc(allocator, abs_path, std.math.maxInt(usize)) catch |err| {
        return mapError(err);
    };
}

pub fn writeFile(rel_path: []const u8, data: []const u8) StorageError!void {
    const abs_path = try resolvePath(rel_path);

    const file = std.fs.cwd().createFile(abs_path, .{ .truncate = true }) catch |err| {
        return mapError(err);
    };
    defer file.close();
    file.writeAll(data) catch |err| return mapError(err);
}

pub fn createDir(rel_path: []const u8) StorageError!void {
    var abs_buf: [MAX_PATH_LEN]u8 = undefined;
    const abs_path = try resolvePathInto(rel_path, &abs_buf);

    std.fs.cwd().makePath(abs_path) catch |err| return mapError(err);
}

pub fn deleteFile(rel_path: []const u8) StorageError!void {
    const abs_path = try resolvePath(rel_path);

    std.fs.cwd().deleteFile(abs_path) catch |err| return mapError(err);
}

pub fn exists(rel_path: []const u8) StorageError!bool {
    const abs_path = try resolvePath(rel_path);

    std.fs.cwd().access(abs_path, .{}) catch |err| {
        if (err == error.FileNotFound) return false;
        return mapError(err);
    };
    return true;
}

pub fn getFileSize(rel_path: []const u8) StorageError!usize {
    const file = try openFile(rel_path, .{ .read = true });
    defer file.close();

    return file.getEndPos() catch |err| return mapError(err);
}

// ==================== Path Resolution ====================

fn resolvePath(rel_path: []const u8) StorageError![]const u8 {
    var buf: [MAX_PATH_LEN]u8 = undefined;
    return resolvePathInto(rel_path, &buf);
}

fn resolvePathInto(rel_path: []const u8, buf: []u8) StorageError![]const u8 {
    const base_path = getDataPath();

    if (rel_path.len == 0 or std.mem.eql(u8, rel_path, ".")) {
        return base_path;
    }

    if (isAbsolutePath(rel_path)) {
        if (rel_path.len >= buf.len) return error.path_too_long;
        @memcpy(buf[0..rel_path.len], rel_path);
        return buf[0..rel_path.len];
    }

    const full_path = std.fmt.bufPrint(buf, "{s}/{s}", .{ base_path, rel_path }) catch {
        return error.path_too_long;
    };

    return full_path;
}

fn isAbsolutePath(path: []const u8) bool {
    if (is_windows) {
        return path.len >= 3 and path[1] == ':' and (path[2] == '/' or path[2] == '\\');
    } else {
        return path.len > 0 and path[0] == '/';
    }
}

// ==================== Compile-time Verification ====================

//! errors.zig - Cross-platform Error Mapping
//!
//! Provides unified error code mapping across platforms:
//! - POSIX errno (Linux/macOS)
//! - Windows WSA error codes
//! - Unified NetError enum
//!
//! Usage:
//! ```zig
//! const errors = @import("errors");
//!
//! // Map platform errno to unified error
//! const err = errors.mapErrno(111); // ECONNREFUSED on Linux
//!
//! // Get friendly error message
//! std.debug.print("{s}\n", .{errors.getErrorMessage(err)});
//! ```

const std = @import("std");
const builtin = @import("builtin");

// ==================== Platform Detection ====================

/// Check if running on Windows
const is_windows = builtin.target.os.tag == .windows;

/// Check if running on macOS
const is_macos = builtin.target.os.tag == .macos;

// ==================== Unified Network Error Codes ====================

/// Unified network error codes (based on POSIX.1-2008)
pub const NetError = enum(u16) {
    // DNS/address resolution errors (1-10)
    dns_not_found = 1,
    dns_temporary_failure = 2,
    address_invalid = 3,

    // Address-related errors (11-20)
    address_in_use = 11,
    address_not_available = 12,
    address_family_not_supported = 13,
    destination_address_required = 14,

    // Connection-related errors (21-35)
    connection_refused = 21,
    connection_timed_out = 22,
    connection_aborted = 23,
    connection_reset = 24,
    connection_in_progress = 25,
    connection_already_in_progress = 26,
    network_reset = 27,
    not_connected = 28,
    already_connected = 29,

    // Network status errors (36-42)
    network_unreachable = 36,
    network_down = 37,
    host_unreachable = 38,
    no_buffer_space = 39,
    resource_unavailable = 40,

    // Protocol-related errors (41-48)
    protocol_not_supported = 41,
    protocol_not_available = 42,
    protocol_wrong_type = 43,
    protocol_error = 44,
    operation_not_supported = 45,

    // Socket-related errors (46-50)
    not_a_socket = 46,
    message_too_large = 47,
    broken_pipe = 48,

    // Permission/I/O errors (51-55)
    permission_denied = 51,
    operation_not_permitted = 52,
    io_error = 53,

    // Argument/system errors (56-60)
    invalid_argument = 56,

    // Other errors (91-99)
    unknown = 99,
};

// ==================== Platform-specific errno Values ====================

/// Platform-specific errno values (compile-time determined)
pub const errno = if (is_windows)
    struct {
        const WSAEINPROGRESS = 10036;
        const WSAETIMEDOUT = 10060;
        const WSAECONNREFUSED = 10061;
        const WSAENETUNREACH = 10051;
        const WSAEHOSTUNREACH = 10065;
        const WSAEINVAL = 10022;
        const WSAENOTFOUND = 10108;
        const WSAEADDRINUSE = 10048;
        const WSAEADDRNOTAVAIL = 10049;
        const WSAEAFNOSUPPORT = 10047;
        const WSAEDESTADDRREQ = 10039;
        const WSAEALREADY = 10037;
        const WSAECONNABORTED = 10053;
        const WSAECONNRESET = 10054;
        const WSAENETRESET = 10052;
        const WSAENOTCONN = 10057;
        const WSAEISCONN = 10056;
        const WSAENETDOWN = 10050;
        const WSAENOBUFS = 10055;
        const WSAEWOULDBLOCK = 10035;
        const WSAEPROTONOSUPPORT = 10043;
        const WSAENOPROTOOPT = 10042;
        const WSAEPROTOTYPE = 10041;
        const WSAENOTSUP = WSAEOPNOTSUPP;
        const WSAEOPNOTSUPP = 10045;
        const WSAENOTSOCK = 10038;
        const WSAEMSGSIZE = 10040;
        const WSAEPIPE = 10032;
        const WSAEACCES = 10013;
        const WSAEPERM = WSAEACCES;
        const WSAEIO = 10006;
    }
else if (is_macos)
    struct {
        const EINPROGRESS = 36;
        const ETIMEDOUT = 60;
        const ECONNREFUSED = 61;
        const ENETUNREACH = 101;
        const EHOSTUNREACH = 65;
        const EINVAL = 22;
        const ENOENT = 2;
        const EAI_NONAME = 8;
        const EADDRINUSE = 48;
        const EADDRNOTAVAIL = 49;
        const EAFNOSUPPORT = 47;
        const EDESTADDRREQ = 39;
        const EALREADY = 37;
        const ECONNABORTED = 53;
        const ECONNRESET = 54;
        const ENETRESET = 52;
        const ENOTCONN = 57;
        const EISCONN = 56;
        const ENETDOWN = 50;
        const ENOBUFS = 55;
        const EAGAIN = 35;
        const EWOULDBLOCK = EAGAIN;
        const EPROTONOSUPPORT = 43;
        const ENOPROTOOPT = 42;
        const EPROTOTYPE = 41;
        const EPROTO = 100;
        const ENOTSUP = 102;
        const EOPNOTSUPP = ENOTSUP;
        const ENOTSOCK = 38;
        const EMSGSIZE = 40;
        const EPIPE = 32;
        const EACCES = 13;
        const EPERM = 1;
        const EIO = 5;
    }
else // Linux
    struct {
        const EINPROGRESS = 115;
        const ETIMEDOUT = 110;
        const ECONNREFUSED = 111;
        const ENETUNREACH = 101;
        const EHOSTUNREACH = 113;
        const EINVAL = 22;
        const ENOENT = 2;
        const EAI_NONAME = -2;
        const EADDRINUSE = 98;
        const EADDRNOTAVAIL = 99;
        const EAFNOSUPPORT = 97;
        const EDESTADDRREQ = 89;
        const EALREADY = 114;
        const ECONNABORTED = 103;
        const ECONNRESET = 104;
        const ENETRESET = 102;
        const ENOTCONN = 107;
        const EISCONN = 106;
        const ENETDOWN = 100;
        const ENOBUFS = 105;
        const EAGAIN = 11;
        const EPROTONOSUPPORT = 93;
        const ENOPROTOOPT = 92;
        const EPROTOTYPE = 91;
        const EPROTO = 71;
        const ENOTSUP = 95;
        const EOPNOTSUPP = ENOTSUP;
        const ENOTSOCK = 88;
        const EMSGSIZE = 90;
        const EPIPE = 32;
        const EACCES = 13;
        const EPERM = 1;
        const EIO = 5;
    };

// ==================== Error Mapping Functions ====================

/// Map platform errno to unified NetError (compile-time optimized)
pub fn mapErrno(err: c_int) NetError {
    if (err == 0) return .connection_aborted;

    // DNS error check (negative range)
    if (err < 0 and err > -20) return .dns_not_found;

    if (comptime is_windows) {
        return mapWindowsWSAError(err);
    } else {
        return mapPosixErrno(err);
    }
}

/// POSIX platform error code mapping (macOS/Linux)
inline fn mapPosixErrno(err: c_int) NetError {
    if (err == errno.EAI_NONAME) return .dns_not_found;

    return switch (err) {
        errno.EADDRINUSE => .address_in_use,
        errno.EADDRNOTAVAIL => .address_not_available,
        errno.EAFNOSUPPORT => .address_family_not_supported,
        errno.EDESTADDRREQ => .destination_address_required,

        errno.ECONNREFUSED => .connection_refused,
        errno.ETIMEDOUT => .connection_timed_out,
        errno.ECONNABORTED => .connection_aborted,
        errno.ECONNRESET => .connection_reset,
        errno.EINPROGRESS => .connection_in_progress,
        errno.EALREADY => .connection_already_in_progress,
        errno.ENETRESET => .network_reset,
        errno.ENOTCONN => .not_connected,
        errno.EISCONN => .already_connected,

        errno.ENETUNREACH => .network_unreachable,
        errno.ENETDOWN => .network_down,
        errno.EHOSTUNREACH => .host_unreachable,
        errno.ENOBUFS => .no_buffer_space,
        errno.EAGAIN => .resource_unavailable,

        errno.EPROTONOSUPPORT => .protocol_not_supported,
        errno.ENOPROTOOPT => .protocol_not_available,
        errno.EPROTOTYPE => .protocol_wrong_type,
        errno.EPROTO => .protocol_error,

        errno.ENOTSOCK => .not_a_socket,
        errno.EMSGSIZE => .message_too_large,
        errno.EPIPE => .broken_pipe,

        errno.EACCES => .permission_denied,
        errno.EPERM => .operation_not_permitted,
        errno.EIO => .io_error,

        errno.EINVAL => .invalid_argument,
        errno.ENOENT => .dns_not_found,

        else => .unknown,
    };
}

/// Windows platform: map WSA error codes
inline fn mapWindowsWSAError(err: c_int) NetError {
    return switch (err) {
        10061 => .connection_refused,
        10060 => .connection_timed_out,
        10053 => .connection_aborted,
        10054 => .connection_reset,
        10048 => .address_in_use,
        10049 => .address_not_available,
        10047 => .address_family_not_supported,
        10039 => .destination_address_required,
        10052 => .network_reset,
        10057 => .not_connected,
        10056 => .already_connected,
        10050 => .network_down,
        10051 => .network_unreachable,
        10065 => .host_unreachable,
        10055 => .no_buffer_space,
        10035 => .resource_unavailable,
        10043 => .protocol_not_supported,
        10042 => .protocol_not_available,
        10041 => .protocol_wrong_type,
        10045 => .operation_not_supported,
        10038 => .not_a_socket,
        10040 => .message_too_large,
        10013 => .permission_denied,
        10006 => .io_error,
        10022 => .invalid_argument,
        else => .unknown,
    };
}

// ==================== Error Messages ====================

/// Get friendly error message for NetError
pub fn getErrorMessage(err: NetError) []const u8 {
    return switch (err) {
        .dns_not_found => "Cannot resolve hostname",
        .dns_temporary_failure => "DNS temporary failure",
        .address_invalid => "Invalid address format",

        .address_in_use => "Address already in use",
        .address_not_available => "Address not available",
        .address_family_not_supported => "Address family not supported",
        .destination_address_required => "Destination address required",

        .connection_refused => "Connection refused",
        .connection_timed_out => "Connection timed out",
        .connection_aborted => "Connection aborted",
        .connection_reset => "Connection reset",
        .connection_in_progress => "Connection in progress",
        .connection_already_in_progress => "Connection already in progress",
        .network_reset => "Network reset connection",
        .not_connected => "Socket not connected",
        .already_connected => "Socket already connected",

        .network_unreachable => "Network unreachable",
        .network_down => "Network down",
        .host_unreachable => "Host unreachable",
        .no_buffer_space => "No buffer space available",
        .resource_unavailable => "Resource temporarily unavailable",

        .protocol_not_supported => "Protocol not supported",
        .protocol_not_available => "Protocol not available",
        .protocol_wrong_type => "Protocol wrong type for socket",
        .protocol_error => "Protocol error",
        .operation_not_supported => "Operation not supported",

        .not_a_socket => "Not a socket",
        .message_too_large => "Message too large",
        .broken_pipe => "Broken pipe",

        .permission_denied => "Permission denied",
        .operation_not_permitted => "Operation not permitted",
        .io_error => "I/O error",

        .invalid_argument => "Invalid argument",

        .unknown => "Unknown error",
    };
}

/// Get friendly error message from errno code
pub fn getErrorMessageFromErrno(errno_code: c_int) []const u8 {
    return getErrorMessage(mapErrno(errno_code));
}

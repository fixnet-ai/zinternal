# zinternal Design Document

## Architecture Overview

```
zinternal/
├── src/
│   ├── platform.zig      # Platform abstraction layer
│   ├── errors.zig        # Error code mapping (POSIX/Windows)
│   ├── logger.zig        # Logging wrapper (std.log)
│   ├── config.zig        # Lock-free configuration
│   ├── signal.zig        # Signal handling
│   └── app.zig           # Application framework
└── tests/
    ├── test_unit.zig     # Unit tests
    └── test_runner.zig   # Integration tests
```

## Module Dependencies

```
app.zig
    ├── platform.zig
    ├── errors.zig
    ├── logger.zig
    ├── signal.zig
    └── config.zig

platform.zig
    └── errors.zig

signal.zig
    ├── platform.zig
    └── logger.zig
```

## Module Specifications

### errors.zig

Cross-platform error code mapping providing unified NetError enum and errno translation.

#### Types

```zig
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
    // ... more errors

    unknown = 99,
};
```

#### Constants

```zig
pub const errno  // Platform-specific errno values (compile-time determined)
```

#### Functions

```zig
pub fn mapErrno(err: c_int) NetError
pub fn getErrorMessage(err: NetError) []const u8
pub fn getErrorMessageFromErrno(errno_code: c_int) []const u8
```

### platform.zig

Cross-platform abstraction layer providing OS detection, aligned allocator, and errno mapping (errors are re-exported from errors.zig).

#### Constants

```zig
pub const is_linux: bool
pub const is_macos: bool
pub const is_windows: bool
pub const is_posix: bool
pub const is_android: bool
pub const is_ios: bool
pub const is_mobile: bool

pub const SIGINT: c_int = 2
pub const SIGTERM: c_int = 15
pub const SIGHUP: c_int = 1
pub const SIGQUIT: c_int = 3
pub const SIGKILL: c_int = 9
pub const SIGUSR1: c_int = 10
pub const SIGUSR2: c_int = 12
```

#### Types

```zig
pub const Arch = enum {
    x86_64,
    aarch64,
    arm,
    riscv64,
    other,
};

pub const OSType = enum {
    linux,
    macos,
    windows,
    other,
};
```

#### Functions

```zig
// Platform detection
pub fn getArch() Arch
pub fn getOSType() OSType
pub fn getPlatformInfo() []const u8  // e.g., "linux-x86_64"

// Memory allocator
pub fn initAllocator() void
pub var allocator: std.mem.Allocator
pub fn alignedAllocator() std.mem.Allocator
pub fn reportLeaks() bool
```

#### Re-exports

Error mapping types and functions are re-exported from errors.zig:

```zig
pub usingnamespace errors;
```

#### Alignment Requirements

On macOS x86_64, `std.atomic.Value(u64)` and HashMap require 16-byte alignment due to CMPXCHG16B instruction. Use `platform.alignedAllocator()` for containers with atomic operations.

### logger.zig

Logging wrapper around Zig's `std.log` with dynamic level control.

#### Level

```zig
pub const Level = enum(u8) {
    trace = 0,
    debug = 1,
    info = 2,
    warn = 3,
    err = 4,
    fatal = 5,
};
```

#### Initialization

```zig
// Initialize logger with default level (INFO)
pub fn init(level: Level) void

// Cleanup logger
pub fn shutdown() void

// Check if initialized
pub fn isInitialized() bool
```

#### Level Control

```zig
pub fn getLevel() Level
pub fn setLevel(level: Level) void

// Check if level is enabled
pub fn isTraceEnabled() bool
pub fn isDebugEnabled() bool
pub fn isInfoEnabled() bool
pub fn isWarnEnabled() bool
```

#### Logging

```zig
pub fn log(level: Level, comptime format: []const u8, args: anytype) void
pub fn trace(comptime format: []const u8, args: anytype) void
pub fn debug(comptime format: []const u8, args: anytype) void
pub fn info(comptime format: []const u8, args: anytype) void
pub fn warn(comptime format: []const u8, args: anytype) void
pub fn err(comptime format: []const u8, args: anytype) void
pub fn fatal(comptime format: []const u8, args: anytype) void
```

#### File Output

```zig
pub fn addFile(path: []const u8) !void
pub fn removeFile() void
```

#### Error Helper

```zig
pub const InternalError = struct {
    level: Level,
    msg: []const u8,
};

pub fn makeErr(msg: []const u8) InternalError
pub fn makeWarn(msg: []const u8) InternalError
```

### config.zig

Lock-free atomic configuration storage.

#### Constants

```zig
pub const MAX_CONFIG_ITEMS: usize = 256
pub const MAX_STRING_SIZE: usize = 256
```

#### Config Type

```zig
pub const Config = struct {
    // Initialize config table
    pub fn init() Config

    // Bool operations (atomic)
    pub fn setBool(self: *Self, key: u8, value: bool) void
    pub fn getBool(self: *const Self, key: u8) bool

    // Integer operations (atomic)
    pub fn setInt(self: *Self, key: u8, value: u64) void
    pub fn getInt(self: *const Self, key: u8) u64

    // String operations (atomic length)
    pub fn setString(self: *Self, key: u8, value: []const u8) void
    pub fn getString(self: *const Self, key: u8) []const u8

    // Version management (atomic)
    pub fn getVersion(self: *const Self) u64
};
```

#### Global Singleton

```zig
pub fn initialize() void
pub fn isInitialized() bool
pub fn get() *Config

pub fn setBool(key: u8, value: bool) void
pub fn getBool(key: u8) bool
pub fn setInt(key: u8, value: u64) void
pub fn getInt(key: u8) u64
pub fn setString(key: u8, value: []const u8) void
pub fn getString(key: u8) []const u8
pub fn getVersion() u64
```

### signal.zig

Cross-platform signal handling using self-pipe technique.

#### Constants

```zig
pub const SIGINT: c_int = 2
pub const SIGTERM: c_int = 15
```

#### Setup

```zig
pub fn setup(handler: ?SignalHandler) !void
pub fn setupDefault() !void
```

#### State Queries

```zig
pub fn isTriggered() bool
pub fn getCaughtSignal() c_int
pub fn getSignalFd() i32
pub fn shouldExit() bool
```

#### Control

```zig
pub fn clear() void
pub fn cleanup() void
pub fn waitForSignal() c_int
```

#### SignalHandler Type

```zig
pub const SignalHandler = *const fn (sig: c_int) callconv(.C) void
```

### app.zig

Application framework with lifecycle management.

#### AppInfo

```zig
pub const AppInfo = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
};
```

#### AppConfig

```zig
pub const AppConfig = struct {
    enable_signal: bool = true,
    enable_leak_detection: bool = true,
    default_log_level: logger.Level = .info,
};
```

#### Args Parser

```zig
pub const Args = struct {
    positional: std.ArrayListUnmanaged([]const u8),
    options: std.StringHashMapUnmanaged([]const u8),
    argc: usize,

    pub fn deinit(self: *Args, allocator: std.mem.Allocator) void
};

pub fn parseArgs(allocator: std.mem.Allocator, argc: usize, argv: [*:null]?[*:0]u8) !Args
pub fn getOption(args: *const Args, key: []const u8, default: []const u8) []const u8
pub fn hasOption(args: *const Args, key: []const u8) bool
pub fn getPositional(args: *const Args, index: usize) ?[]const u8
```

#### AppFramework

```zig
pub fn AppFramework(comptime T: type) type
```

Example usage:

```zig
const MyApp = app.AppFramework(struct {
    port: u16 = 8080,
}) {};

pub fn init_fn(state: *MyApp, args: *app.Args) !void {
    state.port = 8080;
}

pub fn run_fn(state: *MyApp) !void {
    logger.info("Running on port {}", .{state.port});
}

pub fn main() !void {
    var myapp = try MyApp.init(
        .{ .name = "MyApp", .version = "1.0.0", .description = "My application" },
        .{},
        init_fn,
    );
    defer myapp.deinit();

    try myapp.run(run_fn);
}
```

#### SimpleApp

```zig
pub const SimpleApp = struct {
    allocator: std.mem.Allocator,
    running: bool,
    config: AppConfig,

    pub fn init(app_config: AppConfig) !SimpleApp
    pub fn setupSignals(self: *SimpleApp) !void
    pub fn shouldExit(self: *SimpleApp) bool
    pub fn stop(self: *SimpleApp) void
    pub fn allocator(self: *SimpleApp) std.mem.Allocator
    pub fn deinit(self: *SimpleApp) void
};
```

#### Exit Codes

```zig
pub const ExitCode = enum(u8) {
    success = 0,
    general_error = 1,
    invalid_argument = 2,
    runtime_error = 3,
};

pub fn exit(code: ExitCode) noreturn
```

## Thread Safety

- **logger.zig**: Uses atomic operations for level changes
- **config.zig**: All operations use atomic load/store with monotonic memory order
- **signal.zig**: Uses atomic operations for signal state, mutex-free design

## Platform Notes

### macOS

- Aligned allocator uses 16-byte alignment for HashMap compatibility
- Signal handling uses POSIX pipes

### Linux

- Standard POSIX signal handling
- 8-byte alignment sufficient

### Windows

- ConsoleCtrlHandler for signal emulation
- socketpair() instead of pipe()

## Memory Alignment

**Critical**: On macOS x86_64, `std.atomic.Value(u64)` and HashMap require 16-byte alignment due to CMPXCHG16B instruction. Use `platform.alignedAllocator()` for containers with atomic operations.

```zig
// Correct: use aligned allocator
const alloc = platform.alignedAllocator();
var map = std.StringHashMap(u32).init(alloc);

// Also correct: global variables with explicit alignment
var g_atomic: std.atomic.Value(u64) align(16) = .init(0);
```

## Build Targets

The `build-all` target compiles static libraries for all supported platforms:

| Platform | Target | ABI |
|----------|--------|-----|
| Linux x86_64 | `x86_64-linux-gnu` | GNU |
| Linux ARM64 | `aarch64-linux-gnu` | GNU |
| macOS x86_64 | `x86_64-macos` | None |
| macOS ARM64 | `aarch64-macos` | None |
| Windows x86_64 | `x86_64-windows-gnu` | GNU |
| Windows ARM64 | `arm64-windows-gnu` | GNU |
| iOS ARM64 | `aarch64-ios` | None |
| iOS x86_64 Simulator | `x86_64-ios-sim` | None |
| Android ARM64 | `aarch64-linux-android` | Android |
| Android x86_64 Simulator | `x86_64-linux-android` | Android |

### Build Commands

```bash
# Build for all targets (outputs to zig-out/lib/)
zig build build-all

# Build for specific target
zig build -Dtarget=x86_64-linux-gnu

# Release build for specific target
zig build -Dtarget=aarch64-linux-gnu -Doptimize=ReleaseSafe
```

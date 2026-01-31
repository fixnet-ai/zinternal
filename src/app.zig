//! app.zig - Application Framework
//!
//! A foundational application framework that provides:
//! - Command-line argument parsing
//! - System signal capture and graceful shutdown
//! - Logging with configurable levels (via logger wrapper of std.log)
//! - GPA-aligned memory management and leak detection
//!
//! All applications should use this framework to reduce code duplication
//! and improve reliability.
//!
//! Usage:
//! ```zig
//! const app = @import("app");
//!
//! // Define application
//! const MyApp = app.AppFramework(struct {
//!     port: u16 = 8080,
//!     verbose: bool = false,
//! }) {};
//!
//! pub fn main() !void {
//!     var myapp = try MyApp.init("MyApp", .{});
//!     defer myapp.deinit();
//!
//!     // Run application
//!     try myapp.run();
//! }
//! ```
//!

const std = @import("std");
const builtin = @import("builtin");
const platform = @import("platform");
const logger = @import("logger");
const signal = @import("signal");
const config = @import("config");

// ==================== App Info ====================

/// Application information
pub const AppInfo = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
};

// ==================== Argument Parser ====================

/// Simple argument parser result
pub const Args = struct {
    /// Parsed positional arguments
    positional: std.ArrayListUnmanaged([]const u8) = .{},

    /// Parsed options (--key value or --flag)
    options: std.StringHashMapUnmanaged([]const u8) = .{},

    /// Raw argument count
    argc: usize = 0,

    /// Free function
    pub fn deinit(self: *Args, allocator: std.mem.Allocator) void {
        for (self.positional.items) |arg| {
            allocator.free(arg);
        }
        self.positional.deinit(allocator);

        var it = self.options.valueIterator();
        while (it.next()) |value| {
            allocator.free(value.*);
        }
        self.options.deinit(allocator);
    }
};

/// Parse command-line arguments
pub fn parseArgs(allocator: std.mem.Allocator, argc: usize, argv: [*:null]?[*:0]u8) !Args {
    var args: Args = .{};

    var i: usize = 1; // Skip program name
    while (i < argc) : (i += 1) {
        const arg = std.mem.span(argv[i] orelse break);

        if (arg.len > 2 and arg[0] == '-' and arg[1] == '-') {
            // Option
            const key = arg[2..];

            // Check if next argument is value (not starting with --)
            if (i + 1 < argc) {
                const next_arg = std.mem.span(argv[i + 1] orelse break);
                if (next_arg.len == 0 or (next_arg[0] != '-' or (next_arg.len > 1 and next_arg[1] != '-'))) {
                    // This is a key=value or --key value option
                    try args.options.put(allocator, try allocator.dupe(u8, key), try allocator.dupe(u8, next_arg));
                    i += 1;
                    continue;
                }
            }

            // Flag option (no value)
            try args.options.put(allocator, try allocator.dupe(u8, key), try allocator.dupe(u8, ""));
        } else {
            // Positional argument
            try args.positional.append(allocator, try allocator.dupe(u8, arg));
        }
    }

    args.argc = argc;
    return args;
}

/// Get option value, with default
pub fn getOption(args: *const Args, key: []const u8, default: []const u8) []const u8 {
    return args.options.get(key) orelse default;
}

/// Get bool option (true if present, regardless of value)
pub fn hasOption(args: *const Args, key: []const u8) bool {
    return args.options.contains(key);
}

/// Get positional argument at index
pub fn getPositional(args: *const Args, index: usize) ?[]const u8 {
    return if (index < args.positional.items.len) args.positional.items[index] else null;
}

// ==================== Help and Version ====================

/// Print help message
pub fn printHelp(info: AppInfo) void {
    const out = std.io.getStdOut().writer();
    out.print("{} v{}\n\n", .{ info.name, info.version }) catch {};
    out.print("{}\n\n", .{info.description}) catch {};
    out.print("Usage: {s} [OPTIONS]\n\n", .{info.name}) catch {};
    out.print("Options:\n", .{}) catch {};
    out.print("  -h, --help     Show this help message\n", .{}) catch {};
    out.print("  -v, --version  Show version information\n", .{}) catch {};
    out.print("  -l, --level    Log level (trace, debug, info, warn, err, fatal)\n", .{}) catch {};
    out.print("  --verbose      Enable verbose output (same as -l debug)\n", .{}) catch {};
}

/// Print version information
pub fn printVersion(info: AppInfo) void {
    std.io.getStdOut().print("{} v{}\n", .{ info.name, info.version }) catch {};
}

// ==================== App Framework ====================

/// Application framework configuration
pub const AppConfig = struct {
    /// Enable signal handling (SIGINT/SIGTERM)
    enable_signal: bool = true,

    /// Enable memory leak detection (Debug mode only)
    enable_leak_detection: bool = true,

    /// Default log level
    default_log_level: logger.Level = .info,
};

/// Application framework state
pub fn AppFramework(comptime T: type) type {
    return struct {
        const Self = @This();

        /// User-defined application state
        state: T,

        /// Command-line arguments
        args: Args,

        /// Configuration
        config: AppConfig,

        /// Initialization
        pub fn init(info: AppInfo, app_config: AppConfig, init_fn: *const fn (*T, *Args) anyerror!void) !Self {
            var self: Self = undefined;

            // Initialize allocator
            platform.initAllocator();

            // Initialize config system (no-op if already initialized)
            config.initialize();

            // Initialize logging
            logger.init(app_config.default_log_level);

            // Parse arguments
            const allocator = platform.allocator;
            self.args = try parseArgs(allocator, std.os.argv.len, std.os.argv.ptr);

            // Handle help/version flags
            if (hasOption(&self.args, "help") or hasOption(&self.args, "h")) {
                printHelp(info);
                std.process.exit(0);
            }
            if (hasOption(&self.args, "version") or hasOption(&self.args, "v")) {
                printVersion(info);
                std.process.exit(0);
            }

            // Set log level from arguments
            if (hasOption(&self.args, "verbose")) {
                logger.setLevel(.debug);
            }
            if (getOption(&self.args, "level", "").len > 0) {
                const level_str = getOption(&self.args, "level", "info");
                const level = parseLogLevel(level_str);
                logger.setLevel(level);
            }

            // Setup signal handler if enabled
            if (app_config.enable_signal) {
                signal.setupDefault() catch {
                    logger.warn("Failed to setup signal handler", .{});
                };
            }

            // Initialize user state
            try init_fn(&self.state, &self.args);

            self.config = app_config;
            return self;
        }

        /// Run the application main loop
        pub fn run(self: *Self, run_fn: *const fn (*T) anyerror!void) !void {
            // Log startup
            logger.info("Application started", .{});
            logger.debug("Platform: {s}", .{platform.getPlatformInfo()});

            // Run user main function
            try run_fn(&self.state);
        }

        /// Wait for shutdown signal
        pub fn waitForShutdown(self: *Self) void {
            _ = self;
            signal.waitForSignal();
        }

        /// Check if should shutdown
        pub fn shouldExit(self: *Self) bool {
            _ = self;
            return signal.shouldExit();
        }

        /// Cleanup and exit
        pub fn deinit(self: *Self) void {
            const allocator = platform.allocator;

            // Log shutdown
            logger.info("Application shutting down", .{});

            // Cleanup signals
            signal.cleanup();

            // Cleanup arguments
            self.args.deinit(allocator);

            // Cleanup logging
            logger.shutdown();

            // Report memory leaks
            if (self.config.enable_leak_detection) {
                const leaked = platform.reportLeaks();
                if (!leaked) {
                    std.debug.print("[WARNING] Memory leaks detected\n", .{});
                }
            }
        }

        /// Get log level from string
        fn parseLogLevel(s: []const u8) logger.Level {
            if (std.ascii.eqlIgnoreCase(s, "trace")) return .trace;
            if (std.ascii.eqlIgnoreCase(s, "debug")) return .debug;
            if (std.ascii.eqlIgnoreCase(s, "info")) return .info;
            if (std.ascii.eqlIgnoreCase(s, "warn")) return .warn;
            // Note: "error" is a Zig keyword, so we use "err" for error level
            if (std.ascii.eqlIgnoreCase(s, "err")) return .err;
            if (std.ascii.eqlIgnoreCase(s, "fatal")) return .fatal;
            return .info;
        }
    };
}

// ==================== Simple App Builder ====================

/// Simple application builder for common use cases
pub const SimpleApp = struct {
    allocator: std.mem.Allocator,
    running: bool = true,
    config: AppConfig,

    /// Initialize simple app
    pub fn init(app_config: AppConfig) !SimpleApp {
        platform.initAllocator();
        config.initialize();
        logger.init(app_config.default_log_level);

        return .{
            .allocator = platform.allocator,
            .running = true,
            .config = app_config,
        };
    }

    /// Initialize with name
    pub fn initNamed(comptime name: []const u8, app_config: AppConfig) !SimpleApp {
        _ = name;
        return init(app_config);
    }

    /// Setup signal handling
    pub fn setupSignals(self: *SimpleApp) !void {
        _ = self;
        try signal.setupDefault();
    }

    /// Check if should exit
    pub fn shouldExit(self: *SimpleApp) bool {
        _ = self;
        return signal.shouldExit();
    }

    /// Set running flag
    pub fn stop(self: *SimpleApp) void {
        self.running = false;
    }

    /// Get allocator
    pub fn allocator(self: *SimpleApp) std.mem.Allocator {
        return self.allocator;
    }

    /// Cleanup
    pub fn deinit(self: *SimpleApp) void {
        logger.info("Application stopped", .{});
        signal.cleanup();
        logger.shutdown();

        if (self.config.enable_leak_detection) {
            _ = platform.reportLeaks();
        }
    }
};

// ==================== Common Options ====================

/// Standard application options
pub const StandardOptions = struct {
    /// Help flag
    help: bool = false,

    /// Version flag
    version: bool = false,

    /// Verbose mode
    verbose: bool = false,

    /// Log level
    log_level: logger.Level = .info,

    /// Parse from Args
    pub fn fromArgs(args: *const Args) StandardOptions {
        return .{
            .help = hasOption(args, "help") or hasOption(args, "h"),
            .version = hasOption(args, "version") or hasOption(args, "v"),
            .verbose = hasOption(args, "verbose"),
            .log_level = if (hasOption(args, "verbose")) .debug else .info,
        };
    }
};

// ==================== Exit Codes ====================

/// Standard exit codes
pub const ExitCode = enum(u8) {
    success = 0,
    general_error = 1,
    invalid_argument = 2,
    runtime_error = 3,
};

/// Exit with code
pub fn exit(code: ExitCode) noreturn {
    std.process.exit(@intFromEnum(code));
}

// ==================== Compile-time Verification ====================

comptime {
    // Verify exit codes
    std.debug.assert(@intFromEnum(ExitCode.success) == 0);
    std.debug.assert(@intFromEnum(ExitCode.general_error) == 1);
    std.debug.assert(@intFromEnum(ExitCode.invalid_argument) == 2);
    std.debug.assert(@intFromEnum(ExitCode.runtime_error) == 3);
}

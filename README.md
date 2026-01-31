# zinternal

A pure Zig library providing cross-platform utilities for applications.

## Features

- **Platform Abstraction** - OS/arch detection, aligned memory allocator
- **Error Mapping** - Cross-platform errno translation (POSIX/Windows)
- **Logging** - Dynamic log level control with optional file output
- **Configuration** - Lock-free atomic configuration storage
- **Signal Handling** - Cross-platform SIGINT/SIGTERM handling
- **Application Framework** - Command-line parsing, lifecycle management

## Modules

| Module | Description |
|--------|-------------|
| `platform` | Platform/OS/arch detection, aligned allocator |
| `errors` | Error code mapping (POSIX/Windows errno) |
| `logger` | Dynamic log level, file output |
| `config` | Lock-free atomic configuration storage |
| `signal` | Signal handling (SIGINT/SIGTERM) |
| `app` | Application framework with lifecycle management |

## Quick Start

```zig
const std = @import("std");
const app = @import("app");
const logger = @import("logger");

pub fn main() !void {
    var myapp = try app.SimpleApp.init(.{});
    defer myapp.deinit();

    logger.info("Hello from zinternal!", .{});
    _ = myapp;
}
```

## Requirements

- Zig 0.13.0
- macOS, Linux, Windows, iOS, or Android

## Building

```bash
# Build and run unit tests (default)
zig build

# Run integration tests
zig build test

# Build all supported targets (no tests)
zig build all

# Cross-platform build
zig build -Dtarget=x86_64-linux-gnu
zig build -Dtarget=aarch64-macos
```

## Supported Targets

| Platform | Target |
|----------|--------|
| Linux x86_64 | `x86_64-linux-gnu` |
| Linux ARM64 | `aarch64-linux-gnu` |
| macOS x86_64 | `x86_64-macos` |
| macOS ARM64 | `aarch64-macos` |
| Windows x86_64 | `x86_64-windows-gnu` |
| Windows ARM64 | `arm64-windows-gnu` |
| iOS ARM64 | `aarch64-ios` |
| iOS x86_64 Simulator | `x86_64-ios-sim` |
| Android ARM64 | `aarch64-linux-android` |
| Android x86_64 | `x86_64-linux-android` |

## Documentation

- [DESIGN.md](DESIGN.md) - Architecture and API reference
- [build_tools/README.md](build_tools/README.md) - Build system specification

## License

MIT

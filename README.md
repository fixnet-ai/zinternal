# zinternal

A pure Zig library providing cross-platform utilities for applications.

## Features

- **Platform Abstraction** - OS detection, architecture detection, aligned memory allocator
- **Logging** - Dynamic log level control with optional file output (wraps std.log)
- **Configuration** - Lock-free atomic configuration storage for bool/u64/string
- **Signal Handling** - Cross-platform SIGINT/SIGTERM handling with self-pipe technique
- **Application Framework** - Command-line parsing, lifecycle management

## Modules

| Module | Description |
|--------|-------------|
| `platform` | Platform detection, aligned allocator, errno mapping |
| `logger` | Dynamic log level, std.log wrapper, file output |
| `config` | Lock-free atomic configuration storage |
| `signal` | Signal handling (SIGINT/SIGTERM) |
| `app` | Application framework with lifecycle management |

## Quick Start

```zig
const app = @import("app");
const logger = @import("logger");

const MyApp = app.AppFramework(struct {
    port: u16 = 8080,
}) {};

pub fn main() !void {
    var myapp = try MyApp.init("MyApp", .{}, init_fn);
    defer myapp.deinit();

    logger.info("Server started on port {}", .{myapp.state.port});
    try myapp.run();
}
```

## Requirements

- Zig 0.13.0
- macOS, Linux, Windows, iOS, or Android

## Building

```bash
# Build and run tests
zig build

# Run integration tests
zig build test

# Cross-platform build
zig build -Dtarget=x86_64-linux-gnu
zig build -Dtarget=aarch64-linux-gnu
```

## Documentation

- [DESIGN.md](DESIGN.md) - Architecture and API reference
- [BUILD.md](BUILD.md) - Build instructions for all platforms

## License

MIT

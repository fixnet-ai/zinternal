# Build Instructions

## Requirements

- **Zig**: 0.13.0
- **Platforms**: macOS, Linux, Windows, iOS, Android

## Quick Start

```bash
# Install Zig 0.13.0 (if needed)
# macOS: brew install zig@0.13
# Linux: Download from ziglang.org
# Windows: Download from ziglang.org

# Build and run unit tests (default)
zig build

# Run integration tests
zig build test

# Build all supported targets
zig build build-all

# Release build
zig build -Doptimize=ReleaseSafe
```

## Build Options

### Standard Options

```bash
# Debug build (default)
zig build -Doptimize=Debug

# Release build
zig build -Doptimize=ReleaseSafe

# Minimum size release
zig build -Doptimize=ReleaseSmall
```

### Target Options

```bash
# Native build (current platform)
zig build

# Cross-compilation
zig build -Dtarget=x86_64-linux-gnu
zig build -Dtarget=aarch64-linux-gnu
zig build -Dtarget=x86_64-windows-gnu
zig build -Dtarget=aarch64-macos
zig build -Dtarget=aarch64-ios
```

### Target Triplets

| Platform | Target | ABI |
|----------|--------|-----|
| macOS x86_64 | `x86_64-macos` | None |
| macOS ARM64 | `aarch64-macos` | None |
| Linux x86_64 | `x86_64-linux-gnu` | GNU |
| Linux ARM64 | `aarch64-linux-gnu` | GNU |
| Windows x86_64 | `x86_64-windows-gnu` | GNU |
| Windows ARM64 | `arm64-windows-gnu` | GNU |
| iOS ARM64 | `aarch64-ios` | None |
| iOS x86_64 Simulator | `x86_64-ios-sim` | None |
| Android ARM64 | `aarch64-linux-android` | Android |
| Android x86_64 Simulator | `x86_64-linux-android` | Android |

## Directory Structure

```
zinternal/
├── src/                    # Source code
│   ├── platform.zig       # Platform abstraction
│   ├── errors.zig         # Error code mapping
│   ├── logger.zig         # Logging
│   ├── config.zig         # Configuration
│   ├── signal.zig         # Signal handling
│   └── app.zig            # Application framework
├── tests/
│   ├── test_unit.zig      # Unit tests (zig test)
│   ├── test_runner.zig    # Integration tests (executable)
│   └── test_framework.zig # Shared test utilities
├── scripts/               # Build scripts
├── build.zig             # Build script
├── build.zig.zon         # Build manifest
└── zig-out/              # Build output
```

## Build Commands

### Development Build

```bash
# Clean and build
rm -rf .zig-cache zig-out
zig build
```

### Testing

```bash
# Unit tests (default)
zig build

# Integration tests
zig build test

# Both
zig build && zig build test
```

### Release Build

```bash
# Release build
zig build -Doptimize=ReleaseSafe

# Output location
ls zig-out/bin/
```

### Cross-Compilation

#### Linux Targets

```bash
# x86_64 Linux
zig build -Dtarget=x86_64-linux-gnu

# ARM64 Linux
zig build -Dtarget=aarch64-linux-gnu

# ARM32 Linux
zig build -Dtarget=arm-linux-gnu
```

#### macOS Targets

```bash
# x86_64 macOS
zig build -Dtarget=x86_64-macos

# ARM64 macOS (Apple Silicon)
zig build -Dtarget=aarch64-macos

# Universal binary
zig build -Dtarget=x86_64-macos
cp zig-out/bin/zinternal zinternal-x86_64
zig build -Dtarget=aarch64-macos
cp zig-out/bin/zinternal zinternal-aarch64
lipo -create zinternal-x86_64 zinternal-aarch64 -output zinternal-macos
```

#### Windows Targets

```bash
# x86_64 Windows (MinGW)
zig build -Dtarget=x86_64-windows-gnu

# ARM64 Windows (MinGW)
zig build -Dtarget=arm64-windows-gnu
```

#### iOS Targets

```bash
# iOS ARM64
zig build -Dtarget=aarch64-ios

# iOS x86_64 Simulator
zig build -Dtarget=x86_64-ios-sim

# iOS ARM64 Simulator
zig build -Dtarget=aarch64-ios-sim
```

#### Android Targets

```bash
# Android ARM64
zig build -Dtarget=aarch64-linux-android

# Android x86_64 Simulator
zig build -Dtarget=x86_64-linux-android
```

## CI/CD Example

```yaml
# .github/workflows/build.yml
name: Build and Test

on: [push, pull_request]

jobs:
  build:
    strategy:
      matrix:
        platform:
          - x86_64-linux
          - x86_64-macos
          - aarch64-macos
          - x86_64-windows
    runs-on: ${{ matrix.platform }}
    steps:
      - uses: actions/checkout@v4
      - name: Setup Zig
        uses: crazy-max/ghaction-setup-zig@v2
        with:
          zig-version: 0.13.0
      - name: Build native
        run: zig build
      - name: Test
        run: zig build test
      - name: Build all targets
        run: zig build build-all
```

## Build Cache

Zig uses a build cache at `.zig-cache/`. To force a clean rebuild:

```bash
rm -rf .zig-cache zig-out
zig build
```

## Troubleshooting

### Missing Dependencies

Ensure Zig 0.13.0 is installed:

```bash
zig version
# Should output: 0.13.0
```

### macOS Code Signing

For iOS builds, code signing may be required:

```bash
# Development signing
zig build -Dtarget=aarch64-ios --code-signing-identity "-"
```

### Windows Notes

All Windows targets use GNU ABI (MinGW). MSVC is not supported.

### Executable Linking

**test_runner.zig** and any executable with `main()` must link libc:

```zig
const test_runner = b.addExecutable(.{
    .name = "zinternal_test",
    .root_source_file = b.path("tests/test_runner.zig"),
    .target = target,
    .optimize = optimize,
});
test_runner.linkLibC();  // Required for executables with main()
```

### Static Linking

For fully static binaries:

```bash
zig build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseSmall
```

## Code Standards

### Naming Conventions

- **Module names**: lowercase (e.g., `platform`, `logger`)
- **Public functions**: snake_case
- **Types**: PascalCase
- **Constants**: SCREAMING_SNAKE_CASE
- **Variables**: snake_case

### Alignment Requirements

**Critical**: On macOS x86_64, `std.atomic.Value(u64)` and HashMap require 16-byte alignment.

```zig
// Correct: use aligned allocator
const alloc = platform.alignedAllocator();
var map = std.StringHashMap(u32).init(alloc);

// Correct: explicit alignment for global variables
var g_counter: std.atomic.Value(u64) align(16) = .init(0);
```

### Error Handling

- Use `try` for errors that should propagate
- Use `catch` for errors that can be handled locally
- Use `error.SignalSetupFailed` style naming for custom errors

### Comment Style

```zig
// Single-line comment for implementation details
/// Doc comment for public API
```

### Import Style

```zig
const std = @import("std");
const platform = @import("platform");
const logger = @import("logger");
```

## Version Management

When making changes that affect the API:

1. Update `build.zig.zon` version if needed
2. Document changes in `CHANGELOG.md`
3. Update `DESIGN.md` if architecture changes

## Performance Notes

- Debug builds enable GPA memory leak detection
- Release builds use optimized memory allocation
- Aligned allocator adds minimal overhead (required for macOS x86_64)

## File Organization

```
src/
├── *.zig              # Public modules (no test blocks)
tests/
├── test_unit.zig      # Zig test{} blocks (no main)
├── test_runner.zig    # Executable with main()
docs/
├── DESIGN.md          # Architecture documentation
└── BUILD.md           # Build instructions
```

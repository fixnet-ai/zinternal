# zinternal Development Tasks

## Completed

### Core Modules
- [x] Create `platform.zig` - Platform abstraction (OS/arch detection, aligned allocator)
- [x] Create `errors.zig` - Cross-platform error code mapping (POSIX/Windows errno)
- [x] Create `logger.zig` - std.log wrapper with dynamic level control
- [x] Create `config.zig` - Lock-free atomic configuration storage
- [x] Create `signal.zig` - Cross-platform signal handling (SIGINT/SIGTERM)
- [x] Create `app.zig` - Application framework with lifecycle management

### Testing
- [x] Create `tests/test_unit.zig` - Unit tests for all modules
- [x] Create `tests/test_runner.zig` - Integration tests for App lifecycle
- [x] Create `tests/test_framework.zig` - Shared test utilities

### Build System
- [x] Update `build.zig` - Module configuration, test targets, build-all
- [x] Create `build.zig.zon` - Build manifest

### C Logger Library
- [x] Create `src/logger.h` - C logging header for external C projects
- [x] Create `src/logger.c` - Thread-safe C logging implementation with spinlock
- [x] Add `logger.c` to native build - Static library includes C code
- [x] Add `logger.c` to build-all targets - All platforms include C logging
- [x] Link libc for C compilation - Native and cross-compilation targets

### Documentation
- [x] Create `README.md` - Project overview and quick start
- [x] Create `DESIGN.md` - Architecture and API documentation
- [x] Create `BUILD.md` - Build instructions for all platforms

### Refactoring
- [x] Rename `xlog.zig` to `logger.zig` - std.log wrapper instead of custom implementation
- [x] Extract error mapping to `errors.zig` - Reduce platform.zig complexity

### Cross-Platform Support
- [x] Add `build-all` target for multi-platform builds
- [x] Windows x86_64 (gnu)
- [x] Windows ARM64 (gnu)
- [x] Linux x86_64 (gnu)
- [x] Linux ARM64 (gnu)
- [x] macOS x86_64
- [x] macOS ARM64
- [x] iOS ARM64
- [x] iOS x86_64 simulator
- [x] Android ARM64
- [x] Android x86_64 simulator

## Test Results

```
Unit Tests:      17/17 passed
Integration Tests: 8/8 passed
Build All:       10/10 targets passed
```

## Next Tasks

### Platform Support
- [ ] Test Linux build in Lima VM
- [ ] Test Windows build
- [ ] Test iOS/Android cross-compilation

### Performance
- [ ] Benchmark aligned allocator on macOS
- [ ] Profile memory usage with GPA

### Features
- [ ] Add logger format string escaping for user input
- [ ] Add config migration support between versions
- [ ] Add signal custom handler documentation

## Notes

- Zig 0.13.0 required
- macOS x86_64 requires 16-byte alignment for atomic operations
- Use `platform.alignedAllocator()` for HashMap and atomic containers
- All Windows targets use GNU ABI (MinGW)

# zinternal Development Tasks

## Completed

### Core Modules
- [x] Create `platform.zig` - Platform abstraction (OS/arch detection, aligned allocator, errno mapping)
- [x] Create `logger.zig` - std.log wrapper with dynamic level control
- [x] Create `config.zig` - Lock-free atomic configuration storage
- [x] Create `signal.zig` - Cross-platform signal handling (SIGINT/SIGTERM)
- [x] Create `app.zig` - Application framework with lifecycle management

### Testing
- [x] Create `tests/test_unit.zig` - Unit tests for all modules
- [x] Create `tests/test_runner.zig` - Integration tests for App lifecycle
- [x] Create `tests/test_framework.zig` - Shared test utilities

### Build System
- [x] Update `build.zig` - Module configuration and test targets
- [x] Create `build.zig.zon` - Build manifest

### Documentation
- [x] Create `README.md` - Project overview and quick start
- [x] Create `DESIGN.md` - Architecture and API documentation
- [x] Create `BUILD.md` - Build instructions for all platforms

### Refactoring
- [x] Rename `xlog.zig` to `logger.zig` - std.log wrapper instead of custom implementation
- [x] Update all module imports to use `logger` instead of `xlog`
- [x] Update `app.zig` to manage logger/config/signal lifecycle

## Test Results

```
Unit Tests:      17/17 passed
Integration Tests: 8/8 passed
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

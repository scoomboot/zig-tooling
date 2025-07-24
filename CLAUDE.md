# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Development Commands

### Build Commands
```bash
# Build all tools with ReleaseFast optimization (recommended)
zig build -Doptimize=ReleaseFast

# Build all tools in debug mode
zig build

# Install executables to zig-out/bin/
zig build install
```

### Run Commands
```bash
# Run individual tools directly
zig build run-memory -- [args]
zig build run-testing -- [args]
zig build run-logger -- [args]

# Or after installation
./zig-out/bin/memory_checker_cli [args]
./zig-out/bin/testing_compliance_cli [args]
./zig-out/bin/app_logger_cli [args]
```

### Configuration Commands
```bash
# Initialize configuration
memory_checker_cli config init

# Show current configuration
memory_checker_cli config show

# Validate configuration file
memory_checker_cli config validate .zigtools.json

# Use custom configuration
memory_checker_cli --config custom-config.json scan
testing_compliance_cli --config custom-config.json check
app_logger_cli --config custom-config.json stats
```

### Test Commands
```bash
# Run all tests
zig build test

# Run individual test files
zig test tests/test_memory_checker_cli.zig
zig test tests/test_testing_compliance_cli.zig
zig test tests/test_app_logger_cli.zig
zig test tests/test_scope_integration.zig
```

## Architecture Overview

This is a Zig tooling suite providing three main CLI tools for code quality analysis:

1. **Memory Checker** (`memory_checker_cli`) - Validates memory safety patterns including allocator usage, defer cleanup, and ownership transfers
2. **Testing Compliance** (`testing_compliance_cli`) - Enforces test naming conventions and validates test organization
3. **App Logger** (`app_logger_cli`) - Provides structured logging with auto-rotation and monitoring

### Core Components

- **Analyzers** (`src/analyzers/`) - Pattern-based analysis engines that perform the actual code checking
  - `memory_analyzer.zig` - Memory safety pattern detection
  - `testing_analyzer.zig` - Test compliance validation

- **Scope Tracking** (`src/core/scope_tracker.zig`) - Hierarchical scope tracking system that reduces false positives by understanding code context. This is a key differentiator that provides 47% false positive reduction.

- **Source Context** (`src/core/source_context.zig`) - Manages source file parsing and context for analysis

### Key Design Patterns

1. **Pattern-Based Detection**: All analyzers use regex patterns to identify code constructs
2. **Hierarchical Scope Tracking**: Maintains context awareness through nested scope analysis
3. **Modular CLI Design**: Each tool is a separate executable built on shared analyzer components
4. **Zero Dependencies**: Pure Zig implementation with no external dependencies

### Performance Considerations

- Always build with `-Doptimize=ReleaseFast` for production use (49-71x performance improvement)
- File processing is single-threaded but optimized for speed (~3.23ms per file for memory checking)
- Minor memory leak in single-file analysis mode is acceptable for CLI usage

### Testing Approach

- Tests use Zig's built-in testing framework
- Test naming convention: `test "unit: component: description"`
- All tests use test allocator for memory safety validation
- Helper functions in tests for file creation/deletion operations

## See Also

- [Configuration Guide](docs/configuration.md) - Complete configuration reference
- [User Guide](docs/user-guide/user-guide.md) - Comprehensive usage guide
- [README](README.md) - Quick start and overview
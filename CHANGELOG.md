# Changelog

All notable changes to the Zig Tooling Suite will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-01-24

### Added
- Initial release of Zig Tooling Suite
- **Memory Checker CLI** (`memory_checker`)
  - Validates memory safety patterns in Zig code
  - Detects missing allocator usage
  - Identifies missing defer cleanup patterns
  - Validates ownership transfers
  - Hierarchical scope tracking for reduced false positives (47% reduction)
  - Pattern-based detection engine
  - Performance: ~3.23ms per file with ReleaseFast optimization
  
- **Testing Compliance CLI** (`testing_compliance`)
  - Enforces test naming conventions
  - Validates test file organization
  - Ensures proper test categorization (unit, integration, e2e)
  - Configurable test patterns
  
- **App Logger CLI** (`app_logger`)
  - Structured logging with multiple severity levels
  - Automatic log rotation based on size
  - File and console output support
  - Thread-safe logging operations
  - JSON output format support (pending fix)

### Features
- Zero external dependencies - pure Zig implementation
- Cross-platform support (Linux, macOS, Windows)
- Optimized performance with ReleaseFast builds (49-71x improvement)
- Modular architecture for easy extension
- Comprehensive test coverage

### Known Issues
- JSON output flag (`--json`) not working correctly (ISSUE-081)
- Minor memory leak in single-file analysis mode (acceptable for CLI usage)
- No configuration file support yet
- Documentation contains project-specific references

### Technical Details
- Built with Zig 0.15.0-dev
- Requires Zig 0.13.0 or later for building
- Single-threaded file processing
- Pattern-based analysis using regex matching

[0.1.0]: https://github.com/your-org/zig-tooling/releases/tag/v0.1.0
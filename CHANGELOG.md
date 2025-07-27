# Changelog

All notable changes to the Zig Tooling Suite will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.4] - 2025-07-27

### Added
- **Enhanced Ownership Detection**: Added "get" function pattern to default ownership transfer patterns
  - Reduces false positives for getter functions that return owned memory
  - Improves analysis accuracy for common accessor patterns
- **Advanced Struct Field Detection**: Enhanced array element struct field assignment detection
  - Better handling of complex ownership transfer patterns in struct initialization
  - Improved recognition of indirect ownership transfers through data structures

### Fixed
- Improved ownership transfer detection for GitHub issue #2 patterns (getMigrationHistory example)
- Enhanced pattern matching for array-based data structure initialization

### Changed
- Updated project tracking documentation (ISSUES.md, READY.md)
- Expanded test coverage with LC072 test case replicating real-world usage patterns

### Tests
- Added comprehensive LC072 test case demonstrating getMigrationHistory ownership pattern
- Enhanced validation for struct field assignment scenarios
- Improved test coverage for edge cases in ownership detection

## [0.1.3] - 2025-07-27

### Added
- **Major Feature**: Comprehensive ownership transfer detection (LC068)
  - Configurable ownership patterns for custom allocator detection
  - Enhanced return type parsing for error unions, optionals, and complex types
  - Data flow analysis to track allocations returned later in functions
  - 8 comprehensive test cases covering various ownership scenarios
  - Default ownership patterns for common factory/builder functions
- **Infrastructure**: Comprehensive integration testing framework (LC020)
  - 6 integration test modules covering end-to-end workflows
  - 4 sample projects with different complexity levels
  - Build system integration testing
  - Memory performance validation and benchmarks
  - Thread safety and concurrent analysis validation
  - Error boundary and edge case testing

### Fixed
- Resolved false positive "missing defer" warnings for valid ownership transfers (addresses GitHub issue #2)
- Improved memory analyzer accuracy with scope-aware detection

### Changed
- Updated issue tracker organization and prioritization for v1.0 roadmap
- Enhanced documentation with ownership transfer configuration examples

## [0.1.2] - 2025-07-27

### Fixed
- **CRITICAL**: Fixed segfault in memory_analyzer.findFunctionContext when freeing return_type (LC057)
  - Root cause: String literals were being freed as heap allocations
  - Impact: Caused crashes during memory analysis in zig-db integration
  - Resolution: Ensured consistent heap allocation for all strings in parseFunctionSignature

### Added
- Regression test "LC057: Function context parsing memory safety"
- Improved memory management documentation
- Enhanced error handling with proper errdefer cleanup

## [0.1.1] - 2025-07-27

### Fixed
- **CRITICAL**: Fixed segfault in memory analyzer suggestion handling
- Improved memory safety in analyzer core functions

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

[0.1.3]: https://github.com/scoomboot/zig-tooling/releases/tag/v0.1.3
[0.1.2]: https://github.com/scoomboot/zig-tooling/releases/tag/v0.1.2
[0.1.1]: https://github.com/scoomboot/zig-tooling/releases/tag/v0.1.1
[0.1.0]: https://github.com/scoomboot/zig-tooling/releases/tag/v0.1.0
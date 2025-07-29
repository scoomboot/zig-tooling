# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Essential Commands

```bash
# Build the library
zig build

# Run all tests (unit tests only)
zig build test

# Run integration tests
zig build test-integration

# Run all tests including integration
zig build test-all

# Run a specific test file
zig test tests/test_patterns.zig --dep zig_tooling --mod zig_tooling::src/zig_tooling.zig

# Run code quality checks on current project
zig build quality

# Run quality checks on zig-tooling itself (non-blocking)
zig build dogfood

# Validate all tools compile
zig build validate-tools
```

## Project Architecture

### Core Library Structure
The project is a Zig static analysis library with the following key components:

1. **Main Entry Point** (`src/zig_tooling.zig`)
   - Re-exports all public APIs
   - Provides high-level `analyzeFile` and `analyzeProject` functions
   - Coordinates between different analyzers

2. **Core Analyzers**
   - `MemoryAnalyzer` (`src/memory_analyzer.zig`) - Detects missing defer statements, allocator mismatches, and ownership transfers
   - `TestingAnalyzer` (`src/testing_analyzer.zig`) - Validates test naming conventions and organization
   - `ScopeTracker` (`src/scope_tracker.zig`) - Provides scope-aware analysis with 47% false positive reduction

3. **High-Level API** (`src/patterns.zig`)
   - `checkProject()` - Analyzes entire projects with progress reporting
   - `checkFile()` - Quick single-file analysis
   - Provides sensible defaults and enhanced error handling

4. **Build Integration**
   - Library is exposed as a Zig module named "zig_tooling"
   - `tools/quality_check.zig` - Executable for CI/build integration
   - Supports `--check` (all/memory/tests), `--format` (text/json/github-actions), and `--no-fail-on-warnings` flags

### Key Design Patterns

1. **Allocator Management**: All functions accept an allocator as first parameter. Results must be freed using provided free functions.

2. **Configuration**: Optional `Config` struct allows customization of:
   - Allowed allocators and patterns
   - Test naming conventions
   - File/directory exclusions

3. **Error Handling**: Uses Zig error unions with custom `AnalysisError` type

4. **Issue Reporting**: Issues have severity (error/warning), type, message, and location info

### Testing Strategy

- Unit tests in `tests/` directory test individual components
- Integration tests in `tests/integration/` test real-world scenarios
- Sample projects in `tests/integration/sample_projects/` for testing against real code
- Tests use `@import("zig_tooling")` to access the library

### Common Development Patterns

1. **Adding New Analysis Rules**:
   - Add logic to appropriate analyzer (MemoryAnalyzer or TestingAnalyzer)
   - Add test cases to corresponding test file
   - Update patterns.zig if needed for high-level API

2. **Testing Changes**:
   - Unit test individual functions
   - Integration test with sample projects
   - Run `zig build dogfood` to test against own codebase

3. **Memory Safety**:
   - Always use defer for cleanup
   - Match allocators for alloc/free
   - Use arena allocators appropriately
   - Track ownership transfers in factory patterns
# Zig Tooling Library API Reference

This document provides a comprehensive reference for all public APIs in the zig-tooling library.

## Table of Contents

1. [Quick Start](#quick-start)
2. [Core APIs](#core-apis)
3. [Analyzers](#analyzers)
4. [Types and Configuration](#types-and-configuration)
5. [Utility Modules](#utility-modules)
6. [Advanced Usage](#advanced-usage)
7. [Memory Management](#memory-management)

## Quick Start

```zig
const zig_tooling = @import("zig_tooling");

// Simple file analysis
const result = try zig_tooling.analyzeFile(allocator, "src/main.zig", null);
defer allocator.free(result.issues);
defer for (result.issues) |issue| {
    allocator.free(issue.file_path);
    allocator.free(issue.message);
    if (issue.suggestion) |s| allocator.free(s);
};

// Check for errors
if (result.hasErrors()) {
    for (result.issues) |issue| {
        std.debug.print("{s}:{}:{}: {s}: {s}\n", .{
            issue.file_path,
            issue.line,
            issue.column,
            issue.severity.toString(),
            issue.message,
        });
    }
}
```

## Core APIs

### Main Entry Points

The main module (`zig_tooling`) provides high-level convenience functions for common analysis tasks.

#### `analyzeFile`

```zig
pub fn analyzeFile(allocator: std.mem.Allocator, path: []const u8, config: ?Config) AnalysisError!AnalysisResult
```

Analyzes a single file for both memory safety and test compliance issues.

**Parameters:**
- `allocator`: Allocator for result storage
- `path`: Path to the file to analyze
- `config`: Optional configuration (uses defaults if null)

**Returns:** `AnalysisResult` containing all detected issues

**Errors:**
- `FileNotFound`: The specified file does not exist
- `AccessDenied`: Cannot read the specified file
- `OutOfMemory`: Allocation failure
- `ParseError`: Source code parsing failed

#### `analyzeSource`

```zig
pub fn analyzeSource(allocator: std.mem.Allocator, source: []const u8, config: ?Config) AnalysisError!AnalysisResult
```

Analyzes source code directly without file I/O.

**Parameters:**
- `allocator`: Allocator for result storage
- `source`: Source code to analyze
- `config`: Optional configuration

**Returns:** `AnalysisResult` containing all detected issues

#### `analyzeMemory`

```zig
pub fn analyzeMemory(allocator: std.mem.Allocator, source: []const u8, file_path: []const u8, config: ?Config) AnalysisError!AnalysisResult
```

Performs memory safety analysis only.

**Parameters:**
- `allocator`: Allocator for result storage
- `source`: Source code to analyze
- `file_path`: Path for error reporting
- `config`: Optional configuration

#### `analyzeTests`

```zig
pub fn analyzeTests(allocator: std.mem.Allocator, source: []const u8, file_path: []const u8, config: ?Config) AnalysisError!AnalysisResult
```

Performs test compliance analysis only.

## Analyzers

### MemoryAnalyzer

The `MemoryAnalyzer` detects memory safety issues including leaks, missing defer statements, and allocator misuse.

```zig
var analyzer = MemoryAnalyzer.init(allocator);
defer analyzer.deinit();
try analyzer.analyzeSourceCode("example.zig", source);
const issues = analyzer.getIssues();
```

**Key Methods:**
- `init(allocator)`: Create with default configuration
- `initWithConfig(allocator, config)`: Create with custom memory configuration
- `initWithFullConfig(allocator, config)`: Create with full configuration including logging
- `analyzeSourceCode(file_path, source)`: Analyze source code
- `getIssues()`: Get all detected issues

### TestingAnalyzer

The `TestingAnalyzer` validates test organization, naming conventions, and structure.

```zig
var analyzer = TestingAnalyzer.init(allocator);
defer analyzer.deinit();
try analyzer.analyzeSourceCode("example_test.zig", source);
const issues = analyzer.getIssues();
```

**Key Methods:**
- `init(allocator)`: Create with default configuration
- `initWithConfig(allocator, config)`: Create with custom testing configuration
- `initWithFullConfig(allocator, config)`: Create with full configuration
- `getComplianceReport()`: Get detailed compliance statistics
- `getCategoryBreakdown(allocator)`: Get test counts by category

## Types and Configuration

### Issue

```zig
pub const Issue = struct {
    file_path: []const u8,
    line: u32,
    column: u32,
    issue_type: IssueType,
    severity: Severity,
    message: []const u8,
    suggestion: ?[]const u8 = null,
    code_snippet: ?[]const u8 = null,
};
```

Represents a single issue found during analysis.

### AnalysisResult

```zig
pub const AnalysisResult = struct {
    issues: []const Issue,
    files_analyzed: u32,
    issues_found: u32,
    analysis_time_ms: u64,
    
    pub fn hasErrors(self: AnalysisResult) bool
    pub fn hasWarnings(self: AnalysisResult) bool
};
```

Contains the complete results of an analysis operation.

### Config

```zig
pub const Config = struct {
    memory: MemoryConfig = .{},
    testing: TestingConfig = .{},
    patterns: PatternConfig = .{},
    options: AnalysisOptions = .{},
    logging: LoggingConfig = .{},
};
```

Main configuration structure for customizing analysis behavior.

### MemoryConfig

```zig
pub const MemoryConfig = struct {
    check_defer: bool = true,
    check_arena_usage: bool = true,
    check_allocator_usage: bool = true,
    check_ownership_transfer: bool = true,
    track_test_allocations: bool = true,
    allowed_allocators: []const []const u8 = &.{},
    allocator_patterns: []const AllocatorPattern = &.{},
};
```

Configuration options for memory safety analysis.

**Example:**
```zig
const config = Config{
    .memory = .{
        .check_defer = true,
        .allowed_allocators = &.{"std.heap.GeneralPurposeAllocator"},
        .allocator_patterns = &.{
            .{ .name = "MyAllocator", .pattern = "my_alloc" },
        },
    },
};
```

### TestingConfig

```zig
pub const TestingConfig = struct {
    enforce_categories: bool = true,
    enforce_naming: bool = true,
    enforce_test_files: bool = true,
    allowed_categories: []const []const u8 = &.{ "unit", "integration", "e2e", "performance", "stress" },
    test_file_suffix: []const u8 = "_test",
    test_directory: ?[]const u8 = null,
};
```

Configuration options for test compliance analysis.

### Severity Levels

```zig
pub const Severity = enum {
    err,      // Critical issues that should fail builds
    warning,  // Important issues that may need attention
    info,     // Informational notices
};
```

### Issue Types

```zig
pub const IssueType = enum {
    // Memory issues
    missing_defer,
    memory_leak,
    double_free,
    use_after_free,
    incorrect_allocator,
    arena_in_library,
    missing_errdefer,
    defer_in_loop,
    ownership_transfer,
    allocator_mismatch,
    
    // Testing issues
    missing_test_category,
    invalid_test_naming,
    test_outside_file,
    missing_test_file,
    orphaned_test,
    missing_source_file,
    source_without_tests,
    invalid_test_location,
    duplicate_test_name,
};
```

## Utility Modules

### patterns

High-level convenience functions for common analysis scenarios.

```zig
const patterns = zig_tooling.patterns;

// Analyze entire project
const result = try patterns.checkProject(allocator, ".", null, progressCallback);
defer patterns.freeProjectResult(allocator, result);

// Quick file check
const ok = try patterns.checkFile(allocator, "src/main.zig", null);

// Check source directly
const result = try patterns.checkSource(allocator, source_code, null);
defer patterns.freeResult(allocator, result);
```

**Progress Callback:**
```zig
fn progressCallback(files_processed: u32, total_files: u32, current_file: []const u8) void {
    std.debug.print("Analyzing {}/{}: {s}\n", .{ files_processed + 1, total_files, current_file });
}
```

### formatters

Result formatting utilities for different output formats.

```zig
const formatters = zig_tooling.formatters;

// Text output
const text = try formatters.formatAsText(allocator, result, .{ .color = true });
defer allocator.free(text);

// JSON output
const json = try formatters.formatAsJson(allocator, result, .{ .json_indent = 2 });
defer allocator.free(json);

// GitHub Actions format
const gh = try formatters.formatAsGitHubActions(allocator, result, .{});
defer allocator.free(gh);
```

### build_integration

Helper functions for integrating analysis into Zig build systems.

```zig
const build_integration = zig_tooling.build_integration;

// In build.zig
pub fn build(b: *std.Build) void {
    // Add memory check step
    const memory_check = build_integration.addMemoryCheckStep(b, .{
        .source_paths = &.{ "src/**/*.zig" },
        .fail_on_warnings = true,
    });
    
    // Add test compliance step
    const test_check = build_integration.addTestComplianceStep(b, .{
        .source_paths = &.{ "tests/**/*.zig" },
    });
    
    // Create quality check step
    const quality = b.step("quality", "Run code quality checks");
    quality.dependOn(&memory_check.step);
    quality.dependOn(&test_check.step);
}
```

### ScopeTracker

Advanced scope tracking for custom analyzers.

```zig
// Using the builder pattern
var tracker = ScopeTrackerBuilder.init(allocator)
    .withArenaTracking()
    .withDeferTracking()
    .withMaxDepth(20)
    .build();
defer tracker.deinit();

try tracker.analyzeSourceCode(source);
const scopes = tracker.getScopes();

// Find specific scopes
var functions = try tracker.findScopesByType(.function);
defer functions.deinit();

// Get scope hierarchy at a line
var hierarchy = try tracker.getScopeHierarchy(42);
defer hierarchy.deinit();
```

### Logging

Optional logging interface for debugging and monitoring.

```zig
const config = Config{
    .logging = .{
        .enabled = true,
        .callback = zig_tooling.stderrLogCallback,
        .min_level = .warn,
    },
};

// Custom log handler
fn myLogHandler(event: LogEvent) void {
    std.debug.print("[{s}] {s}: {s}\n", .{
        @tagName(event.level),
        event.category,
        event.message,
    });
}
```

## Advanced Usage

### Custom Allocator Patterns

```zig
const config = Config{
    .memory = .{
        .allowed_allocators = &.{ "MyPoolAllocator", "MyArenaAllocator" },
        .allocator_patterns = &.{
            .{ .name = "MyPoolAllocator", .pattern = "pool_alloc" },
            .{ .name = "MyArenaAllocator", .pattern = "arena" },
        },
    },
};
```

### Source Context Analysis

```zig
var context = zig_tooling.source_context.SourceContext.init(allocator);
defer context.deinit();
try context.analyzeSource(source_code);

// Check if position contains actual code
if (context.isPositionInCode(line, column)) {
    // Safe to analyze this as actual code
}

// Get context type
const ctx_type = context.getContextAtPosition(line, column);
```

## Memory Management

### Basic Pattern

Always free issues and their string fields:

```zig
const result = try zig_tooling.analyzeFile(allocator, "main.zig", null);
defer {
    for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    }
    allocator.free(result.issues);
}
```

### Pattern Helpers

The patterns module provides helper functions:

```zig
const result = try patterns.checkFile(allocator, "main.zig", null);
defer patterns.freeResult(allocator, result);

const project_result = try patterns.checkProject(allocator, ".", null);
defer patterns.freeProjectResult(allocator, project_result);
```

### HashMap Cleanup

Some methods return HashMaps that must be cleaned up:

```zig
var breakdown = try analyzer.getCategoryBreakdown(allocator);
defer breakdown.deinit();
```

## Error Handling

```zig
const result = zig_tooling.analyzeFile(allocator, "src/main.zig", null) catch |err| switch (err) {
    AnalysisError.FileNotFound => {
        std.debug.print("File not found\n", .{});
        return;
    },
    AnalysisError.AccessDenied => {
        std.debug.print("Permission denied\n", .{});
        return;
    },
    else => return err,
};
```

## Best Practices

1. **Always use defer for cleanup** - Ensure proper memory management
2. **Check hasErrors() before processing** - Quick way to determine if action is needed
3. **Use appropriate analyzers** - Use specific analyzers when you only need one type of analysis
4. **Configure for your project** - Customize allowed allocators and test categories
5. **Enable logging during development** - Helps debug analysis issues
6. **Use the patterns module** - Provides optimized defaults and better error handling
7. **Handle all error cases** - Especially file access errors in CI/CD environments

## Thread Safety

The analyzers and trackers are not thread-safe. Each thread should create its own instances. The configuration structures can be shared across threads as they are read-only during analysis.

## Performance Tips

1. **Use specific analyzers** - If you only need memory analysis, use `analyzeMemory` instead of `analyzeFile`
2. **Enable lazy parsing for large files** - Use ScopeTrackerBuilder with lazy parsing for files over 10k lines
3. **Limit analysis scope** - Use PatternConfig to exclude generated or vendor code
4. **Reuse analyzers** - Create once and analyze multiple files instead of creating new instances
5. **Use streaming for large projects** - Process files one at a time instead of loading all into memory

---

For more examples and use cases, see the [examples](../examples/) directory and [CLAUDE.md](../CLAUDE.md).
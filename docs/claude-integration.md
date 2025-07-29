# Configuration Guide

Complete configuration reference and advanced usage patterns for zig-tooling.

[← Back to Documentation Index](README.md) | [API Reference →](api-reference.md)

## Overview

Zig Tooling is a comprehensive code analysis library for Zig projects, providing:
- Memory safety analysis (allocation tracking, defer validation, ownership transfers)
- Testing compliance validation (naming conventions, test organization)
- Scope-aware analysis with 47% false positive reduction

## Installation and Integration

### Add to build.zig.zon
```zig
.dependencies = .{
    .zig_tooling = .{
        .url = "https://github.com/yourusername/zig-tooling/archive/refs/tags/v0.1.0.tar.gz",
        .hash = "...", // Use `zig fetch` to get the hash
    },
},
```

### Import in build.zig
```zig
const zig_tooling = b.dependency("zig_tooling", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zig_tooling", zig_tooling.module("zig_tooling"));
```

## API Quick Reference

### Main Entry Points
```zig
const zig_tooling = @import("zig_tooling");

// Analyze a file for both memory and testing issues
const result = try zig_tooling.analyzeFile(allocator, "src/main.zig", null);
defer allocator.free(result.issues);

// Analyze source code directly
const result = try zig_tooling.analyzeSource(allocator, source_code, null);

// Memory analysis only
const result = try zig_tooling.analyzeMemory(allocator, source, "file.zig", null);

// Testing compliance only
const result = try zig_tooling.analyzeTests(allocator, source, "test.zig", null);
```

### Types and Configuration
```zig
// Configure analysis
const config = zig_tooling.Config{
    .memory = .{
        .check_defer = true,
        .check_arena_usage = true,
        .check_allocator_usage = true,
        .allowed_allocators = &.{ "MyCustomAllocator", "PoolAllocator" },
        // Define custom allocator patterns for type detection
        .allocator_patterns = &.{
            .{ .name = "MyCustomAllocator", .pattern = "my_custom" },
            .{ .name = "PoolAllocator", .pattern = "pool" },
        },
    },
    .testing = .{
        .enforce_categories = true,
        .allowed_categories = &.{ "unit", "integration", "e2e" },
    },
};

// Check results
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

// Logging types
const Logger = zig_tooling.Logger;
const LogLevel = zig_tooling.LogLevel;
const LogEvent = zig_tooling.LogEvent;
const LogContext = zig_tooling.LogContext;
const LogCallback = zig_tooling.LogCallback;
const LoggingConfig = zig_tooling.LoggingConfig;
```

## Common Usage Patterns

### High-Level Convenience Functions

The library provides a patterns module for the most common analysis scenarios:

```zig
const zig_tooling = @import("zig_tooling");
const patterns = zig_tooling.patterns;

// Quick project analysis with progress reporting
pub fn checkMyProject() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Analyze entire project directory
    const result = try patterns.checkProject(allocator, ".", null, progressCallback);
    defer patterns.freeProjectResult(allocator, result);
    
    std.debug.print("Analyzed {} files in {}ms\n", .{ 
        result.files_analyzed, result.analysis_time_ms 
    });
    
    if (result.hasErrors()) {
        std.debug.print("Found {} errors and {} warnings\n", .{
            result.getErrorCount(), result.getWarningCount()
        });
        
        for (result.issues) |issue| {
            std.debug.print("{s}:{}:{}: {s}: {s}\n", .{
                issue.file_path, issue.line, issue.column,
                issue.severity.toString(), issue.message
            });
        }
        std.process.exit(1);
    }
}

fn progressCallback(files_processed: u32, total_files: u32, current_file: []const u8) void {
    std.debug.print("Analyzing {}/{}: {s}\n", .{ files_processed + 1, total_files, current_file });
}

// Quick file check with enhanced error handling
pub fn checkSingleFile(file_path: []const u8) !bool {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const result = try patterns.checkFile(allocator, file_path, null);
    defer patterns.freeResult(allocator, result);
    
    return !result.hasErrors();
}

// Analyze source code directly from memory
pub fn validateCodeSnippet(source: []const u8) !bool {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const result = try patterns.checkSource(allocator, source, null);
    defer patterns.freeResult(allocator, result);
    
    return !result.hasErrors();
}
```

#### Pattern Functions Overview

- **`checkProject(allocator, path, config, progress_callback)`**: Analyzes entire project directories
  - Automatic file discovery with configurable patterns
  - Progress reporting for large projects
  - Aggregated results across all files
  - Built-in handling of cache directories and build artifacts

- **`checkFile(allocator, file_path, config)`**: Analyzes single files
  - Enhanced error handling with descriptive messages
  - Uses optimized defaults for common scenarios
  - Wrapper around core `analyzeFile()` with better UX

- **`checkSource(allocator, source, config)`**: Analyzes source code from memory
  - No file I/O overhead
  - Ideal for editor integrations and live analysis
  - More lenient defaults suitable for code snippets

Each pattern function provides:
- Sensible default configurations optimized for common use cases
- Enhanced error handling with user-friendly messages
- Automatic memory management helpers (`freeResult()`, `freeProjectResult()`)
- Progress reporting for long-running operations

### Custom Allocator Detection
```zig
// Define custom allocator patterns for your project
const config = zig_tooling.Config{
    .memory = .{
        // Restrict to only allow specific allocators
        .allowed_allocators = &.{ "MyPoolAllocator", "MyArenaAllocator" },
        
        // Define patterns to detect your custom allocators
        .allocator_patterns = &.{
            // Pattern matches substring in allocator variable name
            .{ .name = "MyPoolAllocator", .pattern = "pool_alloc" },
            .{ .name = "MyArenaAllocator", .pattern = "my_arena" },
            // Multiple patterns can map to the same allocator type
            .{ .name = "MyArenaAllocator", .pattern = "custom_arena" },
        },
    },
};

// Example code that will be properly detected:
// var pool_alloc = MyPoolAllocator.init();
// const allocator = pool_alloc.allocator(); // Detected as "MyPoolAllocator"
// 
// var my_arena = CustomArenaAllocator.init();
// const arena_alloc = my_arena.allocator(); // Detected as "MyArenaAllocator"
```

### Pattern Conflict Resolution

The library provides several mechanisms to handle pattern conflicts:

```zig
// Disable all default patterns and use only custom patterns
const config = zig_tooling.Config{
    .memory = .{
        .use_default_patterns = false,  // Disable all built-in patterns
        .allocator_patterns = &.{
            .{ .name = "MyTestAllocator", .pattern = "std.testing.allocator" },
        },
    },
};

// Selectively disable specific default patterns
const config = zig_tooling.Config{
    .memory = .{
        // Disable specific built-in patterns that conflict with your project
        .disabled_default_patterns = &.{ "std.testing.allocator", "ArenaAllocator" },
        .allowed_allocators = &.{ "MyTestAllocator", "MyArena" },
        .allocator_patterns = &.{
            // These custom patterns will be used instead
            .{ .name = "MyTestAllocator", .pattern = "testing.allocator" },
            .{ .name = "MyArena", .pattern = "arena" },
        },
    },
};
```

#### Pattern Precedence Rules
1. **Custom patterns are checked first** - If a custom pattern matches, it takes precedence over built-in patterns
2. **Disabled patterns are skipped** - Patterns listed in `disabled_default_patterns` are not checked
3. **Built-in patterns are checked last** - Only if enabled and not disabled

#### Handling std.testing.allocator
The library includes built-in patterns for both `std.testing.allocator` and `testing.allocator`:
- Use `allowed_allocators = &.{ "std.testing.allocator", "testing.allocator" }` to allow both
- Use `disabled_default_patterns = &.{ "std.testing.allocator" }` to disable the built-in pattern
- Define custom patterns if you need different behavior for test allocators

### Memory Ownership Transfer Detection

The library automatically detects when functions transfer memory ownership to their callers, reducing false positive "missing defer" warnings. This is especially useful for factory functions, builders, and other patterns that allocate and return memory.

#### Default Ownership Transfer Patterns

The library recognizes common patterns that indicate ownership transfer:

**Function Name Patterns:**
- `create`, `init`, `make`, `new` - Factory/constructor functions
- `clone`, `duplicate`, `copy` - Functions that return owned copies
- `toString`, `toSlice`, `format` - String conversion functions
- `alloc` - Explicit allocation functions

**Return Type Patterns:**
- `[]u8`, `[]const u8` - Byte slices (often strings)
- `![]u8`, `![]const u8` - Error unions returning slices
- `?[]u8`, `?[]const u8` - Optional slices
- `*T`, `!*T`, `?*T` - Pointers (excluding function pointers)
- Complex types like `anyerror![]u8` are also supported

#### Configuring Custom Ownership Patterns

```zig
const config = zig_tooling.Config{
    .memory = .{
        // Add custom ownership transfer patterns
        .ownership_patterns = &.{
            // Match function names containing "get"
            .{ .function_pattern = "get", .description = "Getter functions" },
            
            // Match specific return types
            .{ .return_type_pattern = "!MyStruct", .description = "Factory returning MyStruct" },
            
            // Combine both patterns for more specific matching
            .{ 
                .function_pattern = "fetch",
                .return_type_pattern = "![]const u8",
                .description = "Fetch functions returning strings" 
            },
        },
        
        // Optionally disable default patterns
        .use_default_ownership_patterns = false,
    },
};
```

#### How It Works

The analyzer detects ownership transfer in several ways:

1. **Immediate Return**: `return try allocator.alloc(u8, 100);`
2. **Stored and Returned**: Variable allocated, processed, then returned
3. **Struct Initialization**: Allocated memory included in returned struct
4. **Error Handling**: Proper `errdefer` cleanup for error paths

#### Example: Ownership Transfer Patterns

```zig
// Detected as ownership transfer - no missing defer warning
pub fn createBuffer(allocator: std.mem.Allocator) ![]u8 {
    return try allocator.alloc(u8, 100);
}

// Also detected - allocation stored then returned
pub fn createAndInit(allocator: std.mem.Allocator) ![]u8 {
    const buffer = try allocator.alloc(u8, 100);
    errdefer allocator.free(buffer);  // Proper error handling
    
    // Initialize buffer...
    @memset(buffer, 0);
    
    return buffer;  // Ownership transferred to caller
}

// Struct pattern - allocated field in returned struct
pub fn createStruct(allocator: std.mem.Allocator) !MyStruct {
    const data = try allocator.alloc(u8, 100);
    errdefer allocator.free(data);
    
    return MyStruct{
        .data = data,  // Ownership transferred via struct
        .len = 100,
    };
}

// NOT ownership transfer - will warn about missing defer
pub fn processData(allocator: std.mem.Allocator) !void {
    const buffer = try allocator.alloc(u8, 100);
    // Missing defer - function doesn't return the allocation
    doSomething(buffer);
}
```

### Logging Integration
```zig
// Enable logging with a custom callback
const config = zig_tooling.Config{
    .memory = .{ .check_defer = true },
    .testing = .{ .enforce_categories = true },
    .logging = .{
        .enabled = true,
        .callback = myLogHandler,
        .min_level = .info,
    },
};

// Example log handler that writes to stderr
fn myLogHandler(event: zig_tooling.LogEvent) void {
    const stderr = std.io.getStdErr().writer();
    stderr.print("[{s}] {s}: {s}\n", .{
        @tagName(event.level),
        event.category,
        event.message,
    }) catch return;
}

// Or use the built-in stderr callback
const config_with_stderr = zig_tooling.Config{
    .logging = .{
        .enabled = true,
        .callback = zig_tooling.stderrLogCallback,
        .min_level = .warn, // Only log warnings and errors
    },
};

// Logging provides structured information about:
// - Analysis start/completion
// - Issues detected with context
// - Performance metrics (if implemented)
```

### Build System Integration

The library provides helper functions to integrate code quality checks directly into your build system using the `build_integration` module:

```zig
// In build.zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    // Add zig-tooling dependency (assumes you've added it to build.zig.zon)
    const zig_tooling_dep = b.dependency("zig_tooling", .{
        .target = target,
        .optimize = optimize,
    });
    
    // Your main executable
    const exe = b.addExecutable(.{
        .name = "my_app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zig_tooling", zig_tooling_dep.module("zig_tooling"));
    
    // Create a build script to run zig-tooling analysis
    const quality_check_exe = b.addExecutable(.{
        .name = "quality_check",
        .root_source_file = b.path("tools/quality_check.zig"),
        .target = target,
        .optimize = optimize,
    });
    quality_check_exe.root_module.addImport("zig_tooling", zig_tooling_dep.module("zig_tooling"));
    
    // Create quality check step
    const quality_step = b.step("quality", "Run all code quality checks");
    const run_quality = b.addRunArtifact(quality_check_exe);
    run_quality.addArgs(&.{"--memory", "--tests", "--fail-on-warnings"});
    quality_step.dependOn(&run_quality.step);
    
    // Install your executable
    b.installArtifact(exe);
}
```

And create `tools/quality_check.zig`:

```zig
// tools/quality_check.zig
const std = @import("std");
const zig_tooling = @import("zig_tooling");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    var run_memory = false;
    var run_tests = false;
    var fail_on_warnings = false;
    
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--memory")) run_memory = true;
        if (std.mem.eql(u8, arg, "--tests")) run_tests = true;
        if (std.mem.eql(u8, arg, "--fail-on-warnings")) fail_on_warnings = true;
    }
    
    var total_issues: u32 = 0;
    
    if (run_memory) {
        const memory_options = zig_tooling.build_integration.MemoryCheckOptions{
            .source_paths = &.{ "src/**/*.zig" },
            .fail_on_warnings = fail_on_warnings,
            .memory_config = .{
                .check_defer = true,
                .check_arena_usage = true,
                .allowed_allocators = &.{ "std.heap.GeneralPurposeAllocator" },
            },
        };
        
        // Note: This is a simplified example - in practice you'd need to implement
        // the pattern matching and analysis logic here
        std.debug.print("Running memory safety analysis...\n");
        // total_issues += runMemoryAnalysis(allocator, memory_options);
    }
    
    if (run_tests) {
        std.debug.print("Running test compliance analysis...\n");
        // total_issues += runTestAnalysis(allocator, test_options);
    }
    
    if (total_issues > 0) {
        std.debug.print("Found {d} issues.\n", .{total_issues});
        std.process.exit(1);
    } else {
        std.debug.print("All quality checks passed!\n");
    }
}
```

#### Build Integration Options

**Memory Check Options:**
```zig
const memory_check = zig_tooling.build_integration.addMemoryCheckStep(b, .{
    // Source patterns to analyze (supports basic glob patterns)
    .source_paths = &.{ "src/**/*.zig", "lib/**/*.zig" },
    
    // Exclude patterns
    .exclude_patterns = &.{ "**/zig-cache/**", "**/test_*.zig" },
    
    // Memory analysis configuration
    .memory_config = .{
        .check_defer = true,
        .check_arena_usage = true,
        .check_allocator_usage = true,
        .allowed_allocators = &.{ "std.heap.GeneralPurposeAllocator", "std.testing.allocator" },
    },
    
    // Build behavior
    .fail_on_warnings = true,
    .max_issues = 100,
    .continue_on_error = false,
    .output_format = .text, // .text, .json, .github_actions
    
    // Step configuration
    .step_name = "memory-check",
    .step_description = "Run memory safety analysis",
});
```

**Test Compliance Options:**
```zig
const test_check = zig_tooling.build_integration.addTestComplianceStep(b, .{
    .source_paths = &.{ "tests/**/*.zig" },
    .testing_config = .{
        .enforce_categories = true,
        .enforce_naming = true,
        .allowed_categories = &.{ "unit", "integration", "e2e", "performance" },
    },
    .fail_on_warnings = false,
    .output_format = .json,
});
```

#### Pre-commit Hook Generation

Generate pre-commit hooks to run analysis automatically:

```zig
// In a build step or utility script
const hook_script = try zig_tooling.build_integration.createPreCommitHook(allocator, .{
    .include_memory_checks = true,
    .include_test_compliance = true,
    .fail_on_warnings = true,
    .check_paths = &.{ "src/", "tests/" },
    .hook_type = .bash, // .bash, .fish, .powershell
});
defer allocator.free(hook_script);

// Install the hook
try std.fs.cwd().writeFile(".git/hooks/pre-commit", hook_script);

// Make it executable (Unix systems)
if (builtin.os.tag != .windows) {
    const file = try std.fs.cwd().openFile(".git/hooks/pre-commit", .{});
    defer file.close();
    try file.chmod(0o755);
}
```

#### CI/CD Integration

For GitHub Actions, use the github_actions output format:

```zig
// In your build.zig for CI
const ci_check = zig_tooling.build_integration.addMemoryCheckStep(b, .{
    .source_paths = &.{ "src/**/*.zig" },
    .fail_on_warnings = true,
    .output_format = .github_actions, // Formats output for GitHub annotations
    .step_name = "ci-quality-check",
});
```

This will output issues in GitHub Actions format that automatically annotate your PRs with found issues.

### Custom Analysis Tool
```zig
// tools/check.zig
const std = @import("std");
const zig_tooling = @import("zig_tooling");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    for (args[1..]) |file_path| {
        const result = try zig_tooling.analyzeFile(allocator, file_path, null);
        defer allocator.free(result.issues);
        defer for (result.issues) |issue| {
            allocator.free(issue.file_path);
            allocator.free(issue.message);
            if (issue.suggestion) |s| allocator.free(s);
        };
        
        if (result.hasErrors()) {
            std.process.exit(1);
        }
    }
}
```

### Result Formatting

The library provides comprehensive formatting capabilities for analysis results through the `formatters` module:

```zig
const zig_tooling = @import("zig_tooling");

// Basic usage - format as human-readable text
const result = try zig_tooling.analyzeMemory(allocator, source, "file.zig", null);
defer allocator.free(result.issues);
defer for (result.issues) |issue| {
    allocator.free(issue.file_path);
    allocator.free(issue.message);
    if (issue.suggestion) |s| allocator.free(s);
};

// Format as text for console output
const text_output = try zig_tooling.formatters.formatAsText(allocator, result, .{
    .color = true,
    .verbose = true,
});
defer allocator.free(text_output);

// Format as JSON for programmatic consumption
const json_output = try zig_tooling.formatters.formatAsJson(allocator, result, .{
    .json_indent = 2,
    .include_stats = true,
});
defer allocator.free(json_output);

// Format for GitHub Actions CI/CD
const gh_output = try zig_tooling.formatters.formatAsGitHubActions(allocator, result, .{
    .verbose = true,
});
defer allocator.free(gh_output);
```

#### Built-in Formatters

**Text Formatter** - Human-readable console output:
- Color support for errors, warnings, and info
- Verbose mode with code snippets and suggestions
- Issue count summaries and statistics
- Customizable output sections

**JSON Formatter** - Structured data output:
- Complete issue metadata
- Configurable indentation
- Proper JSON escaping for special characters
- Analysis statistics and timing information

**GitHub Actions Formatter** - CI/CD integration:
- Annotation format for inline PR comments
- Error/warning/notice workflow commands
- Summary statistics for build logs
- Truncation warnings for large result sets

#### Formatting Options

```zig
const options = zig_tooling.formatters.FormatOptions{
    .verbose = true,           // Include code snippets and suggestions
    .color = true,             // ANSI color codes for text output
    .max_issues = 100,         // Limit number of issues shown
    .include_stats = true,     // Show analysis statistics
    .json_indent = 4,          // JSON indentation size
};
```

#### Custom Formatters

Create your own formatters using the custom formatter interface:

```zig
fn myCustomFormatter(
    allocator: std.mem.Allocator,
    result: zig_tooling.AnalysisResult,
    options: zig_tooling.formatters.FormatOptions,
) ![]const u8 {
    return try std.fmt.allocPrint(allocator, 
        "CUSTOM: Found {} issues in {} files ({}ms)",
        .{ result.issues_found, result.files_analyzed, result.analysis_time_ms });
}

// Use the custom formatter
const formatter = zig_tooling.formatters.customFormatter(myCustomFormatter);
const output = try formatter.format(allocator, result, .{});
defer allocator.free(output);
```

#### Format Detection

Automatically detect formats based on file extensions:

```zig
const format = zig_tooling.formatters.detectFormat("output.json"); // Returns .json
const format = zig_tooling.formatters.detectFormat("report.txt");   // Returns .text
const format = zig_tooling.formatters.detectFormat("github-ci");    // Returns .github_actions
```

#### Integration with Analysis Options

The formatters work seamlessly with the new `AnalysisOptions` to control analysis behavior:

```zig
const config = zig_tooling.Config{
    .options = .{
        .max_issues = 50,           // Limit issues during analysis
        .verbose = true,            // Include extra details
        .continue_on_error = false, // Stop on first critical error
    },
};

const result = try zig_tooling.analyzeMemory(allocator, source, "file.zig", config);
// result.issues.len will be limited to 50 as configured

// Format with matching verbose setting
const output = try zig_tooling.formatters.formatAsText(allocator, result, .{
    .verbose = config.options.verbose, // Match analysis verbosity
    .max_issues = null,                 // Don't double-limit in formatter
});
defer allocator.free(output);
```

## Architecture Overview

### Public API Structure
- **Main Module** (`zig_tooling.zig`) - Entry point with convenience functions
- **Analyzers** - Core analysis engines (MemoryAnalyzer, TestingAnalyzer)
- **Types** (`types.zig`) - Common data structures (Issue, Config, AnalysisResult)
- **Utilities** - ScopeTracker for context-aware analysis

### Analysis Workflow
1. Source code is parsed into an AST-like structure
2. ScopeTracker builds a hierarchical scope model
3. Analyzers run pattern matching with scope awareness
4. Issues are collected with precise location information
5. Results are returned as structured data

### Key Design Patterns
1. **Pattern-Based Detection**: Regex patterns identify code constructs
2. **Scope-Aware Analysis**: Reduces false positives by understanding context
3. **Modular Architecture**: Analyzers can be used independently
4. **Zero Dependencies**: Pure Zig implementation

### Performance Characteristics
- Memory analysis: ~3.23ms per file (ReleaseFast)
- Testing analysis: ~0.84ms per file (ReleaseFast)
- Linear scaling with file size
- Minimal memory overhead

## Testing with the Library

### Unit Tests
```zig
test "code passes memory safety checks" {
    const source = @embedFile("my_module.zig");
    const result = try zig_tooling.analyzeMemory(testing.allocator, source, "my_module.zig", null);
    defer testing.allocator.free(result.issues);
    // ... cleanup issues
    
    try testing.expect(!result.hasErrors());
}
```

### Integration Tests
```zig
test "integration: analyze entire module" {
    const files = [_][]const u8{ "src/main.zig", "src/utils.zig" };
    
    var total_issues: u32 = 0;
    for (files) |file| {
        const result = try zig_tooling.analyzeFile(allocator, file, null);
        defer allocator.free(result.issues);
        // ... cleanup
        total_issues += result.issues_found;
    }
    
    try testing.expect(total_issues == 0);
}
```

## Testing

### Running Tests

The library includes comprehensive test coverage across 4 test suites:

```bash
# Run all tests
zig build test

# Run specific test suites
zig test tests/test_api.zig
zig test tests/test_patterns.zig  
zig test tests/test_scope_integration.zig
zig test src/zig_tooling.zig  # Library unit tests
```

### Test Structure

- **`tests/test_api.zig`** - Comprehensive API tests (68+ test cases)
  - Public API functionality testing
  - Configuration validation
  - Edge cases (empty source, large files, deep nesting)
  - Error boundary testing (invalid paths, concurrent usage)
  - Performance benchmarks (target: <1000ms for large files)
  - Memory management and cleanup verification

- **`tests/test_patterns.zig`** - High-level patterns library tests
  - checkProject(), checkFile(), checkSource() functions
  - File discovery and filtering
  - Progress callback functionality
  - Temporary directory handling for integration tests

- **`tests/test_scope_integration.zig`** - Scope analysis integration tests  
  - ScopeTracker with MemoryAnalyzer integration
  - Performance baselines and measurements
  - Complex source code analysis scenarios

- **`src/zig_tooling.zig`** - Library unit tests
  - Core module functionality
  - Type exports and public interface

### Test Categories

Tests follow naming conventions:
- `unit: API: ...` - Public API functionality tests
- `unit: patterns: ...` - Patterns library tests  
- `integration: ...` - Cross-component integration tests
- `performance: ...` - Performance and benchmark tests
- `LC###: ...` - Issue-specific regression tests

### Writing Tests

When adding new functionality:

1. **API Tests**: Add to `tests/test_api.zig` for public API changes
2. **Edge Cases**: Include boundary conditions and error handling
3. **Memory Management**: Always test proper cleanup with defer statements
4. **Performance**: Add benchmarks for expensive operations
5. **Integration**: Test interactions between components

Example test pattern:
```zig
test "unit: API: your new feature" {
    const allocator = testing.allocator;
    
    const result = try zig_tooling.yourNewFunction(allocator, input, config);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    try testing.expect(/* your assertions */);
}
```

## Important Notes

- Always free the `result.issues` array and all string fields within issues
- Build with `-Doptimize=ReleaseFast` for production use (49-71x performance improvement)
- The library is thread-safe for read operations but not for configuration changes
- Pattern-based detection may have false positives - use configuration to tune
- All tests pass with Zig 0.14.1 - compatibility tested and maintained

## See Also

- [API Documentation](src/zig_tooling.zig) - Detailed API docs in source
- [Types Reference](src/types.zig) - Configuration and result types
- [README](README.md) - Project overview and quick start
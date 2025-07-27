# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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

## Important Notes

- Always free the `result.issues` array and all string fields within issues
- Build with `-Doptimize=ReleaseFast` for production use (49-71x performance improvement)
- The library is thread-safe for read operations but not for configuration changes
- Pattern-based detection may have false positives - use configuration to tune

## See Also

- [API Documentation](src/zig_tooling.zig) - Detailed API docs in source
- [Types Reference](src/types.zig) - Configuration and result types
- [README](README.md) - Project overview and quick start
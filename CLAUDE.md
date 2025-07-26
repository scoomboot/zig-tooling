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
```

## Common Usage Patterns

### Build System Integration
```zig
// In build.zig - add a code quality check step
const check_step = b.step("check", "Run code quality checks");

const check_exe = b.addExecutable(.{
    .name = "check_code",
    .root_source_file = b.path("tools/check.zig"),
});
check_exe.root_module.addImport("zig_tooling", zig_tooling.module("zig_tooling"));

const run_check = b.addRunArtifact(check_exe);
check_step.dependOn(&run_check.step);
```

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
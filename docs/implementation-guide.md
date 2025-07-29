# zig-tooling Implementation Guide

A complete step-by-step guide for integrating zig-tooling into your Zig project for automated memory safety analysis and testing compliance.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Quick Start (5 minutes)](#quick-start-5-minutes)
- [Standard Integration (15 minutes)](#standard-integration-15-minutes)
- [Configuration](#configuration)
- [Build System Integration](#build-system-integration)
- [CI/CD Setup](#cicd-setup)
- [Advanced Features](#advanced-features)
- [Migration Guide](#migration-guide)
- [Troubleshooting](#troubleshooting)

## Prerequisites

- Zig 0.14.1 or later
- Git (for fetching dependencies)
- Basic familiarity with Zig's build system

## Quick Start (5 minutes)

### Step 1: Add zig-tooling to Your Project

First, fetch the library using Zig's package manager:

```bash
zig fetch --save https://github.com/scoomboot/zig-tooling/archive/refs/tags/v0.1.5.tar.gz
```

This will add the dependency to your `build.zig.zon` file automatically with the correct hash.

### Step 2: Update Your build.zig

Add the following to your existing `build.zig`:

```zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    // Add zig-tooling dependency
    const zig_tooling_dep = b.dependency("zig_tooling", .{
        .target = target,
        .optimize = optimize,
    });
    
    // Your existing executable/library
    const exe = b.addExecutable(.{
        .name = "my_app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Import zig-tooling (only if you want to use it in your code)
    exe.root_module.addImport("zig_tooling", zig_tooling_dep.module("zig_tooling"));
    
    b.installArtifact(exe);
}
```

### Step 3: Run Your First Analysis

Create a simple test file `check.zig`:

```zig
const std = @import("std");
const zig_tooling = @import("zig_tooling");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Analyze your main source file
    const result = try zig_tooling.analyzeFile(allocator, "src/main.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    if (result.hasErrors()) {
        std.debug.print("Found {} issues!\n", .{result.issues_found});
        std.process.exit(1);
    }
    
    std.debug.print("All checks passed!\n", .{});
}
```

Run the analysis:

```bash
zig build-exe check.zig --deps zig_tooling --mod zig_tooling:zig_tooling:zig-out/lib/zig_tooling.zig
./check
```

## Standard Integration (15 minutes)

### Step 1: Create a Proper build.zig.zon

If you don't have one already, create `build.zig.zon`:

```zig
.{
    .name = "my_project",
    .version = "0.1.0",
    .minimum_zig_version = "0.14.1",
    
    .dependencies = .{
        .zig_tooling = .{
            .url = "https://github.com/scoomboot/zig-tooling/archive/refs/tags/v0.1.5.tar.gz",
            .hash = "1234...", // Use the hash from zig fetch
        },
    },
    
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
        "LICENSE",
        "README.md",
    },
}
```

### Step 2: Create a Quality Check Tool

Create `tools/quality_check.zig`:

```zig
const std = @import("std");
const zig_tooling = @import("zig_tooling");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Use the high-level patterns API for project-wide analysis
    const result = try zig_tooling.patterns.checkProject(
        allocator,
        ".",
        null,
        progressCallback,
    );
    defer zig_tooling.patterns.freeProjectResult(allocator, result);
    
    // Format and display results
    const output = try zig_tooling.formatters.formatAsText(allocator, result, .{
        .color = true,
        .verbose = true,
    });
    defer allocator.free(output);
    
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(output);
    
    if (result.hasErrors()) {
        std.process.exit(1);
    }
}

fn progressCallback(files_processed: u32, total_files: u32, current_file: []const u8) void {
    const stderr = std.io.getStdErr().writer();
    stderr.print("\rAnalyzing {}/{}: {s}", .{
        files_processed + 1,
        total_files,
        current_file,
    }) catch {};
}
```

### Step 3: Integrate Into Build System

Update your `build.zig`:

```zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    // === Your application ===
    const exe = b.addExecutable(.{
        .name = "my_app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Add zig-tooling dependency
    const zig_tooling_dep = b.dependency("zig_tooling", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zig_tooling", zig_tooling_dep.module("zig_tooling"));
    
    b.installArtifact(exe);
    
    // === Quality checks ===
    const quality_check = b.addExecutable(.{
        .name = "quality_check",
        .root_source_file = b.path("tools/quality_check.zig"),
        .target = target,
        .optimize = optimize,
    });
    quality_check.root_module.addImport("zig_tooling", zig_tooling_dep.module("zig_tooling"));
    
    // Add quality check step
    const quality_step = b.step("quality", "Run code quality checks");
    const run_quality = b.addRunArtifact(quality_check);
    quality_step.dependOn(&run_quality.step);
    
    // Make tests depend on quality checks
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(quality_step);
    
    const tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
```

Now you can run:

```bash
zig build quality  # Run quality checks
zig build test     # Run tests (after quality checks)
```

## Configuration

### Basic Configuration

Create a custom configuration for your project's needs:

```zig
const config = zig_tooling.Config{
    .memory = .{
        // Enable/disable specific checks
        .check_defer = true,
        .check_arena_usage = true,
        .check_allocator_usage = true,
        
        // Whitelist allowed allocators
        .allowed_allocators = &.{
            "std.heap.GeneralPurposeAllocator",
            "std.testing.allocator",
            "std.heap.ArenaAllocator",
        },
    },
    .testing = .{
        // Enforce test naming conventions
        .enforce_categories = true,
        .enforce_naming = true,
        
        // Define allowed test categories
        .allowed_categories = &.{ "unit", "integration", "e2e", "perf" },
    },
    .options = .{
        .max_issues = 100,
        .verbose = true,
        .continue_on_error = true,
    },
};
```

### Custom Allocator Patterns

If you use custom allocators, configure pattern detection:

```zig
const config = zig_tooling.Config{
    .memory = .{
        // Define patterns to detect your custom allocators
        .allocator_patterns = &.{
            .{ .name = "MyPoolAllocator", .pattern = "pool_alloc" },
            .{ .name = "MyArenaAllocator", .pattern = "my_arena" },
        },
        
        // Only allow your custom allocators
        .allowed_allocators = &.{ "MyPoolAllocator", "MyArenaAllocator" },
    },
};
```

### Ownership Transfer Patterns

Configure functions that transfer memory ownership:

```zig
const config = zig_tooling.Config{
    .memory = .{
        // Add custom ownership transfer patterns
        .ownership_patterns = &.{
            .{ .function_pattern = "create", .description = "Factory functions" },
            .{ .return_type_pattern = "!MyStruct", .description = "MyStruct factories" },
        },
    },
};
```

## Build System Integration

### Add Multiple Check Steps

```zig
// Memory checks only
const memory_step = b.step("check-memory", "Run memory safety checks");
const run_memory = b.addRunArtifact(quality_check);
run_memory.addArgs(&.{ "--mode", "memory" });
memory_step.dependOn(&run_memory.step);

// Test compliance only
const test_check_step = b.step("check-tests", "Run test compliance checks");
const run_test_check = b.addRunArtifact(quality_check);
run_test_check.addArgs(&.{ "--mode", "tests" });
test_check_step.dependOn(&run_test_check.step);

// CI-optimized output
const ci_step = b.step("ci", "Run checks for CI/CD");
const run_ci = b.addRunArtifact(quality_check);
run_ci.addArgs(&.{ "--format", "github-actions" });
ci_step.dependOn(&run_ci.step);
```

### Pre-commit Hook Installation

Add a step to install git hooks:

```zig
const hook_step = b.step("install-hooks", "Install git pre-commit hooks");
const hook_installer = b.addExecutable(.{
    .name = "hook_installer",
    .root_source_file = b.path("tools/install_hooks.zig"),
    .target = target,
    .optimize = optimize,
});
hook_installer.root_module.addImport("zig_tooling", zig_tooling_dep.module("zig_tooling"));
const run_hooks = b.addRunArtifact(hook_installer);
hook_step.dependOn(&run_hooks.step);
```

## CI/CD Setup

### GitHub Actions

Create `.github/workflows/quality.yml`:

```yaml
name: Code Quality

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  quality-check:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v4
    
    - uses: mlugg/setup-zig@v1
      with:
        version: 0.14.1
    
    - name: Run quality checks
      run: |
        zig build ci --summary all
```

### GitLab CI

Create `.gitlab-ci.yml`:

```yaml
quality:
  stage: test
  image: ziglang/zig:0.14.1
  script:
    - zig build ci --summary all
  artifacts:
    reports:
      junit: quality-report.xml
```

### Integration Tests in CI

zig-tooling includes comprehensive integration tests that validate the library's behavior under various conditions. When running in CI, these tests have specific resource requirements:

**Resource Limits**: Integration tests run with constrained resources to ensure consistent behavior:
- Memory: 4GB container limit (3GB available to tests)
- CPU: 2 cores
- Timeout: 30 minutes

**Environment Variables**: Configure test behavior with:
- `ZTOOL_TEST_MAX_MEMORY_MB`: Maximum memory for tests (default: 3072)
- `ZTOOL_TEST_MAX_THREADS`: Maximum concurrent threads (default: 4)

For detailed information about the integration test suite, including architecture, troubleshooting, and local development tips, see the [Integration Tests Guide](integration-tests.md).

## Advanced Features

### Custom Analysis Tool

Create specialized analysis for your project:

```zig
const std = @import("std");
const zig_tooling = @import("zig_tooling");

pub fn analyzeWithCustomRules(allocator: std.mem.Allocator, source: []const u8) !void {
    // Create custom analyzer configuration
    const config = zig_tooling.Config{
        .memory = .{
            // Disable default patterns that conflict with your project
            .disabled_default_patterns = &.{ "std.testing.allocator" },
            
            // Add project-specific patterns
            .allocator_patterns = &.{
                .{ .name = "MyTestAllocator", .pattern = "test_alloc" },
            },
            
            // Custom ownership rules
            .ownership_patterns = &.{
                .{ 
                    .function_pattern = "acquire",
                    .return_type_pattern = "!*Resource",
                    .description = "Resource acquisition" 
                },
            },
        },
    };
    
    const result = try zig_tooling.analyzeSource(allocator, source, config);
    defer allocator.free(result.issues);
    // ... handle results
}
```

### Integration Testing

Test your code passes zig-tooling checks:

```zig
test "code passes quality checks" {
    const source = @embedFile("my_module.zig");
    const result = try zig_tooling.analyzeSource(testing.allocator, source, null);
    defer testing.allocator.free(result.issues);
    defer for (result.issues) |issue| {
        testing.allocator.free(issue.file_path);
        testing.allocator.free(issue.message);
        if (issue.suggestion) |s| testing.allocator.free(s);
    };
    
    try testing.expect(!result.hasErrors());
}
```

### Performance Optimization

For large codebases:

```zig
// Build with optimization for faster analysis
// zig build -Doptimize=ReleaseFast quality

// Configure for performance
const config = zig_tooling.Config{
    .options = .{
        .max_issues = 50,  // Stop after 50 issues
        .continue_on_error = false,  // Stop on first critical error
    },
    .pattern_config = .{
        // Exclude generated files
        .exclude_patterns = &.{ 
            "**/zig-cache/**", 
            "**/zig-out/**",
            "**/*.generated.zig" 
        },
    },
};
```

## Migration Guide

### From Manual Memory Checking

Replace manual checks with automated analysis:

```zig
// Before: Manual checking in code review
pub fn oldFunction(allocator: std.mem.Allocator) !void {
    const data = try allocator.alloc(u8, 100);
    // Hope someone catches the missing defer in review
}

// After: Automated detection
// zig build quality
// Error: Missing defer for allocation at line 3
```

### Gradual Adoption

1. **Start with warnings only**:
   ```bash
   zig build quality || true  # Don't fail builds initially
   ```

2. **Fix critical issues first**:
   ```zig
   const config = zig_tooling.Config{
       .memory = .{
           .check_defer = true,  // Start with defer checks only
           .check_arena_usage = false,
           .check_allocator_usage = false,
       },
   };
   ```

3. **Gradually enable more checks**:
   - Week 1: Enable defer checks
   - Week 2: Add arena usage validation
   - Week 3: Add allocator usage checks
   - Week 4: Enable test compliance

### Team Adoption

1. **Document your configuration**:
   ```zig
   // project_quality_config.zig
   pub const quality_config = zig_tooling.Config{
       // Document why each setting is chosen
       .memory = .{
           .check_defer = true,  // Prevent memory leaks
           .allowed_allocators = &.{
               "std.heap.GeneralPurposeAllocator",  // Default allocator
               "ProjectArenaAllocator",  // Our custom arena
           },
       },
   };
   ```

2. **Create project-specific documentation**:
   - Which allocators are approved and why
   - How to handle false positives
   - Common patterns in your codebase

3. **Set up automated enforcement**:
   - Pre-commit hooks for local development
   - CI/CD checks for pull requests
   - Regular reports on code quality metrics

## Troubleshooting

### Common Issues

**Issue**: "Unknown allocator type detected"
```zig
// Solution: Add pattern for your allocator
.allocator_patterns = &.{
    .{ .name = "MyAllocator", .pattern = "my_alloc" },
},
```

**Issue**: "False positive on ownership transfer"
```zig
// Solution: Add ownership pattern
.ownership_patterns = &.{
    .{ .function_pattern = "buildThing", .description = "Builder pattern" },
},
```

**Issue**: "Performance too slow on large codebase"
```bash
# Solution: Use ReleaseFast optimization
zig build -Doptimize=ReleaseFast quality
```

**Issue**: "Too many warnings to fix at once"
```zig
// Solution: Limit and prioritize
.options = .{
    .max_issues = 20,  // Start with top 20
    .continue_on_error = true,  // See all issues
},
```

### Getting Help

1. Check the [API documentation](../src/zig_tooling.zig)
2. Review [example code](../examples/)
3. File issues at: https://github.com/scoomboot/zig-tooling/issues
4. Read the [Configuration Guide](claude-integration.md) for detailed configuration

### Debug Mode

Enable detailed logging to troubleshoot:

```zig
const config = zig_tooling.Config{
    .logging = .{
        .enabled = true,
        .callback = zig_tooling.stderrLogCallback,
        .min_level = .debug,
    },
};
```

## Next Steps

1. Run `zig build quality` on your project
2. Fix any critical issues found
3. Customize configuration for your needs
4. Set up CI/CD integration
5. Install pre-commit hooks for the team

Remember: Start simple, add complexity as needed. The default configuration works well for most projects!
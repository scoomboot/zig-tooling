# Getting Started with zig-tooling

Welcome! This guide will walk you through setting up zig-tooling in your project and running your first code analysis. By the end, you'll have automated memory safety checks integrated into your build process.

## Prerequisites

Before you begin, ensure you have:
- **Zig 0.14.1 or later** installed ([Download Zig](https://ziglang.org/download/))
- A Zig project with a `build.zig` file
- Basic familiarity with Zig's build system

## Step 1: Install zig-tooling

The easiest way to add zig-tooling to your project is using `zig fetch`:

```bash
zig fetch --save https://github.com/yourusername/zig-tooling/archive/refs/tags/v0.1.5.tar.gz
```

This command will:
1. Download the zig-tooling library
2. Add it to your `build.zig.zon` file automatically
3. Calculate and include the correct hash

### Alternative: Manual Installation

If you prefer manual setup or need a specific version:

1. Create or update your `build.zig.zon`:
```zig
.{
    .name = "my_project",
    .version = "0.1.0",
    .dependencies = .{
        .zig_tooling = .{
            .url = "https://github.com/yourusername/zig-tooling/archive/refs/tags/v0.1.5.tar.gz",
            .hash = "1220...", // Get this from zig fetch
        },
    },
}
```

## Step 2: Create Your First Quality Check

Create a new file `tools/check.zig`:

```zig
const std = @import("std");
const zig_tooling = @import("zig_tooling");

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Get command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    // Default to checking current directory
    const path = if (args.len > 1) args[1] else ".";
    
    // Analyze the project
    std.debug.print("Analyzing {s}...\n", .{path});
    const result = try zig_tooling.patterns.checkProject(
        allocator,
        path,
        null, // Use default configuration
        progressCallback,
    );
    defer zig_tooling.patterns.freeProjectResult(allocator, result);
    
    // Display results
    const output = try zig_tooling.formatters.formatAsText(allocator, result, .{
        .color = true,
        .verbose = false,
    });
    defer allocator.free(output);
    
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(output);
    
    // Exit with error code if issues found
    if (result.hasErrors()) {
        std.process.exit(1);
    }
}

fn progressCallback(files_processed: u32, total_files: u32, current_file: []const u8) void {
    std.debug.print("\r[{}/{}] Analyzing: {s}", .{
        files_processed + 1,
        total_files,
        current_file,
    });
}
```

## Step 3: Update Your build.zig

Add zig-tooling to your build configuration:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    // === Your existing application ===
    const exe = b.addExecutable(.{
        .name = "my_app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);
    
    // === Add zig-tooling ===
    const zig_tooling_dep = b.dependency("zig_tooling", .{
        .target = target,
        .optimize = optimize,
    });
    
    // Create quality check executable
    const check = b.addExecutable(.{
        .name = "check",
        .root_source_file = b.path("tools/check.zig"),
        .target = target,
        .optimize = optimize,
    });
    check.root_module.addImport("zig_tooling", zig_tooling_dep.module("zig_tooling"));
    
    // Add quality check step
    const quality_step = b.step("quality", "Run code quality checks");
    const run_check = b.addRunArtifact(check);
    quality_step.dependOn(&run_check.step);
    
    // Make tests depend on quality checks
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(quality_step); // Quality checks run before tests
}
```

## Step 4: Run Your First Analysis

Now you can analyze your code:

```bash
# Run quality checks on entire project
zig build quality

# Or build and run directly
zig build && ./zig-out/bin/check src/
```

## Understanding the Output

When zig-tooling finds issues, it provides detailed information:

```
src/main.zig:45:5: error: Missing defer for allocation
    const buffer = try allocator.alloc(u8, 1024);
    ^
    Suggestion: Add 'defer allocator.free(buffer);' after allocation

src/utils.zig:23:10: warning: Using non-allowed allocator 'std.heap.page_allocator'
    const allocator = std.heap.page_allocator;
    ^
    Suggestion: Use one of the allowed allocators: GeneralPurposeAllocator, ArenaAllocator

Found 1 error and 1 warning in 2 files (analyzed in 45ms)
```

### Issue Types

**Errors** (❌) - Critical issues that should be fixed:
- Missing `defer` statements for allocations
- Use-after-free patterns
- Double-free issues
- Memory leaks in non-transfer contexts

**Warnings** (⚠️) - Important but not critical:
- Using non-allowed allocators
- Inconsistent test naming
- Missing test categories
- Potential arena allocator misuse

**Info** (ℹ️) - Suggestions for improvement:
- Test organization recommendations
- Performance suggestions

## Step 5: Configure for Your Project

Create a custom configuration for your project's needs:

```zig
// In your check.zig or build configuration
const config = zig_tooling.Config{
    .memory = .{
        // Only allow specific allocators
        .allowed_allocators = &.{
            "std.heap.GeneralPurposeAllocator",
            "std.testing.allocator",
            "MyProjectAllocator",
        },
        
        // Define custom allocator patterns
        .allocator_patterns = &.{
            .{ .name = "MyProjectAllocator", .pattern = "project_alloc" },
        },
        
        // Configure checks
        .check_defer = true,
        .check_arena_usage = true,
    },
    .testing = .{
        // Define your test categories
        .allowed_categories = &.{ "unit", "integration", "benchmark" },
        .enforce_categories = true,
    },
};

// Use the custom config
const result = try zig_tooling.patterns.checkProject(allocator, ".", config, null);
```

## Common First-Time Issues

### "Unknown allocator type detected"

If you use custom allocators, configure pattern detection:

```zig
.allocator_patterns = &.{
    .{ .name = "MyAllocator", .pattern = "my_alloc" },
},
.allowed_allocators = &.{ "MyAllocator" },
```

### "Too many issues to fix"

Start with critical errors only:

```zig
.options = .{
    .max_issues = 10, // Limit to first 10 issues
},
```

Or focus on specific checks:

```zig
.memory = .{
    .check_defer = true,      // Start with just defer checks
    .check_arena_usage = false,
    .check_allocator_usage = false,
},
```

### Performance on Large Projects

For large codebases, build with optimization:

```bash
zig build -Doptimize=ReleaseFast quality
```

## Next Steps

Now that you have basic analysis working:

1. **Add to CI/CD** - See [CI/CD Setup Guide](implementation-guide.md#cicd-setup)
2. **Customize Rules** - See [Configuration Guide](claude-integration.md)
3. **Create Pre-commit Hooks** - See [Pre-commit Example](../examples/advanced/pre_commit_setup.zig)
4. **Explore Advanced Features** - See [User Guide](user-guide.md)

## Getting Help

- **Examples**: Check the [examples directory](../examples/) for common patterns
- **API Reference**: See the [API documentation](api-reference.md)
- **Issues**: Report problems at [GitHub Issues](https://github.com/yourusername/zig-tooling/issues)
- **Community**: Join the discussion in [GitHub Discussions](https://github.com/yourusername/zig-tooling/discussions)

---

**Congratulations!** You've successfully integrated zig-tooling into your project. Your code quality just leveled up! 🎉
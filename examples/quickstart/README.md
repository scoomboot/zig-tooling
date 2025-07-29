# Quickstart Example - zig-tooling

This is a complete, runnable example showing how to integrate zig-tooling into your Zig project. You can copy this entire directory as a starting point for your own project.

## 📁 What's Included

```
quickstart/
├── build.zig.zon          # Dependency configuration
├── build.zig              # Build system with quality steps
├── src/
│   └── main.zig          # Example code with issues to find
└── tools/
    └── quality_check.zig  # Configurable quality checker
```

- **build.zig.zon** - Shows how to add zig-tooling as a dependency
- **build.zig** - Complete build setup with multiple quality check targets
- **src/main.zig** - Example code demonstrating both correct patterns and detectable issues
- **tools/quality_check.zig** - Ready-to-use, customizable quality check tool

## 🚀 Getting Started

1. **Install the dependency** (if not already done):
   ```bash
   zig fetch --save https://github.com/yourusername/zig-tooling/archive/refs/tags/v0.1.5.tar.gz
   ```

2. **Run quality checks**:
   ```bash
   zig build quality
   ```

3. **Try other commands**:
   ```bash
   # Memory checks only
   zig build check-memory
   
   # Test compliance only  
   zig build check-tests
   
   # CI-friendly output
   zig build ci
   
   # Run tests (includes quality check)
   zig build test
   ```

## 📊 Expected Output

### Clean Code
When running on the default code:
```
Analyzing project: .
[1/1] Analyzing: src/main.zig
================================================================================
zig-tooling Analysis Report
================================================================================
Files analyzed: 1
Issues found: 0
Analysis time: 12ms

✅ All checks passed!
```

### With Issues
Uncomment the `problematicFunction` in `src/main.zig` to see:
```
Analyzing project: .
[1/1] Analyzing: src/main.zig
================================================================================
zig-tooling Analysis Report
================================================================================
src/main.zig:32:5: error: Missing defer for allocation
    const data = try allocator.alloc(u8, 1024);
    ^
    Suggestion: Add 'defer allocator.free(data);' after this allocation

src/main.zig:36:21: warning: Using non-allowed allocator 'std.heap.page_allocator'
    const allocator = std.heap.page_allocator;
                      ^
    Suggestion: Use one of: std.heap.GeneralPurposeAllocator, std.testing.allocator

Files analyzed: 1
Issues found: 2 (1 error, 1 warning)
Analysis time: 15ms

❌ Analysis failed with 1 error and 1 warning
```

## 🔧 Common Customizations

### 1. Configure Allowed Allocators

In `tools/quality_check.zig`, modify the configuration:

```zig
const config = zig_tooling.Config{
    .memory = .{
        .allowed_allocators = &.{
            "std.heap.GeneralPurposeAllocator",
            "std.testing.allocator",
            "MyCustomAllocator",  // Add your allocator
        },
    },
};
```

### 2. Add Custom Allocator Patterns

For custom allocator detection:

```zig
const config = zig_tooling.Config{
    .memory = .{
        .allocator_patterns = &.{
            .{ .name = "MyPoolAllocator", .pattern = "pool" },
            .{ .name = "ThreadSafeAlloc", .pattern = "thread_safe" },
        },
    },
};
```

### 3. Configure Test Categories

Customize allowed test categories:

```zig
const config = zig_tooling.Config{
    .testing = .{
        .allowed_categories = &.{ 
            "unit", 
            "integration", 
            "benchmark",     // Add custom categories
            "regression",
        },
    },
};
```

### 4. Add Ownership Transfer Patterns

For factory/builder patterns:

```zig
const config = zig_tooling.Config{
    .memory = .{
        .ownership_patterns = &.{
            .{ 
                .function_pattern = "createOwned",
                .description = "Our ownership convention" 
            },
        },
    },
};
```

### 5. Change Output Format

For CI/CD integration:

```zig
// In quality_check.zig, replace formatAsText with:

// For GitHub Actions
const output = try zig_tooling.formatters.formatAsGitHubActions(
    allocator, result, .{}
);

// For JSON output
const output = try zig_tooling.formatters.formatAsJson(
    allocator, result, .{ .json_indent = 2 }
);
```

### 6. Limit Issues for Gradual Adoption

Start with a manageable number:

```zig
const config = zig_tooling.Config{
    .options = .{
        .max_issues = 10,  // Show only first 10 issues
    },
};
```

## 🎯 Demonstrating Issues

The `src/main.zig` file includes a commented-out `problematicFunction` with intentional issues:

1. **Missing defer** - Allocation without cleanup
2. **Non-allowed allocator** - Using page_allocator directly
3. **Allocator mismatch** - Allocating with one, freeing with another

Uncomment different parts to see how zig-tooling catches various issues.

## 📝 Project Structure Tips

### For New Projects
1. Copy this entire directory
2. Rename in build.zig.zon
3. Customize quality_check.zig
4. Start coding!

### For Existing Projects
1. Copy `tools/quality_check.zig`
2. Add zig-tooling to your build.zig.zon
3. Add the build steps from build.zig
4. Run and fix issues incrementally

## 🔍 Exploring Further

### Understanding the Code

- **build.zig** - Shows how to create multiple build targets
- **quality_check.zig** - Demonstrates configuration and formatting options
- **main.zig** - Examples of both good and problematic patterns

### Advanced Features

Try these modifications:

1. **Add progress callback** - Already implemented, shows file progress
2. **Memory-only mode** - Use `zig build check-memory`
3. **CI mode** - Use `zig build ci` for GitHub Actions format
4. **Custom ignore patterns** - Add to PatternConfig in quality_check.zig

## 🚦 Next Steps

1. **Run the example** to see it in action
2. **Uncomment issues** to understand detection
3. **Customize configuration** for your needs
4. **Copy to your project** and integrate
5. **Add to CI/CD** using the ci target
6. **Read the guides**:
   - [Implementation Guide](../../docs/implementation-guide.md)
   - [User Guide](../../docs/user-guide.md)
   - [API Reference](../../docs/api-reference.md)

## 💡 Pro Tips

- Use `zig build -Doptimize=ReleaseFast quality` for faster analysis
- Start with warnings only (`|| true` in CI) for gradual adoption
- The progress callback helps with large projects
- Check the advanced examples for more sophisticated setups

---

**Questions?** Check the [main documentation](../../docs/) or file an issue!
# zig-tooling User Guide

This comprehensive guide covers all aspects of using zig-tooling in your projects, from basic configuration to advanced integration patterns.

## Table of Contents

1. [Configuration Deep Dive](#configuration-deep-dive)
2. [Memory Analysis](#memory-analysis)
3. [Testing Compliance](#testing-compliance)
4. [Custom Allocator Patterns](#custom-allocator-patterns)
5. [Ownership Transfer Patterns](#ownership-transfer-patterns)
6. [Build System Integration](#build-system-integration)
7. [CI/CD Integration](#cicd-integration)
8. [Performance Optimization](#performance-optimization)
9. [Team Adoption Strategies](#team-adoption-strategies)
10. [Troubleshooting](#troubleshooting)

## Configuration Deep Dive

### Configuration Structure

The main configuration struct provides fine-grained control over all aspects of analysis:

```zig
const config = zig_tooling.Config{
    .memory = MemoryConfig{...},      // Memory safety settings
    .testing = TestingConfig{...},     // Test compliance settings
    .patterns = PatternConfig{...},    // Pattern matching settings
    .options = AnalysisOptions{...},   // General analysis options
    .logging = LoggingConfig{...},     // Logging configuration
};
```

### Memory Configuration

Control memory safety analysis behavior:

```zig
.memory = .{
    // Core checks
    .check_defer = true,              // Detect missing defer statements
    .check_arena_usage = true,        // Validate arena allocator usage
    .check_allocator_usage = true,    // Check allowed allocators
    .check_ownership_transfer = true,  // Smart factory pattern detection
    
    // Test-specific
    .track_test_allocations = true,   // Track allocations in tests
    
    // Allowed allocators (empty = all allowed)
    .allowed_allocators = &.{
        "std.heap.GeneralPurposeAllocator",
        "std.heap.ArenaAllocator",
        "std.testing.allocator",
    },
    
    // Custom patterns
    .allocator_patterns = &.{},       // See Custom Allocator Patterns
    .ownership_patterns = &.{},       // See Ownership Transfer Patterns
    
    // Advanced options
    .use_default_patterns = true,     // Use built-in patterns
    .disabled_default_patterns = &.{}, // Disable specific defaults
};
```

### Testing Configuration

Enforce consistent testing practices:

```zig
.testing = .{
    // Naming and organization
    .enforce_categories = true,       // Require test categories
    .enforce_naming = true,           // Check naming conventions
    .enforce_test_files = true,       // Validate test file structure
    
    // Categories
    .allowed_categories = &.{
        "unit",        // Unit tests
        "integration", // Integration tests
        "e2e",         // End-to-end tests
        "performance", // Performance tests
        "stress",      // Stress tests
        "fuzz",        // Fuzz tests
    },
    
    // File organization
    .test_file_suffix = "_test",      // Expected test file suffix
    .test_directory = "tests",        // Optional test directory
};
```

### Analysis Options

Control analysis behavior:

```zig
.options = .{
    .max_issues = 100,               // Stop after N issues (0 = unlimited)
    .verbose = true,                 // Include detailed information
    .continue_on_error = true,       // Continue after critical errors
    .parallel = false,               // Parallel analysis (future)
};
```

### Logging Configuration

Configure logging output:

```zig
.logging = .{
    .enabled = true,
    .callback = myLogHandler,        // Custom log handler
    .min_level = .warn,              // Minimum log level
    
    // Or use built-in handlers
    .callback = zig_tooling.stderrLogCallback,
};
```

## Memory Analysis

### Understanding Memory Issues

zig-tooling detects several categories of memory issues:

#### Missing Defer
```zig
// ❌ Issue detected
const data = try allocator.alloc(u8, 100);
processData(data);
// Missing: defer allocator.free(data);

// ✅ Correct
const data = try allocator.alloc(u8, 100);
defer allocator.free(data);
processData(data);
```

#### Allocator Mismatches
```zig
// ❌ Issue detected
const data = try gpa.alloc(u8, 100);
defer arena.free(data); // Wrong allocator!

// ✅ Correct
const data = try gpa.alloc(u8, 100);
defer gpa.free(data);
```

#### Arena Allocator in Libraries
```zig
// ❌ Issue in library code
pub fn createThing(arena: *ArenaAllocator) !*Thing {
    // Libraries shouldn't force arena usage
    return try arena.create(Thing);
}

// ✅ Better library design
pub fn createThing(allocator: Allocator) !*Thing {
    return try allocator.create(Thing);
}
```

### Smart Ownership Detection

The library understands when functions transfer ownership:

```zig
// Recognized as ownership transfer - no missing defer warning
pub fn createBuffer(allocator: Allocator) ![]u8 {
    return try allocator.alloc(u8, 1024);
}

// Also recognized with error handling
pub fn createComplex(allocator: Allocator) !*Complex {
    const result = try allocator.create(Complex);
    errdefer allocator.destroy(result);
    
    result.data = try allocator.alloc(u8, 100);
    errdefer allocator.free(result.data);
    
    // Initialize...
    return result; // Ownership transferred
}
```

### Test Allocator Patterns

Special handling for test allocations:

```zig
test "example test" {
    // Recognized as test context
    const data = try testing.allocator.alloc(u8, 100);
    defer testing.allocator.free(data);
    
    // Test code...
}
```

## Testing Compliance

### Test Categories

Organize tests with clear categories:

```zig
test "unit: Parser: handles empty input" {
    // Unit test for Parser component
}

test "integration: Database: connects with auth" {
    // Integration test for database
}

test "e2e: API: full request cycle" {
    // End-to-end API test
}
```

### Test File Organization

```
project/
├── src/
│   ├── parser.zig
│   └── database.zig
└── tests/
    ├── parser_test.zig      // Tests for parser.zig
    └── database_test.zig    // Tests for database.zig
```

### Custom Test Categories

Define project-specific categories:

```zig
.testing = .{
    .allowed_categories = &.{
        "unit",
        "integration", 
        "benchmark",      // Performance benchmarks
        "property",       // Property-based tests
        "regression",     // Regression tests
    },
};
```

## Custom Allocator Patterns

### Basic Pattern Configuration

Define patterns to detect your custom allocators:

```zig
.allocator_patterns = &.{
    // Simple substring matching
    .{ .name = "MyPoolAllocator", .pattern = "pool" },
    
    // More specific patterns
    .{ .name = "ThreadSafeAllocator", .pattern = "thread_safe_alloc" },
    
    // Multiple patterns for same allocator
    .{ .name = "CustomAllocator", .pattern = "custom_alloc" },
    .{ .name = "CustomAllocator", .pattern = "my_allocator" },
};
```

### Pattern Matching Examples

```zig
// These will be detected based on patterns above:
var pool = MyPoolAllocator.init();          // Contains "pool"
const allocator = pool.allocator();         // Detected as MyPoolAllocator

var thread_safe_alloc = initThreadSafe();   // Contains "thread_safe_alloc"
const alloc = thread_safe_alloc.allocator(); // Detected as ThreadSafeAllocator
```

### Disabling Default Patterns

Override built-in pattern detection:

```zig
.memory = .{
    // Option 1: Disable all defaults
    .use_default_patterns = false,
    
    // Option 2: Disable specific patterns
    .disabled_default_patterns = &.{
        "std.testing.allocator",
        "ArenaAllocator",
    },
    
    // Your patterns
    .allocator_patterns = &.{
        .{ .name = "TestAllocator", .pattern = "test_alloc" },
    },
};
```

### Pattern Precedence

1. Custom patterns are checked first
2. Disabled patterns are skipped
3. Default patterns are checked last

## Ownership Transfer Patterns

### Built-in Patterns

The library recognizes common ownership transfer patterns:

**Function Name Patterns:**
- `create*`, `new*`, `init*` - Constructors
- `clone*`, `copy*`, `dup*` - Duplication
- `alloc*`, `make*` - Allocation
- `build*`, `get*` - Builders/getters
- `toString`, `format` - String conversion

**Return Type Patterns:**
- `[]u8`, `[]const u8` - Byte slices
- `*T` - Pointers (non-function)
- Error unions and optionals of above

### Custom Ownership Patterns

Define project-specific patterns:

```zig
.ownership_patterns = &.{
    // Match function names
    .{ 
        .function_pattern = "acquire",
        .description = "Resource acquisition",
    },
    
    // Match return types
    .{ 
        .return_type_pattern = "!*Resource",
        .description = "Resource factories",
    },
    
    // Combine both for specificity
    .{ 
        .function_pattern = "fetch",
        .return_type_pattern = "![]const u8",
        .description = "Data fetching functions",
    },
};
```

### Complex Ownership Examples

```zig
// All recognized as ownership transfer:

// Direct return
pub fn createWidget(allocator: Allocator) !*Widget {
    return try allocator.create(Widget);
}

// With initialization
pub fn buildComplex(allocator: Allocator) !*Complex {
    const obj = try allocator.create(Complex);
    errdefer allocator.destroy(obj);
    
    obj.data = try allocator.alloc(u8, 100);
    errdefer allocator.free(obj.data);
    
    obj.count = 42;
    return obj; // Ownership transferred
}

// Struct with allocated fields
pub fn getData(allocator: Allocator) !DataResult {
    const buffer = try allocator.alloc(u8, 1024);
    errdefer allocator.free(buffer);
    
    const count = try readData(buffer);
    
    return DataResult{
        .data = buffer[0..count], // Ownership in struct
        .allocator = allocator,    // For later cleanup
    };
}
```

## Build System Integration

### Basic Integration

```zig
// build.zig
const quality_step = b.step("quality", "Run quality checks");

// Create check executable
const check = b.addExecutable(.{
    .name = "quality_check",
    .root_source_file = b.path("tools/quality_check.zig"),
    .target = target,
    .optimize = .ReleaseFast, // Optimize for speed
});
check.root_module.addImport("zig_tooling", zig_tooling_dep.module("zig_tooling"));

const run_check = b.addRunArtifact(check);
quality_step.dependOn(&run_check.step);
```

### Multiple Check Targets

Create specialized checks:

```zig
// Memory checks only
const memory_step = b.step("check-memory", "Check memory safety");
const run_memory = b.addRunArtifact(check);
run_memory.addArgs(&.{ "--mode", "memory" });
memory_step.dependOn(&run_memory.step);

// Test compliance only
const test_step = b.step("check-tests", "Check test compliance");
const run_tests = b.addRunArtifact(check);
run_tests.addArgs(&.{ "--mode", "tests" });
test_step.dependOn(&run_tests.step);

// Quick check (errors only)
const quick_step = b.step("check-quick", "Quick check (errors only)");
const run_quick = b.addRunArtifact(check);
run_quick.addArgs(&.{ "--errors-only" });
quick_step.dependOn(&run_quick.step);
```

### Pre-commit Integration

```zig
// Install pre-commit hook
const hook_step = b.step("install-hooks", "Install git hooks");
const install_hook = b.addSystemCommand(&.{
    "cp", "tools/pre-commit", ".git/hooks/pre-commit",
});
const chmod_hook = b.addSystemCommand(&.{
    "chmod", "+x", ".git/hooks/pre-commit",
});
chmod_hook.step.dependOn(&install_hook.step);
hook_step.dependOn(&chmod_hook.step);
```

## CI/CD Integration

### GitHub Actions

```yaml
name: Quality Checks
on: [push, pull_request]

jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: mlugg/setup-zig@v1
        with:
          version: 0.14.1
      
      - name: Cache zig-tooling
        uses: actions/cache@v3
        with:
          path: zig-cache
          key: ${{ runner.os }}-zig-${{ hashFiles('build.zig.zon') }}
      
      - name: Run quality checks
        run: |
          zig build -Doptimize=ReleaseFast quality
```

### GitLab CI

```yaml
quality:
  stage: test
  image: ziglang/zig:0.14.1
  cache:
    paths:
      - zig-cache/
  script:
    - zig build -Doptimize=ReleaseFast quality
  artifacts:
    when: on_failure
    reports:
      junit: quality-report.xml
```

### Output Formats

Configure output for CI systems:

```zig
// GitHub Actions format
const output = try zig_tooling.formatters.formatAsGitHubActions(
    allocator, 
    result, 
    .{ .verbose = true }
);

// JSON for further processing
const json = try zig_tooling.formatters.formatAsJson(
    allocator,
    result,
    .{ .json_indent = 2 }
);
```

## Performance Optimization

### Build Optimization

Always use ReleaseFast for analysis:

```bash
zig build -Doptimize=ReleaseFast quality
```

Performance comparison:
- Debug: ~150ms per file
- ReleaseFast: ~3ms per file (50x faster)

### Large Codebase Strategies

#### 1. Incremental Analysis
```zig
// Analyze only changed files
const changed_files = try getGitChangedFiles(allocator);
for (changed_files) |file| {
    const result = try zig_tooling.analyzeFile(allocator, file, config);
    // Process result...
}
```

#### 2. Parallel Analysis (Manual)
```zig
const thread_count = try std.Thread.getCpuCount();
var threads = try allocator.alloc(std.Thread, thread_count);
defer allocator.free(threads);

// Divide files among threads
for (threads, 0..) |*thread, i| {
    thread.* = try std.Thread.spawn(.{}, analyzeFileSet, .{
        files[i * files_per_thread..(i + 1) * files_per_thread],
    });
}
```

#### 3. Exclude Patterns
```zig
.patterns = .{
    .exclude_patterns = &.{
        "**/zig-cache/**",
        "**/zig-out/**",
        "**/vendor/**",
        "**/*.generated.zig",
    },
};
```

### Memory Usage

For very large files:

```zig
// Use streaming analysis for huge files
var analyzer = MemoryAnalyzer.init(allocator);
defer analyzer.deinit();

const file = try std.fs.cwd().openFile(path, .{});
defer file.close();

// Process in chunks
var buffer: [8192]u8 = undefined;
while (try file.read(&buffer)) |bytes_read| {
    if (bytes_read == 0) break;
    try analyzer.analyzeChunk(buffer[0..bytes_read]);
}
```

## Team Adoption Strategies

### Gradual Rollout

#### Phase 1: Warnings Only (Week 1-2)
```bash
# Run checks but don't fail builds
zig build quality || true
```

#### Phase 2: Fix Critical Issues (Week 3-4)
```zig
.options = .{
    .max_issues = 20,  // Focus on top issues
},
.memory = .{
    .check_defer = true,  // Start with one check
    .check_arena_usage = false,
    .check_allocator_usage = false,
},
```

#### Phase 3: Expand Coverage (Week 5-6)
```zig
.memory = .{
    .check_defer = true,
    .check_arena_usage = true,  // Add more checks
    .check_allocator_usage = true,
},
```

#### Phase 4: Full Enforcement (Week 7+)
```yaml
# CI/CD enforcement
- name: Quality checks
  run: zig build quality  # Now fails on issues
```

### Team Documentation

Create a team-specific guide:

```markdown
# Our Project's Quality Standards

## Approved Allocators
- GeneralPurposeAllocator for most uses
- ArenaAllocator for request handling only
- testing.allocator in tests

## Custom Patterns
- Functions ending in "Owned" transfer ownership
- "tmp_" prefix indicates arena-allocated

## Common False Positives
- Widget.create() transfers ownership (configured)
- RequestContext uses arena by design
```

### Training Materials

1. **Quick Reference Card**
   - Common issues and fixes
   - Approved patterns
   - How to run checks

2. **Code Review Checklist**
   - Memory safety items
   - Test compliance rules
   - Performance considerations

3. **Example PRs**
   - Before/after examples
   - Common refactoring patterns

## Troubleshooting

### Common Issues and Solutions

#### "Unknown allocator type detected"
```zig
// Add pattern for your allocator
.allocator_patterns = &.{
    .{ .name = "MyAllocator", .pattern = "my_alloc" },
},
```

#### "False positive on ownership transfer"
```zig
// Add ownership pattern
.ownership_patterns = &.{
    .{ .function_pattern = "createOwned", .description = "Our convention" },
},
```

#### "Too slow on large codebase"
```bash
# Use release build
zig build -Doptimize=ReleaseFast quality

# Exclude generated files
.exclude_patterns = &.{ "**/*.generated.zig" },
```

#### "Can't find configuration"
```zig
// Check config is passed correctly
const result = try zig_tooling.analyzeFile(allocator, path, config);
//                                                            ^^^^^^
```

### Debug Mode

Enable detailed logging:

```zig
.logging = .{
    .enabled = true,
    .callback = zig_tooling.stderrLogCallback,
    .min_level = .debug,
},
```

### Getting Help

1. **Check examples** - `examples/` directory has common patterns
2. **Read API docs** - Full API reference available
3. **GitHub Issues** - Search existing issues or create new
4. **Debug logs** - Enable logging for detailed info

---

This guide covers the major features and patterns in zig-tooling. For specific API details, see the [API Reference](api-reference.md). For quick setup, see the [Getting Started Guide](getting-started.md).
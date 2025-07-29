# Quality Standards for zig-tooling

This document defines the quality standards and rules that must be followed for code to pass the `zig build quality` checks. These standards ensure memory safety, test compliance, and overall code quality across the project.

## Overview

The `zig build quality` command runs comprehensive static analysis on the codebase to detect:
- Memory safety issues (allocation/deallocation mismatches)
- Test compliance violations (naming conventions, organization)
- Code style and best practice violations

By default, the quality check will **fail on both errors and warnings** to maintain high code standards.

## Memory Safety Rules

### 1. Allocation Cleanup Requirements

**Rule**: Every allocation must have a corresponding `defer` or `errdefer` statement for cleanup.

```zig
// ✅ Good - allocation with immediate defer
const buffer = try allocator.alloc(u8, 100);
defer allocator.free(buffer);

// ✅ Good - allocation with errdefer for error paths
const data = try allocator.alloc(u8, size);
errdefer allocator.free(data);
// ... code that might fail ...
return data; // Ownership transferred to caller

// ❌ Bad - missing defer
const temp = try allocator.alloc(u8, 50);
// No defer - will trigger "missing defer" error
```

### 2. Allowed Allocators

**Rule**: Only approved allocator types may be used in the codebase.

**Allowed allocators**:
- `std.heap.GeneralPurposeAllocator`
- `std.heap.ArenaAllocator`
- `std.testing.allocator`
- `testing.allocator`

```zig
// ✅ Good - using allowed allocator
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();

// ❌ Bad - using non-approved allocator
var page_alloc = std.heap.page_allocator; // Will trigger warning
```

### 3. Arena Allocator Usage

**Rule**: Arena allocators must be properly tracked and documented when used in library code.

```zig
// ✅ Good - arena with clear lifetime management
var arena = std.heap.ArenaAllocator.init(backing_allocator);
defer arena.deinit();

// All allocations use arena - no individual frees needed
const data1 = try arena.allocator().alloc(u8, 100);
const data2 = try arena.allocator().alloc(u8, 200);
// No individual defer needed - arena cleanup handles all

// ⚠️ Warning - arena in library without clear ownership
pub fn processData(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    // Missing defer - will trigger warning
}
```

### 4. Ownership Transfer Patterns

**Rule**: Functions that transfer memory ownership to callers are exempt from defer requirements.

**Recognized ownership transfer patterns**:
- Function names containing: `create`, `init`, `make`, `new`, `clone`, `duplicate`, `dupe`, `copy`, `alloc`, `toString`, `toSlice`, `format`
- Functions returning: `![]u8`, `![]const u8`, `?[]u8`, `?[]const u8`, `!*T`, `?*T`

```zig
// ✅ Good - ownership transfer function
pub fn createBuffer(allocator: std.mem.Allocator, size: usize) ![]u8 {
    return try allocator.alloc(u8, size);
    // No defer needed - caller owns the memory
}

// ✅ Good - init pattern with error handling
pub fn initData(allocator: std.mem.Allocator) !*MyStruct {
    const ptr = try allocator.create(MyStruct);
    errdefer allocator.destroy(ptr);
    
    ptr.* = MyStruct{ .value = 42 };
    return ptr; // Ownership transferred
}
```

## Test Compliance Rules

### 1. Test Naming Convention

**Rule**: All test functions must follow the naming convention.

```zig
// ✅ Good - proper test naming
test "unit: memory: allocation tracking" {
    // Test implementation
}

test "integration: patterns: project analysis" {
    // Test implementation
}

// ❌ Bad - missing proper prefix
test "something works" {
    // Will trigger naming convention error
}
```

### 2. Test Categories

**Rule**: Tests must include a category prefix from the allowed list.

**Allowed categories**:
- `unit:` - Unit tests for individual functions/modules
- `integration:` - Integration tests across components
- `e2e:` - End-to-end tests
- `performance:` - Performance benchmarks

```zig
// ✅ Good - includes category
test "unit: API: analyzeMemory basic functionality" {
    // Test implementation
}

// ❌ Bad - no category
test "analyzeMemory works" {
    // Will trigger category requirement error
}
```

### 3. Test Memory Safety

**Rule**: Tests using allocators must properly clean up allocations.

```zig
// ✅ Good - proper cleanup in tests
test "unit: memory: cleanup verification" {
    const allocator = std.testing.allocator;
    
    const buffer = try allocator.alloc(u8, 100);
    defer allocator.free(buffer);
    
    // Test implementation
}

// ❌ Bad - missing cleanup
test "unit: memory: leaky test" {
    const allocator = std.testing.allocator;
    const data = try allocator.alloc(u8, 50);
    // Missing defer - will trigger error
}
```

### 4. Test File Organization

**Rule**: Test files should be named with `test_` prefix and organized logically.

```
tests/
├── test_api.zig           ✅ Good naming
├── test_patterns.zig      ✅ Good naming
├── test_scope_integration.zig  ✅ Good naming
└── my_tests.zig          ❌ Bad - missing test_ prefix
```

## Code Style Rules

### 1. Error Handling

**Rule**: All errors must be handled appropriately.

```zig
// ✅ Good - explicit error handling
const result = doSomething() catch |err| {
    log.err("Operation failed: {}", .{err});
    return err;
};

// ✅ Good - error propagation
const data = try loadData();

// ❌ Bad - ignoring errors
_ = doSomething() catch {}; // Will trigger warning
```

### 2. Variable Usage

**Rule**: All declared variables must be used.

```zig
// ✅ Good - all variables used
const x = 42;
const y = x * 2;
return y;

// ❌ Bad - unused variable
const unused = 100; // Will trigger warning
return 42;
```

### 3. Import Organization

**Rule**: Imports should be organized and all imported symbols used.

```zig
// ✅ Good - organized imports, all used
const std = @import("std");
const zig_tooling = @import("zig_tooling");

// ❌ Bad - unused import
const unused_module = @import("unused.zig"); // Will trigger warning
```

## Excluded Paths

The following paths are excluded from quality checks by default:
- `**/zig-cache/**` - Build cache
- `**/zig-out/**` - Build outputs
- `**/.zig-cache/**` - Alternative cache location
- `**/build.zig` - Build scripts (different rules apply)
- `examples/**` - Example code (may intentionally show bad patterns)
- `tests/integration/sample_projects/**` - Test fixtures

## Running Quality Checks

### Basic Usage

```bash
# Run all quality checks
zig build quality

# Run only memory checks
zig build quality -- --check memory

# Run only test compliance checks
zig build quality -- --check tests

# Output in JSON format
zig build quality -- --format json

# Allow warnings (only fail on errors)
zig build quality -- --no-fail-on-warnings
```

### CI/CD Integration

```bash
# GitHub Actions format
zig build quality -- --format github-actions

# JSON output for custom processing
zig build quality -- --format json > quality-report.json
```

## Configuration

Quality standards can be customized via `.zigtools.json`:

```json
{
  "memory": {
    "allowed_allocators": ["MyCustomAllocator"],
    "ownership_patterns": [
      { "function_pattern": "get", "description": "Getters that allocate" }
    ]
  },
  "testing": {
    "allowed_categories": ["unit", "integration", "custom"],
    "test_prefix": "test_"
  },
  "options": {
    "fail_on_warnings": false  // Override default behavior
  }
}
```

## Best Practices

1. **Run quality checks locally** before committing code
2. **Fix warnings promptly** - they often indicate potential bugs
3. **Document ownership transfers** clearly in function comments
4. **Use arena allocators** for temporary allocations in performance-critical code
5. **Write comprehensive tests** with proper categorization
6. **Configure project-specific rules** in `.zigtools.json` as needed

## Common Issues and Solutions

### "Missing defer for allocation"

**Cause**: Allocation without corresponding cleanup.

**Solution**: Add `defer allocator.free(...)` immediately after allocation, or document ownership transfer.

### "Test naming convention violation"

**Cause**: Test doesn't follow required naming pattern.

**Solution**: Rename test to include category prefix: `test "unit: module: description"`.

### "Unknown allocator type"

**Cause**: Using allocator not in the allowed list.

**Solution**: Either add the allocator to `.zigtools.json` allowed list or use an approved allocator.

### "Arena allocator in library"

**Cause**: Using arena allocator without clear lifetime management.

**Solution**: Document arena lifetime or refactor to use standard allocator with proper cleanup.

## Performance Guidelines

- Quality checks run at ~3.23ms per file with ReleaseFast builds
- Use `zig build -Doptimize=ReleaseFast quality` for faster analysis
- Large files (4000+ lines) may take up to 27ms
- Total project scan typically completes in under 1 second

## Maintaining Quality

1. **Regular Checks**: Run `zig build quality` as part of your development workflow
2. **Pre-commit Hooks**: Use the generated pre-commit hooks for automatic checking
3. **CI Integration**: Include quality checks in your CI/CD pipeline
4. **Team Standards**: Ensure all team members understand and follow these standards
5. **Continuous Improvement**: Update standards based on project needs and lessons learned
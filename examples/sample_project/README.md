# Sample Project - Zig Tooling Test Data

This directory contains example files with intentional issues that demonstrate what the zig-tooling library can detect.

## Files

- **memory_issues.zig** - Examples of memory management issues:
  - Missing `defer` statements
  - Missing `errdefer` for error handling  
  - Proper memory management patterns (for comparison)

- **test_examples.zig** - Examples of testing compliance issues:
  - Improperly named tests
  - Tests without proper categorization
  - Good examples of properly categorized tests

## Using These Files

These files are used as test data in the integration examples. You can analyze them using the zig-tooling library:

```zig
const std = @import("std");
const zig_tooling = @import("zig_tooling");

// Analyze memory issues
const result = try zig_tooling.analyzeFile(allocator, "memory_issues.zig", null);
defer allocator.free(result.issues);

// Check the results
if (result.hasErrors()) {
    std.debug.print("Found {} issues\n", .{result.issues_found});
}
```

See the [integration examples](../) for more comprehensive usage patterns:
- [basic_usage.zig](../basic_usage.zig) - Getting started
- [build_integration.zig](../build_integration.zig) - Build system integration
- [custom_analyzer.zig](../custom_analyzer.zig) - Creating custom analyzers
- [ide_integration.zig](../ide_integration.zig) - IDE/editor integration
- [ci_integration.zig](../ci_integration.zig) - CI/CD pipeline integration

## Expected Analysis Results

### Memory Issues (memory_issues.zig)
The analyzer should detect:
- Missing `defer` statement after allocation in `leakyFunction` (line 5)
- Missing `errdefer` statement in `riskyOperation` (line 16)
- Proper ownership transfer in `goodExample` should not trigger warnings

### Testing Compliance (test_examples.zig)
The analyzer should detect:
- Test functions not following naming conventions
- Tests missing category prefixes (e.g., "unit:", "integration:")
- Invalid test categories not in the allowed list
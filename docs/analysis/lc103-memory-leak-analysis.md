# LC103: Memory Leak Analysis - analyzeMemory() and analyzeTests() Wrapper Functions

## Executive Summary

Issue LC103 identifies critical memory leaks in the `analyzeMemory()` and `analyzeTests()` wrapper functions in `src/zig_tooling.zig`. The root cause is a **use-after-free bug** where the functions access analyzer issue strings after calling `analyzer.deinit()`, which frees those strings. Additionally, the original analyzer issues array is never freed, causing a memory leak.

## The Memory Leak Pattern

### Current Implementation Problem

```zig
// Simplified view of the problematic pattern:
var analyzer = MemoryAnalyzer.init(allocator);
defer analyzer.deinit();  // This frees all issue strings

analyzer.analyzeSourceCode(file_path, source) catch |err| { ... };

const analyzer_issues = analyzer.getIssues();  // Returns slice of issues owned by analyzer
const issues = try allocator.alloc(Issue, analyzer_issues.len);

// BUG: After defer runs, analyzer.deinit() frees all strings in analyzer_issues
// The following loop accesses freed memory!
for (analyzer_issues, 0..) |ai, i| {
    issues[i] = Issue{
        .file_path = try allocator.dupe(u8, ai.file_path),    // Use-after-free!
        .message = try allocator.dupe(u8, ai.message),        // Use-after-free!
        .suggestion = if (ai.suggestion) |s| try allocator.dupe(u8, s) else null,  // Use-after-free!
        // ... other fields
    };
}
```

### What Actually Happens

1. **Line 117**: `defer analyzer.deinit()` is registered to run at scope exit
2. **Line 124**: `analyzer.getIssues()` returns a slice of issues owned by the analyzer
3. **Scope Exit**: `analyzer.deinit()` runs, freeing:
   - All issue file_path strings
   - All issue message strings
   - All issue suggestion strings
   - The issues array itself
4. **Lines 137-149**: The loop tries to duplicate strings that were just freed!

### Memory Leak Details

The leak occurs at three specific locations mentioned in the issue:
- **Line 211** (in analyzeMemory): `try allocator.dupe(u8, ai.file_path)`
- **Line 216** (in analyzeMemory): `try allocator.dupe(u8, ai.message)`
- **Line 217** (in analyzeMemory): `try allocator.dupe(u8, ai.suggestion)`

The same pattern repeats in `analyzeTests()` at the corresponding lines.

## Zig Memory Management Best Practices

### 1. Explicit Memory Ownership

In Zig, memory ownership must be explicit. Unlike languages with garbage collection or automatic reference counting, Zig requires clear ownership transfer patterns:

```zig
// Pattern 1: Caller owns memory
fn getData(allocator: Allocator) ![]u8 {
    return try allocator.dupe(u8, "data");  // Caller must free
}

// Pattern 2: Callee retains ownership
fn getDataRef(self: *Analyzer) []const u8 {
    return self.internal_data;  // Caller must NOT free
}
```

### 2. The defer Anti-Pattern

While `defer` is excellent for cleanup, it can create timing issues:

```zig
// WRONG: defer runs too early
var resource = Resource.init();
defer resource.deinit();
const data = resource.getData();
return data;  // data is now invalid!

// CORRECT: Transfer ownership before cleanup
var resource = Resource.init();
const data = try resource.extractData(allocator);  // Creates new copy
resource.deinit();  // Safe to cleanup now
return data;
```

### 3. Arena Allocators for Temporary Data

Arena allocators simplify memory management for temporary allocations:

```zig
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();  // Frees everything at once
const arena_alloc = arena.allocator();

// All allocations use arena_alloc
// No individual frees needed
```

### 4. Ownership Transfer Patterns

Common patterns for transferring allocated memory ownership:

```zig
// Pattern 1: Move semantics (take ownership)
fn takeOwnership(self: *Analyzer) ![]Issue {
    const issues = self.issues.toOwnedSlice();  // Transfers ownership
    return issues;
}

// Pattern 2: Clone before transfer
fn cloneData(self: *Analyzer, allocator: Allocator) ![]Issue {
    const new_issues = try allocator.alloc(Issue, self.issues.items.len);
    for (self.issues.items, 0..) |issue, i| {
        new_issues[i] = try issue.clone(allocator);
    }
    return new_issues;
}

// Pattern 3: Extract and reset
fn extractIssues(self: *Analyzer) []Issue {
    const issues = self.issues.items;
    self.issues.items = &.{};  // Clear without freeing
    return issues;
}
```

## Solution Approaches

### Approach 1: Copy Before Cleanup (Minimal Change)

```zig
pub fn analyzeMemory(
    allocator: std.mem.Allocator,
    source: []const u8,
    file_path: []const u8,
    config: ?Config,
) AnalysisError!AnalysisResult {
    const start_time = std.time.milliTimestamp();
    
    var analyzer = if (config) |cfg|
        MemoryAnalyzer.initWithFullConfig(allocator, cfg)
    else
        MemoryAnalyzer.init(allocator);
    // Remove defer here!
    
    analyzer.analyzeSourceCode(file_path, source) catch |err| {
        analyzer.deinit();  // Clean up on error
        switch (err) {
            error.OutOfMemory => return AnalysisError.OutOfMemory,
            else => return AnalysisError.ParseError,
        }
    };
    
    const analyzer_issues = analyzer.getIssues();
    const issues = try allocator.alloc(Issue, analyzer_issues.len);
    var issues_populated: usize = 0;
    errdefer {
        for (issues[0..issues_populated]) |issue| {
            allocator.free(issue.file_path);
            allocator.free(issue.message);
            if (issue.suggestion) |s| allocator.free(s);
        }
        allocator.free(issues);
    }
    
    // Copy all strings while analyzer is still alive
    for (analyzer_issues, 0..) |ai, i| {
        issues[i] = Issue{
            .file_path = try allocator.dupe(u8, ai.file_path),
            .line = ai.line,
            .column = ai.column,
            .issue_type = ai.issue_type,
            .severity = ai.severity,
            .message = try allocator.dupe(u8, ai.message),
            .suggestion = if (ai.suggestion) |s| try allocator.dupe(u8, s) else null,
            .code_snippet = ai.code_snippet,
        };
        issues_populated += 1;
    }
    
    // NOW we can safely clean up the analyzer
    analyzer.deinit();
    
    const end_time = std.time.milliTimestamp();
    
    return AnalysisResult{
        .issues = issues,
        .files_analyzed = 1,
        .issues_found = @intCast(issues.len),
        .analysis_time_ms = @intCast(end_time - start_time),
    };
}
```

### Approach 2: Add Ownership Transfer Method

A cleaner approach would be to add methods to the analyzers that transfer ownership:

```zig
// In MemoryAnalyzer:
pub fn extractIssues(self: *MemoryAnalyzer) []Issue {
    const issues = self.issues.toOwnedSlice();
    return issues;
}

// In wrapper:
const issues = analyzer.extractIssues();  // Transfers ownership
defer analyzer.deinit();  // Safe now, issues already extracted
```

### Approach 3: Clone Method

Add a clone method to Issue for safer copying:

```zig
// In types.zig:
pub fn clone(self: Issue, allocator: Allocator) !Issue {
    return Issue{
        .file_path = try allocator.dupe(u8, self.file_path),
        .line = self.line,
        .column = self.column,
        .issue_type = self.issue_type,
        .severity = self.severity,
        .message = try allocator.dupe(u8, self.message),
        .suggestion = if (self.suggestion) |s| try allocator.dupe(u8, s) else null,
        .code_snippet = self.code_snippet,
    };
}
```

## Testing Recommendations

### 1. Memory Leak Detection Tests

```zig
test "LC103: analyzeMemory no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        try testing.expect(leaked == .ok);
    }
    const allocator = gpa.allocator();
    
    const source = 
        \\fn leaky() void {
        \\    const data = try allocator.alloc(u8, 100);
        \\}
    ;
    
    const result = try analyzeMemory(allocator, source, "test.zig", null);
    defer {
        for (result.issues) |issue| {
            allocator.free(issue.file_path);
            allocator.free(issue.message);
            if (issue.suggestion) |s| allocator.free(s);
        }
        allocator.free(result.issues);
    }
    
    try testing.expect(result.issues.len > 0);
}
```

### 2. Use-After-Free Detection

Consider using AddressSanitizer or Valgrind in CI:

```bash
# Build with AddressSanitizer
zig build -Dsanitize=address

# Run with Valgrind
valgrind --leak-check=full --show-leak-kinds=all ./zig-out/bin/test
```

### 3. Systematic API Testing

Create a test suite that verifies all public APIs are leak-free:

```zig
// tests/test_memory_leaks.zig
const api_functions = .{
    analyzeMemory,
    analyzeTests,
    analyzeFile,
    analyzeSource,
    patterns.checkProject,
    patterns.checkFile,
};

test "All APIs leak-free" {
    inline for (api_functions) |api_fn| {
        // Test with GPA
    }
}
```

## Prevention Strategies

### 1. Ownership Documentation

Document ownership clearly in function comments:

```zig
/// Analyzes memory safety in the provided source code.
/// 
/// Returns: AnalysisResult with newly allocated issues.
/// Ownership: Caller owns all returned memory and must free:
///   - result.issues array
///   - Each issue's file_path, message, and suggestion strings
pub fn analyzeMemory(...) !AnalysisResult {
```

### 2. RAII-Style Wrappers

Consider RAII-style wrappers for complex resources:

```zig
const AnalyzerContext = struct {
    analyzer: MemoryAnalyzer,
    allocator: Allocator,
    
    pub fn init(allocator: Allocator) AnalyzerContext {
        return .{
            .analyzer = MemoryAnalyzer.init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *AnalyzerContext) void {
        self.analyzer.deinit();
    }
    
    pub fn analyzeAndExtract(self: *AnalyzerContext, source: []const u8) ![]Issue {
        try self.analyzer.analyzeSourceCode("", source);
        // Extract issues with proper ownership transfer
        return self.extractIssues();
    }
};
```

### 3. Static Analysis

Add custom linting rules to detect patterns like:
- Accessing analyzer data after defer
- Missing corresponding frees for allocations
- Inconsistent ownership patterns

## Developer Resources

### Zig Documentation
- [Zig Language Reference - Memory](https://ziglang.org/documentation/master/#Memory)
- [Zig Standard Library - Allocators](https://ziglang.org/documentation/master/std/#std.mem.Allocator)
- [Zig Guide - Allocators](https://zig.guide/standard-library/allocators/)

### Best Practices Articles
- [Manual Memory Management in Zig: Allocators Demystified](https://dev.to/hexshift/manual-memory-management-in-zig-allocators-demystified-46ne)
- [Understanding Zig's Memory Management](https://peerdh.com/blogs/programming-insights/understanding-zigs-memory-management)
- [Memory Safety Features in Zig](https://gencmurat.com/en/posts/memory-safety-features-in-zig/)
- [Comprehensive Guide to Memory Management in Zig](https://gencmurat.com/en/posts/memory-management-in-zig/)

### Tools and Utilities
- **GeneralPurposeAllocator**: Built-in allocator with leak detection
- **std.heap.ArenaAllocator**: Simplifies temporary allocation patterns
- **std.testing.allocator**: Detects leaks in tests automatically
- **Valgrind**: External tool for memory error detection
- **AddressSanitizer**: Compiler-based memory error detector

## Conclusion

The memory leak in LC103 is a classic use-after-free bug caused by accessing analyzer-owned memory after the analyzer has been deinitialized. The fix requires reordering operations to copy data before cleanup or implementing proper ownership transfer mechanisms.

This issue highlights the importance of:
1. Understanding Zig's explicit memory ownership model
2. Careful ordering of cleanup operations
3. Comprehensive memory leak testing
4. Clear documentation of memory ownership

By following Zig's memory management best practices and implementing systematic testing, similar issues can be prevented in the future.
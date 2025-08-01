# LC106 & LC107: Memory Leak Analysis - String Ownership and Cleanup Issues

## Executive Summary

Issues LC106 and LC107 represent critical memory leaks in the zig-tooling library related to improper string ownership management and incomplete memory cleanup. Both issues stem from confusion about memory ownership when transferring data between different layers of the API.

- **LC106**: Memory leaks in `patterns.checkProject()` due to ownership transfer confusion when aggregating issues from analyzers
- **LC107**: Memory leaks in `analyzeFile()` and `analyzeSource()` due to incomplete cleanup - only freeing issue arrays but not the string fields within each issue

## Issue Analysis

### LC106: patterns.checkProject Memory Leaks

**Location**: `src/patterns.zig:167,172,173` (as referenced in the issue, though the actual issue appears to be in how issues are aggregated)

**Root Cause**: Ownership transfer confusion when copying issues from analyzer results to the aggregated list

**Current Implementation**:
```zig
// Transfer ownership of issues from file_result to all_issues
// The issues already own their strings, so we just move them
for (file_result.issues) |issue| {
    try all_issues.append(issue);
}

// Only free the array, not the strings (which have been transferred to all_issues)
allocator.free(file_result.issues);
```

**Problem**: The comment says "The issues already own their strings, so we just move them", but this assumes that `analyzeFile()` is properly transferring ownership. However, if `analyzeFile()` is duplicating strings unnecessarily or if there's a mismatch in ownership expectations, this causes leaks.

### LC107: analyzeFile() and analyzeSource() Memory Leaks

**Location**: 
- `src/zig_tooling.zig:291,294` (analyzeFile)
- `src/zig_tooling.zig:334,337` (analyzeSource)

**Root Cause**: Incomplete memory cleanup - only freeing the issue arrays but not the string fields

**Current Implementation**:
```zig
// In analyzeFile():
const memory_result = try analyzeMemory(allocator, source, path, config);
defer allocator.free(memory_result.issues);  // Only frees the array!

const testing_result = try analyzeTests(allocator, source, path, config);
defer allocator.free(testing_result.issues);  // Only frees the array!

// Issues are copied via @memcpy, transferring ownership
@memcpy(combined_issues[0..memory_result.issues.len], memory_result.issues);
```

**Problem**: The defer statements only free the issue arrays, not the strings (file_path, message, suggestion) inside each issue. Since `analyzeMemory()` and `analyzeTests()` duplicate these strings using `allocator.dupe()`, they need to be freed.

## Memory Ownership Flow Analysis

### Current Flow (Buggy)

1. **analyzeMemory()/analyzeTests()**:
   - Creates new issues with duplicated strings (`allocator.dupe()`)
   - Returns ownership of both array and strings to caller

2. **analyzeFile()/analyzeSource()**:
   - Receives ownership of issues and their strings
   - Transfers issues to combined array via `@memcpy`
   - **BUG**: Only frees the original arrays, not the strings
   - Returns combined array to caller

3. **patterns.checkProject()**:
   - Calls `analyzeFile()` for each file
   - Appends issues to aggregate list
   - Frees only the array from `analyzeFile()`
   - **ASSUMPTION**: Believes strings are already transferred

### Ownership Transfer Confusion

The core issue is a mismatch in ownership expectations:

1. **analyzeMemory/analyzeTests** create new allocations for all strings
2. **analyzeFile/analyzeSource** transfer ownership via `@memcpy` but don't properly clean up
3. **patterns.checkProject** assumes ownership was already transferred correctly

## Detailed Problem Analysis

### Memory Allocation Chain

```
analyzeMemory() → allocates strings → returns AnalysisResult
                                           ↓
analyzeFile() → combines results → @memcpy (transfers ownership)
                                    ↓
                                    defer only frees arrays (LEAK!)
                                           ↓
patterns.checkProject() → appends issues → assumes strings transferred
```

### Why This Causes Leaks

1. **In analyzeFile/analyzeSource**:
   ```zig
   // memory_result.issues contains Issues with allocated strings
   defer allocator.free(memory_result.issues);  // Only frees array!
   // The strings inside each issue are leaked!
   ```

2. **In patterns.checkProject**:
   ```zig
   // file_result.issues already leaked strings in analyzeFile
   for (file_result.issues) |issue| {
       try all_issues.append(issue);  // Appends issues with leaked strings
   }
   ```

## Solution Design

### Solution 1: Fix analyzeFile/analyzeSource (Addresses LC107)

**Approach**: Properly handle ownership transfer by not freeing anything since ownership is transferred

```zig
pub fn analyzeFile(
    allocator: std.mem.Allocator,
    path: []const u8,
    config: ?Config,
) AnalysisError!AnalysisResult {
    // ... existing code ...
    
    // Run both analyzers
    const memory_result = try analyzeMemory(allocator, source, path, config);
    // Don't defer free - ownership will be transferred
    
    const testing_result = try analyzeTests(allocator, source, path, config);
    // Don't defer free - ownership will be transferred
    
    // Combine results
    const total_issues = memory_result.issues.len + testing_result.issues.len;
    const combined_issues = try allocator.alloc(Issue, total_issues);
    errdefer allocator.free(combined_issues);
    
    // Transfer ownership of the issues
    @memcpy(combined_issues[0..memory_result.issues.len], memory_result.issues);
    @memcpy(combined_issues[memory_result.issues.len..], testing_result.issues);
    
    // Free only the arrays, not the contents (ownership transferred)
    allocator.free(memory_result.issues);
    allocator.free(testing_result.issues);
    
    return AnalysisResult{
        .issues = combined_issues,
        // ... rest of fields
    };
}
```

### Solution 2: Create Proper Free Functions (Addresses both LC106 & LC107)

**Approach**: Add helper functions to properly free AnalysisResult structures

```zig
// In src/zig_tooling.zig or src/utils.zig
pub fn freeAnalysisResult(allocator: std.mem.Allocator, result: AnalysisResult) void {
    for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    }
    allocator.free(result.issues);
}

// Update analyzeFile to use it:
pub fn analyzeFile(...) AnalysisError!AnalysisResult {
    // ... existing code ...
    
    const memory_result = try analyzeMemory(allocator, source, path, config);
    defer freeAnalysisResult(allocator, memory_result);
    
    const testing_result = try analyzeTests(allocator, source, path, config);
    defer freeAnalysisResult(allocator, testing_result);
    
    // ... combine and return ...
}
```

### Solution 3: Rethink Ownership Model (Long-term fix)

**Approach**: Use a clearer ownership transfer pattern

```zig
// Option A: Move semantics
pub fn extractIssues(self: *AnalysisResult) []Issue {
    const issues = self.issues;
    self.issues = &.{};  // Clear without freeing
    return issues;
}

// Option B: Arena allocator for temporary data
pub fn analyzeFileWithArena(
    allocator: std.mem.Allocator,
    path: []const u8,
    config: ?Config,
) AnalysisError!AnalysisResult {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();
    
    // Use arena for intermediate results
    const memory_result = try analyzeMemory(arena_alloc, source, path, config);
    const testing_result = try analyzeTests(arena_alloc, source, path, config);
    
    // Copy to final allocator
    const combined_issues = try allocator.alloc(Issue, total_issues);
    for (memory_result.issues, 0..) |issue, i| {
        combined_issues[i] = try issue.clone(allocator);
    }
    // ... etc
}
```

## Implementation Plan

### Phase 1: Immediate Fix (LC107)
1. Fix `analyzeFile()` and `analyzeSource()` to not leak strings
2. Add comprehensive memory leak tests
3. Document ownership clearly in comments

### Phase 2: Helper Functions (LC108)
1. Implement `freeAnalysisResult()` helper
2. Update all code to use the helper
3. Make it a public API for users

### Phase 3: Systematic Review (LC106)
1. Review all ownership transfers in patterns.zig
2. Fix any duplicate allocations
3. Add ownership documentation

### Phase 4: Long-term Improvements
1. Consider arena allocator patterns
2. Add ownership tracking types
3. Create systematic memory testing

## Testing Strategy

### 1. Memory Leak Tests for LC107

```zig
test "LC107: analyzeFile no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        try testing.expect(leaked == .ok);
    }
    const allocator = gpa.allocator();
    
    // Create test file
    const test_dir = "test_lc107";
    try std.fs.cwd().makePath(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};
    
    const test_file = try std.fmt.allocPrint(allocator, "{s}/test.zig", .{test_dir});
    defer allocator.free(test_file);
    
    try std.fs.cwd().writeFile(.{
        .sub_path = test_file,
        .data = MEMORY_LEAK_SOURCE,
    });
    
    // Analyze file
    const result = try zig_tooling.analyzeFile(allocator, test_file, null);
    
    // Properly free result
    for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    }
    allocator.free(result.issues);
}
```

### 2. Ownership Transfer Tests

```zig
test "LC106: checkProject ownership transfer validation" {
    // Test that verifies no double-frees or leaks in ownership transfers
}
```

### 3. Integration Tests

```zig
test "Full pipeline memory safety" {
    // Test checkProject → analyzeFile → analyzeMemory/Tests full chain
}
```

## Prevention Measures

### 1. Documentation Standards

Every function that allocates memory must document:
- Who owns the returned memory
- What needs to be freed
- Example cleanup code

### 2. Consistent Patterns

Adopt consistent ownership patterns:
- "extract" functions transfer ownership
- "get" functions return borrowed references
- "clone" functions create new allocations

### 3. Static Analysis

Add custom linting rules to detect:
- Missing frees for allocated fields
- Incomplete cleanup in defer statements
- Ownership transfer violations

### 4. API Design

Consider RAII-style wrappers:
```zig
const ManagedResult = struct {
    result: AnalysisResult,
    allocator: std.mem.Allocator,
    
    pub fn deinit(self: *ManagedResult) void {
        freeAnalysisResult(self.allocator, self.result);
    }
};
```

## Conclusion

LC106 and LC107 represent systematic memory management issues stemming from unclear ownership semantics and incomplete cleanup. The immediate fix is straightforward - ensure all allocated strings are properly freed. The long-term solution requires establishing clear ownership patterns and providing helper functions to manage complex allocations.

These issues highlight the importance of:
1. Clear ownership documentation
2. Comprehensive memory leak testing  
3. Helper functions for complex cleanup
4. Consistent allocation/deallocation patterns

By addressing these issues systematically, we can prevent similar problems in the future and make the API safer and easier to use correctly.
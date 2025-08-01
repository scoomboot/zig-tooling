//! Test cases for LC087 ownership transfer detection
//!
//! This test suite focuses on comprehensive testing of ownership transfer patterns,
//! particularly struct initialization patterns that are currently being incorrectly
//! flagged as missing defer statements.
//!
//! Key patterns tested:
//! 1. Allocation followed by immediate struct return (analyzeFile pattern)
//! 2. Multi-line struct construction with allocated fields
//! 3. Nested struct returns and complex ownership scenarios
//! 4. Edge cases and false positive prevention

const std = @import("std");
const testing = std.testing;
const zig_tooling = @import("zig_tooling");

// Helper function to verify no missing defer issues in result
fn assertNoMissingDeferIssues(issues: []const zig_tooling.Issue) !void {
    for (issues) |issue| {
        if (issue.issue_type == .missing_defer) {
            std.debug.print("Unexpected missing_defer issue: {s}\n", .{issue.message});
            return error.UnexpectedMissingDeferIssue;
        }
    }
}

// Helper function to find specific issue types
fn findIssueType(issues: []const zig_tooling.Issue, issue_type: zig_tooling.IssueType) ?zig_tooling.Issue {
    for (issues) |issue| {
        if (issue.issue_type == issue_type) {
            return issue;
        }
    }
    return null;
}

test "LC087: exact pattern from zig_tooling.zig:128 - AnalysisResult struct return" {
    const allocator = testing.allocator;
    
    // This replicates the exact pattern from src/zig_tooling.zig:128
    const source =
        \\const AnalysisResult = struct {
        \\    issues: []Issue,
        \\    files_analyzed: u32,
        \\    issues_found: u32,
        \\    analysis_time_ms: u32,
        \\};
        \\
        \\const Issue = struct {
        \\    file_path: []const u8,
        \\    message: []const u8,
        \\};
        \\
        \\pub fn analyzeFile(allocator: std.mem.Allocator, count: usize) !AnalysisResult {
        \\    const issues = try allocator.alloc(Issue, count);
        \\    errdefer allocator.free(issues);
        \\    
        \\    // Populate issues (simplified)
        \\    for (issues, 0..) |*issue, i| {
        \\        issue.* = Issue{
        \\            .file_path = try std.fmt.allocPrint(allocator, "file_{d}.zig", .{i}),
        \\            .message = try std.fmt.allocPrint(allocator, "Issue {d}", .{i}),
        \\        };
        \\    }
        \\    
        \\    return AnalysisResult{
        \\        .issues = issues,
        \\        .files_analyzed = 1,
        \\        .issues_found = @intCast(issues.len),
        \\        .analysis_time_ms = 100,
        \\    };
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should NOT report missing defer for the initial `issues` allocation
    // because it's transferred to the returned struct
    try assertNoMissingDeferIssues(result.issues);
    
    // However, it might still flag the allocPrint calls inside the loop
    // which is correct behavior since those strings need proper cleanup
    std.debug.print("Found {d} issues in AnalysisResult pattern test\n", .{result.issues.len});
}

test "LC087: simple struct field ownership transfer" {
    const allocator = testing.allocator;
    
    const source =
        \\const Data = struct {
        \\    buffer: []u8,
        \\    size: usize,
        \\};
        \\
        \\pub fn createData(allocator: std.mem.Allocator, size: usize) !Data {
        \\    const buffer = try allocator.alloc(u8, size);
        \\    
        \\    return Data{
        \\        .buffer = buffer,
        \\        .size = size,
        \\    };
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Debug output
    std.debug.print("\nSimple struct test found {d} issues\n", .{result.issues.len});
    for (result.issues) |issue| {
        std.debug.print("  Issue: {s} at line {d}\n", .{issue.message, issue.line});
    }
    
    // Should not report missing defer because buffer ownership transfers to returned struct
    try assertNoMissingDeferIssues(result.issues);
}

test "LC087: multi-line struct construction" {
    const allocator = testing.allocator;
    
    const source =
        \\const ComplexData = struct {
        \\    primary: []u8,
        \\    secondary: []u8,
        \\    metadata: []const u8,
        \\    count: usize,
        \\};
        \\
        \\pub fn buildComplexData(allocator: std.mem.Allocator) !ComplexData {
        \\    const primary = try allocator.alloc(u8, 100);
        \\    const secondary = try allocator.alloc(u8, 50);
        \\    const metadata = try allocator.dupe(u8, "metadata");
        \\    
        \\    return ComplexData{
        \\        .primary = primary,
        \\        .secondary = secondary,
        \\        .metadata = metadata,
        \\        .count = 150,
        \\    };
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // All three allocations should be recognized as ownership transfers
    try assertNoMissingDeferIssues(result.issues);
}

test "LC087: struct with errdefer pattern" {
    const allocator = testing.allocator;
    
    const source =
        \\const ResourceBundle = struct {
        \\    data: []u8,
        \\    config: []u8,
        \\};
        \\
        \\pub fn loadResources(allocator: std.mem.Allocator) !ResourceBundle {
        \\    const data = try allocator.alloc(u8, 1024);
        \\    errdefer allocator.free(data);
        \\    
        \\    const config = try allocator.alloc(u8, 256);
        \\    errdefer allocator.free(config);
        \\    
        \\    // Some operation that might fail
        \\    if (data.len + config.len > 2000) {
        \\        return error.TooLarge;
        \\    }
        \\    
        \\    return ResourceBundle{
        \\        .data = data,
        \\        .config = config,
        \\    };
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should not report missing defer because:
    // 1. Both allocations have proper errdefer cleanup
    // 2. Both allocations transfer ownership to returned struct
    try assertNoMissingDeferIssues(result.issues);
}

test "LC087: nested struct return pattern" {
    const allocator = testing.allocator;
    
    const source =
        \\const InnerData = struct {
        \\    values: []i32,
        \\};
        \\
        \\const OuterData = struct {
        \\    inner: InnerData,
        \\    name: []u8,
        \\};
        \\
        \\pub fn createNested(allocator: std.mem.Allocator) !OuterData {
        \\    const values = try allocator.alloc(i32, 10);
        \\    const name = try allocator.dupe(u8, "nested");
        \\    
        \\    return OuterData{
        \\        .inner = InnerData{
        \\            .values = values,
        \\        },
        \\        .name = name,
        \\    };
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Both allocations should be recognized as transferred through nested struct
    try assertNoMissingDeferIssues(result.issues);
}

test "LC087: error union return type pattern" {
    const allocator = testing.allocator;
    
    const source =
        \\const Result = struct {
        \\    data: []u8,
        \\    success: bool,
        \\};
        \\
        \\pub fn processData(allocator: std.mem.Allocator, size: usize) !Result {
        \\    if (size == 0) return error.InvalidSize;
        \\    
        \\    const data = try allocator.alloc(u8, size);
        \\    
        \\    return Result{
        \\        .data = data,
        \\        .success = true,
        \\    };
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should recognize error union return as ownership transfer
    try assertNoMissingDeferIssues(result.issues);
}

test "LC087: optional return type pattern" {
    const allocator = testing.allocator;
    
    const source =
        \\const OptionalData = struct {
        \\    buffer: []u8,
        \\};
        \\
        \\pub fn maybeCreateData(allocator: std.mem.Allocator, create: bool) ?OptionalData {
        \\    if (!create) return null;
        \\    
        \\    const buffer = allocator.alloc(u8, 100) catch return null;
        \\    
        \\    return OptionalData{
        \\        .buffer = buffer,
        \\    };
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should recognize optional return as ownership transfer
    try assertNoMissingDeferIssues(result.issues);
}

test "LC087: stored variable later returned in struct" {
    const allocator = testing.allocator;
    
    const source =
        \\const DelayedReturn = struct {
        \\    processed_data: []u8,
        \\    length: usize,
        \\};
        \\
        \\pub fn processDelayed(allocator: std.mem.Allocator) !DelayedReturn {
        \\    const raw_data = try allocator.alloc(u8, 256);
        \\    
        \\    // Some processing happens here
        \\    for (raw_data, 0..) |*byte, i| {
        \\        byte.* = @intCast(i % 256);
        \\    }
        \\    
        \\    const length_value = raw_data.len;
        \\    
        \\    // Variable is stored and returned later
        \\    return DelayedReturn{
        \\        .processed_data = raw_data,
        \\        .length = length_value,
        \\    };
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should detect that raw_data is eventually returned in struct
    try assertNoMissingDeferIssues(result.issues);
}

test "LC087: false positive prevention - allocation not returned" {
    const allocator = testing.allocator;
    
    const source =
        \\const LocalData = struct {
        \\    static_data: []const u8,
        \\};
        \\
        \\pub fn processLocal(allocator: std.mem.Allocator) !LocalData {
        \\    const temp_buffer = try allocator.alloc(u8, 100);
        \\    // This allocation is NOT returned - should require defer
        \\    
        \\    // Do some work with temp_buffer
        \\    for (temp_buffer) |*byte| {
        \\        byte.* = 42;
        \\    }
        \\    
        \\    const result = LocalData{
        \\        .static_data = "static content",
        \\    };
        \\    
        \\    return result;
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // SHOULD report missing defer because temp_buffer is not returned
    const missing_defer_issue = findIssueType(result.issues, .missing_defer);
    try testing.expect(missing_defer_issue != null);
    
    if (missing_defer_issue) |issue| {
        try testing.expect(std.mem.indexOf(u8, issue.message, "temp_buffer") != null or
                          std.mem.indexOf(u8, issue.message, "line") != null);
    }
}

test "LC087: mixed pattern - some allocations returned, some not" {
    const allocator = testing.allocator;
    
    const source =
        \\const MixedResult = struct {
        \\    important_data: []u8,
        \\    metadata: []const u8,
        \\};
        \\
        \\pub fn mixedProcessing(allocator: std.mem.Allocator) !MixedResult {
        \\    const important_data = try allocator.alloc(u8, 200);
        \\    const temp_working_space = try allocator.alloc(u8, 500);
        \\    const metadata = try allocator.dupe(u8, "processed");
        \\    
        \\    // Use temp_working_space for computation
        \\    for (temp_working_space, 0..) |*byte, i| {
        \\        byte.* = @intCast(i % 256);
        \\    }
        \\    
        \\    // Process important_data using temp_working_space
        \\    for (important_data, 0..) |*byte, i| {
        \\        if (i < temp_working_space.len) {
        \\            byte.* = temp_working_space[i];
        \\        }
        \\    }
        \\    
        \\    // temp_working_space should be freed here but isn't!
        \\    
        \\    return MixedResult{
        \\        .important_data = important_data,  // Ownership transferred
        \\        .metadata = metadata,              // Ownership transferred
        \\    };
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should find missing defer for temp_working_space only
    var missing_defer_count: usize = 0;
    for (result.issues) |issue| {
        if (issue.issue_type == .missing_defer) {
            missing_defer_count += 1;
        }
    }
    
    // Should have exactly one missing defer issue for temp_working_space
    try testing.expect(missing_defer_count == 1);
}

test "LC087: array element assignment pattern" {
    const allocator = testing.allocator;
    
    const source =
        \\const Item = struct {
        \\    data: []u8,
        \\    id: u32,
        \\};
        \\
        \\const Collection = struct {
        \\    items: []Item,
        \\    count: usize,
        \\};
        \\
        \\pub fn createCollection(allocator: std.mem.Allocator, count: usize) !Collection {
        \\    const items = try allocator.alloc(Item, count);
        \\    
        \\    for (items, 0..) |*item, i| {
        \\        const item_data = try allocator.alloc(u8, 64);
        \\        item.* = Item{
        \\            .data = item_data,
        \\            .id = @intCast(i),
        \\        };
        \\    }
        \\    
        \\    return Collection{
        \\        .items = items,
        \\        .count = count,
        \\    };
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should recognize that both `items` and `item_data` allocations transfer ownership
    try assertNoMissingDeferIssues(result.issues);
}

test "LC087: complex return with error handling" {
    const allocator = testing.allocator;
    
    const source =
        \\const ProcessResult = struct {
        \\    output: []u8,
        \\    error_log: []u8,
        \\    status: enum { success, warning, error },
        \\};
        \\
        \\pub fn complexProcess(allocator: std.mem.Allocator, input_size: usize) !ProcessResult {
        \\    if (input_size == 0) return error.InvalidInput;
        \\    
        \\    const output = try allocator.alloc(u8, input_size * 2);
        \\    errdefer allocator.free(output);
        \\    
        \\    const error_log = try allocator.alloc(u8, 256);
        \\    errdefer allocator.free(error_log);
        \\    
        \\    // Simulate some processing that could fail
        \\    if (input_size > 1000) {
        \\        return error.TooLarge;
        \\    }
        \\    
        \\    // Fill buffers
        \\    for (output) |*byte| byte.* = 0xAA;
        \\    for (error_log) |*byte| byte.* = 0;
        \\    
        \\    return ProcessResult{
        \\        .output = output,
        \\        .error_log = error_log,
        \\        .status = .success,
        \\    };
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should not report missing defer because:
    // 1. Both allocations have errdefer cleanup
    // 2. Both allocations transfer ownership on success
    try assertNoMissingDeferIssues(result.issues);
}

test "LC087: struct initialization with computation" {
    const allocator = testing.allocator;
    
    const source =
        \\const ComputedResult = struct {
        \\    processed: []u8,
        \\    original_size: usize,
        \\    processed_size: usize,
        \\};
        \\
        \\pub fn computeResult(allocator: std.mem.Allocator, size: usize) !ComputedResult {
        \\    const processed = try allocator.alloc(u8, size);
        \\    
        \\    // Do computation
        \\    for (processed, 0..) |*byte, i| {
        \\        byte.* = @intCast((i * 13) % 256);
        \\    }
        \\    
        \\    const original_size = size;
        \\    const processed_size = processed.len;
        \\    
        \\    return ComputedResult{
        \\        .processed = processed,
        \\        .original_size = original_size,
        \\        .processed_size = processed_size,
        \\    };
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should recognize that `processed` ownership transfers to returned struct
    try assertNoMissingDeferIssues(result.issues);
}

test "LC087: edge case - immediate struct literal return" {
    const allocator = testing.allocator;
    
    const source =
        \\const DirectResult = struct {
        \\    buffer: []u8,
        \\};
        \\
        \\pub fn directReturn(allocator: std.mem.Allocator) !DirectResult {
        \\    // Immediate return with allocation in struct literal
        \\    return DirectResult{
        \\        .buffer = try allocator.alloc(u8, 128),
        \\    };
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should recognize inline allocation as ownership transfer
    try assertNoMissingDeferIssues(result.issues);
}

// Regression test to ensure existing ownership transfer patterns still work
test "LC087: regression - ensure existing ownership transfer tests pass" {
    const allocator = testing.allocator;
    
    // Test pattern from existing LC068 tests - function name based detection
    const source1 =
        \\pub fn createBuffer(allocator: std.mem.Allocator) ![]u8 {
        \\    return try allocator.alloc(u8, 100);
        \\}
    ;
    
    const result1 = try zig_tooling.analyzeMemory(allocator, source1, "test1.zig", null);
    defer allocator.free(result1.issues);
    defer for (result1.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    try assertNoMissingDeferIssues(result1.issues);
    
    // Test immediate return pattern
    const source2 =
        \\pub fn getNewSlice(allocator: std.mem.Allocator) ![]u8 {
        \\    const buffer = try allocator.alloc(u8, 50);
        \\    return buffer;
        \\}
    ;
    
    const result2 = try zig_tooling.analyzeMemory(allocator, source2, "test2.zig", null);
    defer allocator.free(result2.issues);
    defer for (result2.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    try assertNoMissingDeferIssues(result2.issues);
}
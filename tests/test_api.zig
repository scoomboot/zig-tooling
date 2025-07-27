const std = @import("std");
const testing = std.testing;
const zig_tooling = @import("zig_tooling");

test "unit: API: analyzeMemory with valid source" {
    const allocator = testing.allocator;
    
    const source =
        \\pub fn main() !void {
        \\    const allocator = std.heap.page_allocator;
        \\    const data = try allocator.alloc(u8, 100);
        \\    defer allocator.free(data);
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    try testing.expectEqual(@as(u32, 1), result.files_analyzed);
    try testing.expectEqual(@as(u32, 0), result.issues_found);
    try testing.expect(!result.hasErrors());
}

test "unit: API: analyzeMemory detects missing defer" {
    const allocator = testing.allocator;
    
    const source =
        \\pub fn leakyFunction() !void {
        \\    const allocator = std.heap.page_allocator;
        \\    const data = try allocator.alloc(u8, 100);
        \\    // Missing defer allocator.free(data);
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "leak.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    try testing.expect(result.issues_found > 0);
    try testing.expect(result.hasErrors());
    
    // Check that we found a missing defer issue
    var found_missing_defer = false;
    for (result.issues) |issue| {
        if (issue.issue_type == .missing_defer) {
            found_missing_defer = true;
            break;
        }
    }
    try testing.expect(found_missing_defer);
}

test "unit: API: analyzeTests with valid test file" {
    const allocator = testing.allocator;
    
    const source =
        \\const std = @import("std");
        \\const testing = std.testing;
        \\
        \\test "unit: module: test description" {
        \\    try testing.expect(true);
        \\}
    ;
    
    const result = try zig_tooling.analyzeTests(allocator, source, "test_module.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    try testing.expectEqual(@as(u32, 1), result.files_analyzed);
    try testing.expectEqual(@as(u32, 0), result.issues_found);
    try testing.expect(!result.hasErrors());
}

test "unit: API: analyzeMemory with allowed_allocators configuration" {
    const allocator = testing.allocator;
    
    const source =
        \\pub fn main() !void {
        \\    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        \\    const allocator = gpa.allocator();
        \\    const data = try allocator.alloc(u8, 100);
        \\    defer allocator.free(data);
        \\    
        \\    // This should trigger a warning since page_allocator is not allowed
        \\    const temp = try std.heap.page_allocator.alloc(u8, 50);
        \\    defer std.heap.page_allocator.free(temp);
        \\}
    ;
    
    const config = zig_tooling.Config{
        .memory = .{
            .allowed_allocators = &.{ "GeneralPurposeAllocator", "std.testing.allocator" },
        },
    };
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", config);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should find one issue about page_allocator not being allowed
    try testing.expect(result.issues_found > 0);
    
    var found_incorrect_allocator = false;
    for (result.issues) |issue| {
        if (issue.issue_type == .incorrect_allocator) {
            found_incorrect_allocator = true;
            break;
        }
    }
    try testing.expect(found_incorrect_allocator);
}

test "unit: API: analyzeMemory allowed_allocators empty list allows all" {
    const allocator = testing.allocator;
    
    const source =
        \\pub fn main() !void {
        \\    // When allowed_allocators is empty, all allocators should be allowed
        \\    const data1 = try std.heap.page_allocator.alloc(u8, 100);
        \\    defer std.heap.page_allocator.free(data1);
        \\    
        \\    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        \\    defer arena.deinit();
        \\    const arena_allocator = arena.allocator();
        \\    const data2 = try arena_allocator.alloc(u8, 50);
        \\    
        \\    const data3 = try std.heap.c_allocator.alloc(u8, 25);
        \\    defer std.heap.c_allocator.free(data3);
        \\}
    ;
    
    const config = zig_tooling.Config{
        .memory = .{
            .allowed_allocators = &.{}, // Empty list means all allocators are allowed
        },
    };
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", config);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should not find any incorrect_allocator issues
    var found_incorrect_allocator = false;
    for (result.issues) |issue| {
        if (issue.issue_type == .incorrect_allocator) {
            found_incorrect_allocator = true;
            break;
        }
    }
    try testing.expect(!found_incorrect_allocator);
}

test "unit: API: analyzeTests detects missing category" {
    const allocator = testing.allocator;
    
    const source =
        \\const std = @import("std");
        \\const testing = std.testing;
        \\
        \\test "missing category in test name" {
        \\    try testing.expect(true);
        \\}
    ;
    
    const result = try zig_tooling.analyzeTests(allocator, source, "test_bad.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    try testing.expect(result.issues_found > 0);
    
    // Check that we found a missing category issue
    var found_issue = false;
    for (result.issues) |issue| {
        if (issue.issue_type == .missing_test_category or issue.issue_type == .invalid_test_naming) {
            found_issue = true;
            break;
        }
    }
    try testing.expect(found_issue);
}

test "unit: API: analyzeFile with non-existent file" {
    const allocator = testing.allocator;
    
    const result = zig_tooling.analyzeFile(allocator, "/non/existent/file.zig", null);
    try testing.expectError(zig_tooling.AnalysisError.FileNotFound, result);
}

test "unit: API: analyzeSource combines both analyzers" {
    const allocator = testing.allocator;
    
    const source =
        \\const std = @import("std");
        \\const testing = std.testing;
        \\
        \\pub fn leakyFunction() !void {
        \\    const allocator = std.heap.page_allocator;
        \\    const data = try allocator.alloc(u8, 100);
        \\    // Missing defer
        \\}
        \\
        \\test "bad test name" {
        \\    try testing.expect(true);
        \\}
    ;
    
    const result = try zig_tooling.analyzeSource(allocator, source, null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should find issues from both analyzers
    try testing.expect(result.issues_found >= 2);
    
    // Check we have both memory and testing issues
    var has_memory_issue = false;
    var has_testing_issue = false;
    
    for (result.issues) |issue| {
        switch (issue.issue_type) {
            .missing_defer, .memory_leak => has_memory_issue = true,
            .missing_test_category, .invalid_test_naming => has_testing_issue = true,
            else => {},
        }
    }
    
    try testing.expect(has_memory_issue);
    try testing.expect(has_testing_issue);
}

test "unit: API: custom configuration" {
    const allocator = testing.allocator;
    
    const source =
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    const data = try allocator.alloc(u8, 100);
        \\    // Missing defer allocator.free(data);
        \\}
    ;
    
    // Test with defer checking disabled
    const config_no_defer = zig_tooling.Config{
        .memory = .{
            .check_defer = false,
        },
    };
    
    const result1 = try zig_tooling.analyzeMemory(allocator, source, "test.zig", config_no_defer);
    defer allocator.free(result1.issues);
    defer for (result1.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should not report missing defer issues when disabled
    for (result1.issues) |issue| {
        try testing.expect(issue.issue_type != .missing_defer);
    }
    
    // Test with default config (defer checking enabled)
    const result2 = try zig_tooling.analyzeMemory(allocator, source, "test.zig", null);
    defer allocator.free(result2.issues);
    defer for (result2.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should report missing defer with default config
    var found_missing_defer = false;
    for (result2.issues) |issue| {
        if (issue.issue_type == .missing_defer) {
            found_missing_defer = true;
        }
    }
    try testing.expect(found_missing_defer);
}

test "unit: API: issue severity levels" {
    const allocator = testing.allocator;
    
    const source =
        \\pub fn main() !void {
        \\    const data = try allocator.alloc(u8, 100);
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Test severity helper methods
    if (result.issues_found > 0) {
        const has_errors = result.hasErrors();
        const has_warnings = result.hasWarnings();
        
        // At least one should be true if we have issues
        try testing.expect(has_errors or has_warnings);
    }
}

test "unit: API: types exports" {
    // Ensure all types are properly exported
    const IssueType = zig_tooling.IssueType;
    const Severity = zig_tooling.Severity;
    
    // Verify enums have expected values
    try testing.expect(@hasField(IssueType, "missing_defer"));
    try testing.expect(@hasField(IssueType, "invalid_test_naming"));
    try testing.expect(@hasField(Severity, "err"));
    try testing.expect(@hasField(Severity, "warning"));
    try testing.expect(@hasField(Severity, "info"));
    
    // Verify types can be constructed
    _ = zig_tooling.Issue;
    _ = zig_tooling.AnalysisResult;
    _ = zig_tooling.Config;
    _ = zig_tooling.MemoryAnalyzer;
    _ = zig_tooling.TestingAnalyzer;
    _ = zig_tooling.ScopeTracker;
}

test "unit: API: testing configuration" {
    const allocator = testing.allocator;
    
    const source =
        \\test "this test has no category" {
        \\    try std.testing.expect(true);
        \\}
    ;
    
    // Test with category enforcement disabled
    const config_no_categories = zig_tooling.Config{
        .testing = .{
            .enforce_categories = false,
        },
    };
    
    const result1 = try zig_tooling.analyzeTests(allocator, source, "test.zig", config_no_categories);
    defer allocator.free(result1.issues);
    defer for (result1.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should not report uncategorized test issues when disabled
    for (result1.issues) |issue| {
        try testing.expect(issue.issue_type != .missing_test_category);
    }
    
    // Test with default config (category enforcement enabled)
    const result2 = try zig_tooling.analyzeTests(allocator, source, "test.zig", null);
    defer allocator.free(result2.issues);
    defer for (result2.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should report uncategorized test with default config
    var found_uncategorized = false;
    for (result2.issues) |issue| {
        if (issue.issue_type == .missing_test_category) {
            found_uncategorized = true;
        }
    }
    try testing.expect(found_uncategorized);
}

test "unit: API: arena allocator variable tracking" {
    const allocator = testing.allocator;
    
    const source =
        \\pub fn main() !void {
        \\    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        \\    defer arena.deinit();
        \\    
        \\    // This pattern should be tracked
        \\    const arena_allocator = arena.allocator();
        \\    
        \\    // This allocation should not require defer because it's arena-managed
        \\    const data1 = try arena_allocator.alloc(u8, 100);
        \\    _ = data1;
        \\    
        \\    // Test another common pattern
        \\    const alloc = arena.allocator();
        \\    const data2 = try alloc.alloc(u8, 200);
        \\    _ = data2;
        \\    
        \\    // Test with temporary arena
        \\    var temp_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        \\    defer temp_arena.deinit();
        \\    const temp_alloc = temp_arena.allocator();
        \\    const data3 = try temp_alloc.alloc(u8, 300);
        \\    _ = data3;
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "arena_test.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // There should be no missing defer issues for arena allocations
    for (result.issues) |issue| {
        if (issue.issue_type == .missing_defer) {
            std.debug.print("Unexpected missing defer issue: {s}\n", .{issue.message});
        }
        try testing.expect(issue.issue_type != .missing_defer);
    }
    
    // The test passes if we have no defer-related issues
    const defer_issues = blk: {
        var count: u32 = 0;
        for (result.issues) |issue| {
            if (issue.issue_type == .missing_defer or issue.issue_type == .missing_errdefer) {
                count += 1;
            }
        }
        break :blk count;
    };
    
    try testing.expectEqual(@as(u32, 0), defer_issues);
}
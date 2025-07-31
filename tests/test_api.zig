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

test "unit: API: analyzeMemory with custom allocator patterns" {
    const allocator = testing.allocator;
    
    const source =
        \\pub fn main() !void {
        \\    // Custom allocator types
        \\    var my_custom_alloc = MyCustomAllocator.init();
        \\    const custom_allocator = my_custom_alloc.allocator();
        \\    const data1 = try custom_allocator.alloc(u8, 100);
        \\    defer custom_allocator.free(data1);
        \\    
        \\    // Pool allocator
        \\    var pool_alloc = PoolAllocator.init();
        \\    const pool = pool_alloc.allocator();
        \\    const data2 = try pool.alloc(u8, 200);
        \\    defer pool.free(data2);
        \\    
        \\    // This should not be allowed
        \\    const data3 = try std.heap.page_allocator.alloc(u8, 50);
        \\    defer std.heap.page_allocator.free(data3);
        \\}
    ;
    
    const config = zig_tooling.Config{
        .memory = .{
            .allowed_allocators = &.{ "MyCustomAllocator", "PoolAllocator" },
            .allocator_patterns = &.{
                .{ .name = "MyCustomAllocator", .pattern = "my_custom_alloc" },
                .{ .name = "PoolAllocator", .pattern = "pool_alloc" },
                .{ .name = "PoolAllocator", .pattern = "pool" },
            },
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
    
    var found_page_allocator_issue = false;
    var found_custom_allocator_issue = false;
    
    for (result.issues) |issue| {
        if (issue.issue_type == .incorrect_allocator) {
            // Should complain about page_allocator
            if (std.mem.indexOf(u8, issue.message, "page_allocator") != null) {
                found_page_allocator_issue = true;
            }
            // Should NOT complain about custom allocators
            if (std.mem.indexOf(u8, issue.message, "MyCustomAllocator") != null or
                std.mem.indexOf(u8, issue.message, "PoolAllocator") != null) {
                found_custom_allocator_issue = true;
            }
        }
    }
    
    try testing.expect(found_page_allocator_issue);
    try testing.expect(!found_custom_allocator_issue);
}

test "unit: API: custom allocator patterns override defaults" {
    const allocator = testing.allocator;
    
    const source =
        \\pub fn main() !void {
        \\    // This contains "arena" but should be detected as CustomArena
        \\    var my_arena_allocator = CustomArenaAllocator.init();
        \\    const arena = my_arena_allocator.allocator();
        \\    const data = try arena.alloc(u8, 100);
        \\    defer arena.free(data);
        \\}
    ;
    
    const config = zig_tooling.Config{
        .memory = .{
            .allowed_allocators = &.{ "CustomArena" },
            .allocator_patterns = &.{
                // This pattern should override the default "arena" pattern
                .{ .name = "CustomArena", .pattern = "my_arena_allocator" },
            },
        },
    };
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", config);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should not find any issues since CustomArena is allowed
    try testing.expect(result.issues_found == 0);
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
    _ = zig_tooling.ScopeTrackerBuilder;
    _ = zig_tooling.ScopeType;
    _ = zig_tooling.ScopeInfo;
    _ = zig_tooling.VariableInfo;
    _ = zig_tooling.ScopeConfig;
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

test "unit: API: analyzeTests category strings survive config deallocation (LC025)" {
    const allocator = testing.allocator;
    
    const source =
        \\const std = @import("std");
        \\const testing = std.testing;
        \\
        \\test "unit: module: test description" {
        \\    try testing.expect(true);
        \\}
        \\
        \\test "integration: database: connection test" {
        \\    try testing.expect(true);
        \\}
        \\
        \\test "e2e: api: full workflow" {
        \\    try testing.expect(true);
        \\}
    ;
    
    // Create a config with custom categories in a scope that will end
    const result = blk: {
        const config = zig_tooling.Config{
            .testing = .{
                .enforce_categories = true,
                .allowed_categories = &[_][]const u8{ "unit", "integration", "e2e" },
            },
        };
        
        // Analyze with the config
        const analysis_result = try zig_tooling.analyzeTests(allocator, source, "test_categories.zig", config);
        
        // Config goes out of scope here, but category strings should survive
        break :blk analysis_result;
    };
    
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Access the analyzer to check test patterns (this would crash if categories weren't copied)
    var analyzer = zig_tooling.TestingAnalyzer.init(allocator);
    defer analyzer.deinit();
    
    try analyzer.analyzeSourceCode("test_categories.zig", source);
    
    // Verify we have 3 tests with proper categories
    try testing.expectEqual(@as(usize, 3), analyzer.tests.items.len);
    
    // Verify categories are properly set and accessible (would crash if not copied)
    const test1 = analyzer.tests.items[0];
    const test2 = analyzer.tests.items[1];
    const test3 = analyzer.tests.items[2];
    
    try testing.expect(test1.category != null);
    try testing.expect(test2.category != null);
    try testing.expect(test3.category != null);
    
    // Verify the actual category values
    try testing.expectEqualStrings("unit", test1.category.?);
    try testing.expectEqualStrings("integration", test2.category.?);
    try testing.expectEqualStrings("e2e", test3.category.?);
    
    // No issues expected since all tests have proper categories
    try testing.expectEqual(@as(u32, 0), result.issues_found);
}

test "LC027: testing analyzer handles long category names without buffer overflow" {
    // Create a very long category name that would overflow the old 256-byte buffer
    const long_category = "very_long_category_name_that_would_definitely_overflow_a_fixed_size_buffer_this_is_intentionally_made_long_to_test_the_dynamic_allocation_fix_for_issue_LC027_where_we_replaced_fixed_buffers_with_dynamic_allocation_to_prevent_buffer_overflows_when_dealing_with_extremely_long_category_names_in_tests";
    
    const config = zig_tooling.Config{
        .testing = .{
            .enforce_categories = true,
            .allowed_categories = &[_][]const u8{ long_category, "unit", "integration" },
        },
    };
    
    const source =
        \\test "very_long_category_name_that_would_definitely_overflow_a_fixed_size_buffer_this_is_intentionally_made_long_to_test_the_dynamic_allocation_fix_for_issue_LC027_where_we_replaced_fixed_buffers_with_dynamic_allocation_to_prevent_buffer_overflows_when_dealing_with_extremely_long_category_names_in_tests: test with extremely long category" {
        \\    try std.testing.expect(true);
        \\}
        \\test "unit: normal test" {
        \\    try std.testing.expect(true);
        \\}
        \\test "missing category test" {
        \\    try std.testing.expect(true);
        \\}
    ;
    
    const result = try zig_tooling.analyzeTests(testing.allocator, source, "test.zig", config);
    defer testing.allocator.free(result.issues);
    defer for (result.issues) |issue| {
        testing.allocator.free(issue.file_path);
        testing.allocator.free(issue.message);
        if (issue.suggestion) |s| testing.allocator.free(s);
    };
    
    // Should have 1 issue (the test without category)
    try testing.expectEqual(@as(u32, 1), result.issues_found);
    
    // Verify the suggestion includes the long category name
    const issue = result.issues[0];
    try testing.expect(issue.suggestion != null);
    
    // The suggestion should contain all three categories including the very long one
    try testing.expect(std.mem.indexOf(u8, issue.suggestion.?, long_category) != null);
    try testing.expect(std.mem.indexOf(u8, issue.suggestion.?, "unit") != null);
    try testing.expect(std.mem.indexOf(u8, issue.suggestion.?, "integration") != null);
}

test "LC028: memory analyzer validates allocator patterns" {
    const source =
        \\const std = @import("std");
        \\pub fn main() !void {
        \\    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        \\    const allocator = gpa.allocator();
        \\}
    ;
    
    // Test 1: Empty pattern name
    {
        const config = zig_tooling.Config{
            .memory = .{
                .allocator_patterns = &[_]zig_tooling.AllocatorPattern{
                    .{ .name = "", .pattern = "test" },
                },
            },
        };
        
        const result = zig_tooling.analyzeMemory(testing.allocator, source, "test.zig", config);
        try testing.expectError(zig_tooling.AnalysisError.EmptyPatternName, result);
    }
    
    // Test 2: Empty pattern string
    {
        const config = zig_tooling.Config{
            .memory = .{
                .allocator_patterns = &[_]zig_tooling.AllocatorPattern{
                    .{ .name = "TestAllocator", .pattern = "" },
                },
            },
        };
        
        const result = zig_tooling.analyzeMemory(testing.allocator, source, "test.zig", config);
        try testing.expectError(zig_tooling.AnalysisError.EmptyPattern, result);
    }
    
    // Test 3: Duplicate pattern names
    {
        const config = zig_tooling.Config{
            .memory = .{
                .allocator_patterns = &[_]zig_tooling.AllocatorPattern{
                    .{ .name = "MyAllocator", .pattern = "my_alloc" },
                    .{ .name = "MyAllocator", .pattern = "different_pattern" },
                },
            },
        };
        
        const result = zig_tooling.analyzeMemory(testing.allocator, source, "test.zig", config);
        try testing.expectError(zig_tooling.AnalysisError.DuplicatePatternName, result);
    }
    
    // Test 4: Single character pattern (should warn but not error)
    {
        const config = zig_tooling.Config{
            .memory = .{
                .allocator_patterns = &[_]zig_tooling.AllocatorPattern{
                    .{ .name = "SingleChar", .pattern = "a" },
                },
            },
        };
        
        const result = try zig_tooling.analyzeMemory(testing.allocator, source, "test.zig", config);
        defer testing.allocator.free(result.issues);
        defer for (result.issues) |issue| {
            testing.allocator.free(issue.file_path);
            testing.allocator.free(issue.message);
            if (issue.suggestion) |s| testing.allocator.free(s);
        };
        
        // Should have at least one warning about the single character pattern
        var found_warning = false;
        for (result.issues) |issue| {
            if (issue.severity == .warning and 
                std.mem.indexOf(u8, issue.message, "single character pattern") != null) {
                found_warning = true;
                break;
            }
        }
        try testing.expect(found_warning);
    }
    
    // Test 5: Pattern name conflicts with default patterns (should warn)
    {
        const config = zig_tooling.Config{
            .memory = .{
                .allocator_patterns = &[_]zig_tooling.AllocatorPattern{
                    .{ .name = "GeneralPurposeAllocator", .pattern = "my_gpa" },
                },
            },
        };
        
        const result = try zig_tooling.analyzeMemory(testing.allocator, source, "test.zig", config);
        defer testing.allocator.free(result.issues);
        defer for (result.issues) |issue| {
            testing.allocator.free(issue.file_path);
            testing.allocator.free(issue.message);
            if (issue.suggestion) |s| testing.allocator.free(s);
        };
        
        // Should have a warning about conflicting with built-in pattern
        var found_warning = false;
        for (result.issues) |issue| {
            if (issue.severity == .warning and 
                std.mem.indexOf(u8, issue.message, "conflicts with built-in pattern") != null) {
                found_warning = true;
                break;
            }
        }
        try testing.expect(found_warning);
    }
    
    // Test 6: Valid custom patterns should work correctly
    {
        const config = zig_tooling.Config{
            .memory = .{
                .allocator_patterns = &[_]zig_tooling.AllocatorPattern{
                    .{ .name = "MyCustomAllocator", .pattern = "custom_alloc" },
                    .{ .name = "MyPoolAllocator", .pattern = "pool_alloc" },
                },
            },
        };
        
        const test_source =
            \\const std = @import("std");
            \\pub fn main() !void {
            \\    var custom_alloc = MyCustomAllocator.init();
            \\    const allocator = custom_alloc.allocator();
            \\    const data = try allocator.alloc(u8, 100);
            \\}
        ;
        
        const result = try zig_tooling.analyzeMemory(testing.allocator, test_source, "test.zig", config);
        defer testing.allocator.free(result.issues);
        defer for (result.issues) |issue| {
            testing.allocator.free(issue.file_path);
            testing.allocator.free(issue.message);
            if (issue.suggestion) |s| testing.allocator.free(s);
        };
        
        // Should have an issue about missing defer, not about pattern validation
        var has_defer_issue = false;
        for (result.issues) |issue| {
            if (std.mem.indexOf(u8, issue.message, "defer") != null) {
                has_defer_issue = true;
                break;
            }
        }
        try testing.expect(has_defer_issue);
    }
}

test "unit: API: ScopeTracker builder pattern" {
    const allocator = testing.allocator;
    
    // Test basic builder usage
    var builder = zig_tooling.ScopeTracker.builder(allocator);
    var tracker = try builder
        .withOwnershipPatterns(&.{ "myCreate", "myAlloc" })
        .withMaxDepth(50)
        .withArenaTracking(true)
        .withDeferTracking(true)
        .build();
    defer tracker.deinit();
    
    // Verify configuration
    const config = tracker.getConfig();
    try testing.expectEqual(@as(u32, 50), config.max_scope_depth);
    try testing.expect(config.track_arena_allocators);
    try testing.expect(config.track_defer_statements);
}

test "unit: API: ScopeTracker lazy parsing" {
    const allocator = testing.allocator;
    
    // Test lazy parsing configuration
    var builder = zig_tooling.ScopeTracker.builder(allocator);
    var tracker = try builder
        .withLazyParsing(true, 1000)
        .build();
    defer tracker.deinit();
    
    const config = tracker.getConfig();
    try testing.expect(config.lazy_parsing);
    try testing.expectEqual(@as(u32, 1000), config.lazy_parsing_threshold);
}

test "unit: API: ScopeTracker public API methods" {
    const allocator = testing.allocator;
    
    var tracker = zig_tooling.ScopeTracker.init(allocator);
    defer tracker.deinit();
    
    const source =
        \\pub fn main() !void {
        \\    const data = try allocator.alloc(u8, 100);
        \\    defer allocator.free(data);
        \\}
        \\
        \\test "unit: test" {
        \\    try testing.expect(true);
        \\}
    ;
    
    try tracker.analyzeSourceCode(source);
    
    // Test getScopes
    const scopes = tracker.getScopes();
    try testing.expect(scopes.len >= 2);
    
    // Test findScopeAtLine
    const scope_at_line_2 = tracker.findScopeAtLine(2);
    try testing.expect(scope_at_line_2 != null);
    
    // Test findScopesByType
    const functions = try tracker.findScopesByType(.function);
    defer functions.deinit();
    try testing.expect(functions.items.len >= 1);
    
    // Test getTestScopes
    const test_scopes = try tracker.getTestScopes();
    defer test_scopes.deinit();
    try testing.expect(test_scopes.items.len >= 1);
    
    // Test getFunctionScopes
    const all_functions = try tracker.getFunctionScopes();
    defer all_functions.deinit();
    try testing.expect(all_functions.items.len >= 2);
    
    // Test getStats
    const stats = tracker.getStats();
    try testing.expect(stats.total_scopes >= 2);
    try testing.expect(stats.function_count >= 1);
    try testing.expect(stats.test_count >= 1);
    try testing.expect(stats.allocations_tracked >= 1);
    try testing.expect(stats.defer_statements >= 1);
}

test "unit: API: ScopeTracker getScopeHierarchy" {
    const allocator = testing.allocator;
    
    var tracker = zig_tooling.ScopeTracker.init(allocator);
    defer tracker.deinit();
    
    const source =
        \\pub fn outer() !void {
        \\    if (true) {
        \\        while (true) {
        \\            const x = 42;
        \\            _ = x;
        \\        }
        \\    }
        \\}
    ;
    
    try tracker.analyzeSourceCode(source);
    
    // Get hierarchy for line 4 (inside while loop)
    const hierarchy = try tracker.getScopeHierarchy(4);
    defer hierarchy.deinit();
    
    // Should have at least 3 scopes: function, if, while
    try testing.expect(hierarchy.items.len >= 3);
    
    // Verify depth ordering (outermost to innermost)
    for (hierarchy.items, 0..) |scope, i| {
        if (i > 0) {
            try testing.expect(scope.depth > hierarchy.items[i - 1].depth);
        }
    }
}

test "unit: API: ScopeTracker variable finding" {
    const allocator = testing.allocator;
    
    var tracker = zig_tooling.ScopeTracker.init(allocator);
    defer tracker.deinit();
    
    const source =
        \\pub fn main() !void {
        \\    const data = try allocator.alloc(u8, 100);
        \\    defer allocator.free(data);
        \\    
        \\    if (true) {
        \\        const inner = data;
        \\        _ = inner;
        \\    }
        \\}
    ;
    
    try tracker.analyzeSourceCode(source);
    
    // Test hasVariableDeferCleanup
    const has_defer = tracker.hasVariableDeferCleanup("data", 5);
    try testing.expect(has_defer);
    
    // Test findVariable
    const var_info = tracker.findVariable("data", 6);
    try testing.expect(var_info != null);
    try testing.expect(var_info.?.has_defer);
}

test "unit: API: ScopeTracker configuration behavior" {
    const allocator = testing.allocator;
    
    const source =
        \\pub fn main() !void {
        \\    const data = try allocator.alloc(u8, 100);
        \\    defer allocator.free(data);
        \\    
        \\    var arena = std.heap.ArenaAllocator.init(allocator);
        \\    defer arena.deinit();
        \\}
    ;
    
    // Test with variable tracking disabled
    {
        var builder = zig_tooling.ScopeTracker.builder(allocator);
        var tracker = try builder
            .withVariableTracking(false)
            .build();
        defer tracker.deinit();
        
        try tracker.analyzeSourceCode(source);
        
        const var_info = tracker.findVariable("data", 3);
        try testing.expect(var_info == null); // Should not track variables
    }
    
    // Test with defer tracking disabled
    {
        var builder = zig_tooling.ScopeTracker.builder(allocator);
        var tracker = try builder
            .withDeferTracking(false)
            .build();
        defer tracker.deinit();
        
        try tracker.analyzeSourceCode(source);
        
        const has_defer = tracker.hasVariableDeferCleanup("data", 3);
        try testing.expect(!has_defer); // Should not track defer statements
    }
    
    // Test with arena tracking disabled
    {
        var builder = zig_tooling.ScopeTracker.builder(allocator);
        var tracker = try builder
            .withArenaTracking(false)
            .build();
        defer tracker.deinit();
        
        try tracker.analyzeSourceCode(source);
        
        const stats = tracker.getStats();
        // Stats should still work even with features disabled
        try testing.expect(stats.total_scopes >= 1);
    }
}

test "unit: API: ScopeTracker custom ownership patterns" {
    const allocator = testing.allocator;
    
    var builder = zig_tooling.ScopeTracker.builder(allocator);
    var tracker = try builder
        .withOwnershipPatterns(&.{ "customCreate", "customMake" })
        .build();
    defer tracker.deinit();
    
    const source =
        \\pub fn customCreate() ![]u8 {
        \\    return try allocator.alloc(u8, 100);
        \\}
        \\
        \\pub fn customMake() ![]u8 {
        \\    return try allocator.alloc(u8, 200);
        \\}
    ;
    
    try tracker.analyzeSourceCode(source);
    
    // Verify custom patterns were applied
    const functions = try tracker.findScopesByType(.function);
    defer functions.deinit();
    
    try testing.expect(functions.items.len >= 2);
    
    // Both functions should be recognized as ownership transfer
    for (functions.items) |func| {
        try testing.expect(std.mem.indexOf(u8, func.name, "custom") != null);
    }
}

test "unit: API: edge case - empty source code" {
    const allocator = testing.allocator;
    
    // Test empty string
    const result1 = try zig_tooling.analyzeSource(allocator, "", null);
    defer allocator.free(result1.issues);
    defer for (result1.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    try testing.expectEqual(@as(u32, 1), result1.files_analyzed);
    try testing.expectEqual(@as(u32, 0), result1.issues_found);
    
    // Test whitespace only
    const result2 = try zig_tooling.analyzeSource(allocator, "   \n  \t  \n", null);
    defer allocator.free(result2.issues);
    defer for (result2.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    try testing.expectEqual(@as(u32, 1), result2.files_analyzed);
    try testing.expectEqual(@as(u32, 0), result2.issues_found);
}

test "unit: API: edge case - very large allocation sizes" {
    const allocator = testing.allocator;
    
    const source =
        \\pub fn hugeMalloc() !void {
        \\    const allocator = std.heap.page_allocator;
        \\    const huge_data = try allocator.alloc(u8, 0xFFFFFFFF);
        \\    defer allocator.free(huge_data);
        \\    
        \\    const zero_data = try allocator.alloc(u8, 0);
        \\    defer allocator.free(zero_data);
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "huge.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should not crash on large numbers
    try testing.expect(result.files_analyzed >= 1);
}

test "unit: API: edge case - deeply nested scopes" {
    const allocator = testing.allocator;
    
    const source =
        \\pub fn deepNesting() !void {
        \\    if (true) {
        \\        while (true) {
        \\            for (0..10) |i| {
        \\                switch (i) {
        \\                    0 => {
        \\                        if (true) {
        \\                            const data = try allocator.alloc(u8, 10);
        \\                            defer allocator.free(data);
        \\                        }
        \\                    },
        \\                    else => {},
        \\                }
        \\            }
        \\            break;
        \\        }
        \\    }
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "deep.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should handle deep nesting gracefully
    try testing.expect(result.files_analyzed >= 1);
    try testing.expect(!result.hasErrors()); // Properly handled defer
}

test "unit: API: edge case - concurrent analysis" {
    const allocator = testing.allocator;
    
    const source =
        \\const std = @import("std");
        \\
        \\pub fn simpleFunction() !void {
        \\    const alloc = std.heap.page_allocator;
        \\    const data = try alloc.alloc(u8, 100);
        \\    defer alloc.free(data);
        \\}
    ;
    
    // Simulate concurrent usage by running multiple analyses
    var results: [5]zig_tooling.AnalysisResult = undefined;
    
    for (&results) |*result| {
        result.* = try zig_tooling.analyzeMemory(allocator, source, "concurrent.zig", null);
    }
    
    defer for (results) |result| {
        if (result.issues.len > 0) {
            for (result.issues) |issue| {
                allocator.free(issue.file_path);
                allocator.free(issue.message);
                if (issue.suggestion) |s| allocator.free(s);
            }
            allocator.free(result.issues);
        }
    };
    
    // All results should be consistent
    for (results) |result| {
        try testing.expectEqual(@as(u32, 1), result.files_analyzed);
        try testing.expect(!result.hasErrors());
    }
}

test "unit: API: error boundary - invalid file path characters" {
    const allocator = testing.allocator;
    
    const source = "pub fn test() void {}";
    
    // Test with various problematic file path characters
    const problematic_paths = [_][]const u8{
        "file\x00with\x00nulls.zig",
        "file\nwith\nnewlines.zig", 
        "file\twith\ttabs.zig",
        "file with spaces.zig",
        "very_long_file_name_that_exceeds_normal_path_limits_to_test_boundary_conditions.zig",
    };
    
    for (problematic_paths) |path| {
        const result = try zig_tooling.analyzeMemory(allocator, source, path, null);
        defer allocator.free(result.issues);
        defer for (result.issues) |issue| {
            allocator.free(issue.file_path);
            allocator.free(issue.message);
            if (issue.suggestion) |s| allocator.free(s);
        };
        
        // Should handle problematic paths gracefully
        try testing.expect(result.files_analyzed >= 1);
    }
}

test "unit: API: performance benchmark - large file analysis" {
    const allocator = testing.allocator;
    
    // Generate a large source file
    var large_source = std.ArrayList(u8).init(allocator);
    defer large_source.deinit();
    
    // Add multiple functions with allocations
    for (0..100) |i| {
        try large_source.writer().print(
            \\pub fn function_{d}() !void {{
            \\    const allocator = std.heap.page_allocator;
            \\    const data_{d} = try allocator.alloc(u8, {d});
            \\    defer allocator.free(data_{d});
            \\}}
            \\
            , .{ i, i, i + 10, i });
    }
    
    // Add test functions
    for (0..50) |i| {
        try large_source.writer().print(
            \\test "unit: function_{d}: test case" {{
            \\    try std.testing.expect(true);
            \\}}
            \\
            , .{i});
    }
    
    const start_time = std.time.nanoTimestamp();
    const result = try zig_tooling.analyzeSource(allocator, large_source.items, null);
    const end_time = std.time.nanoTimestamp();
    
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
    
    // Performance requirement: should complete within reasonable time
    try testing.expect(duration_ms < 1000.0); // 1 second max for large files
    
    // Should find the expected number of items
    try testing.expect(result.files_analyzed >= 1);
    
    std.debug.print("Large file analysis performance: {d:.2}ms for {d} bytes\n", .{ duration_ms, large_source.items.len });
}

test "API: Logging with callback" {
    const allocator = testing.allocator;
    
    // Track log events
    const LogCollector = struct {
        events: std.ArrayList(zig_tooling.LogEvent),
        allocator_inner: std.mem.Allocator,
        
        fn init(alloc: std.mem.Allocator) @This() {
            return .{ 
                .events = std.ArrayList(zig_tooling.LogEvent).init(alloc),
                .allocator_inner = alloc,
            };
        }
        
        fn deinit(self: *@This()) void {
            self.events.deinit();
        }
    };
    
    var collector = LogCollector.init(allocator);
    defer collector.deinit();
    
    const logHandler = struct {
        fn callback(event: zig_tooling.LogEvent) void {
            _ = event;
            // In a real test we'd collect the events, but for simplicity
            // we'll just count them using a global
        }
    }.callback;
    
    // Create config with logging enabled
    const config = zig_tooling.Config{
        .memory = .{
            .check_defer = true,
        },
        .logging = .{
            .enabled = true,
            .callback = logHandler,
            .min_level = .info,
        },
    };
    
    const source =
        \\const std = @import("std");
        \\pub fn main() !void {
        \\    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        \\    const allocator = gpa.allocator();
        \\    const data = try allocator.alloc(u8, 100);
        \\    // Missing defer allocator.free(data);
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", config);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should have detected the missing defer
    try testing.expect(result.issues.len >= 1);
    
    // Test that logging doesn't crash when disabled
    const config_no_log = zig_tooling.Config{
        .memory = .{ .check_defer = true },
        .logging = .{ .enabled = false },
    };
    
    const result2 = try zig_tooling.analyzeMemory(allocator, source, "test.zig", config_no_log);
    defer allocator.free(result2.issues);
    defer for (result2.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should still work without logging
    try testing.expect(result2.issues.len >= 1);
}

// ============================================================================
// Formatter Tests
// ============================================================================

test "unit: formatters: formatAsText basic functionality" {
    const allocator = testing.allocator;
    
    // Create sample analysis result
    const issues = [_]zig_tooling.Issue{
        zig_tooling.Issue{
            .file_path = "test.zig",
            .line = 10,
            .column = 5,
            .issue_type = .missing_defer,
            .severity = .err,
            .message = "Missing defer statement for memory allocation",
            .suggestion = "Add defer allocator.free(ptr);",
            .code_snippet = "const ptr = try allocator.alloc(u8, 100);",
        },
        zig_tooling.Issue{
            .file_path = "other.zig",
            .line = 25,
            .column = 10,
            .issue_type = .incorrect_allocator,
            .severity = .warning,
            .message = "Using non-approved allocator",
            .suggestion = null,
            .code_snippet = null,
        },
    };
    
    const result = zig_tooling.AnalysisResult{
        .issues = &issues,
        .files_analyzed = 2,
        .issues_found = 2,
        .analysis_time_ms = 42,
    };
    
    // Test basic text formatting
    const output = try zig_tooling.formatters.formatAsText(allocator, result, .{ .color = false });
    defer allocator.free(output);
    
    // Check that output contains expected content
    try testing.expect(std.mem.indexOf(u8, output, "test.zig:10:5") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Missing defer statement") != null);
    try testing.expect(std.mem.indexOf(u8, output, "error:") != null);
    try testing.expect(std.mem.indexOf(u8, output, "warning:") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Files analyzed: 2") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Analysis time: 42ms") != null);
}

test "unit: formatters: formatAsText with verbose option" {
    const allocator = testing.allocator;
    
    const issues = [_]zig_tooling.Issue{
        zig_tooling.Issue{
            .file_path = "test.zig",
            .line = 10,
            .column = 5,
            .issue_type = .missing_defer,
            .severity = .err,
            .message = "Missing defer statement",
            .suggestion = "Add defer allocator.free(ptr);",
            .code_snippet = "const ptr = try allocator.alloc(u8, 100);",
        },
    };
    
    const result = zig_tooling.AnalysisResult{
        .issues = &issues,
        .files_analyzed = 1,
        .issues_found = 1,
        .analysis_time_ms = 10,
    };
    
    // Test verbose formatting
    const output = try zig_tooling.formatters.formatAsText(allocator, result, .{ .verbose = true, .color = false });
    defer allocator.free(output);
    
    // Check for verbose content
    try testing.expect(std.mem.indexOf(u8, output, "Issue type: missing_defer") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Code:") != null);
    try testing.expect(std.mem.indexOf(u8, output, "const ptr = try allocator.alloc") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Suggestion: Add defer allocator.free") != null);
}

test "unit: formatters: formatAsText with max_issues limit" {
    const allocator = testing.allocator;
    
    const issues = [_]zig_tooling.Issue{
        zig_tooling.Issue{
            .file_path = "test1.zig",
            .line = 1,
            .column = 1,
            .issue_type = .missing_defer,
            .severity = .err,
            .message = "Error 1",
        },
        zig_tooling.Issue{
            .file_path = "test2.zig",
            .line = 2,
            .column = 2,
            .issue_type = .missing_defer,
            .severity = .err,
            .message = "Error 2",
        },
        zig_tooling.Issue{
            .file_path = "test3.zig",
            .line = 3,
            .column = 3,
            .issue_type = .missing_defer,
            .severity = .err,
            .message = "Error 3",
        },
    };
    
    const result = zig_tooling.AnalysisResult{
        .issues = &issues,
        .files_analyzed = 3,
        .issues_found = 3,
        .analysis_time_ms = 15,
    };
    
    // Test with max_issues = 2
    const output = try zig_tooling.formatters.formatAsText(allocator, result, .{ .max_issues = 2, .color = false });
    defer allocator.free(output);
    
    // Should include first 2 errors but not the third
    try testing.expect(std.mem.indexOf(u8, output, "Error 1") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Error 2") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Error 3") == null);
    try testing.expect(std.mem.indexOf(u8, output, "and 1 more issues") != null);
}

test "unit: formatters: formatAsJson basic functionality" {
    const allocator = testing.allocator;
    
    const issues = [_]zig_tooling.Issue{
        zig_tooling.Issue{
            .file_path = "test.zig",
            .line = 10,
            .column = 5,
            .issue_type = .missing_defer,
            .severity = .warning,
            .message = "Test message",
            .suggestion = "Test suggestion",
        },
    };
    
    const result = zig_tooling.AnalysisResult{
        .issues = &issues,
        .files_analyzed = 1,
        .issues_found = 1,
        .analysis_time_ms = 42,
    };
    
    const output = try zig_tooling.formatters.formatAsJson(allocator, result, .{});
    defer allocator.free(output);
    
    // Check JSON structure
    try testing.expect(std.mem.indexOf(u8, output, "\"file_path\": \"test.zig\"") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\"line\": 10") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\"column\": 5") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\"issue_type\": \"missing_defer\"") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\"severity\": \"warning\"") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\"message\": \"Test message\"") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\"suggestion\": \"Test suggestion\"") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\"metadata\"") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\"files_analyzed\": 1") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\"analysis_time_ms\": 42") != null);
}

test "unit: formatters: formatAsJson with special characters" {
    const allocator = testing.allocator;
    
    const issues = [_]zig_tooling.Issue{
        zig_tooling.Issue{
            .file_path = "test\"with\\quotes.zig",
            .line = 1,
            .column = 1,
            .issue_type = .missing_defer,
            .severity = .err,
            .message = "Message with \"quotes\" and \\backslashes\nand newlines\tand tabs",
        },
    };
    
    const result = zig_tooling.AnalysisResult{
        .issues = &issues,
        .files_analyzed = 1,
        .issues_found = 1,
        .analysis_time_ms = 5,
    };
    
    const output = try zig_tooling.formatters.formatAsJson(allocator, result, .{});
    defer allocator.free(output);
    
    // Check that special characters are properly escaped
    try testing.expect(std.mem.indexOf(u8, output, "\\\"") != null); // Escaped quotes
    try testing.expect(std.mem.indexOf(u8, output, "\\\\") != null); // Escaped backslashes
    try testing.expect(std.mem.indexOf(u8, output, "\\n") != null);  // Escaped newlines
    try testing.expect(std.mem.indexOf(u8, output, "\\t") != null);  // Escaped tabs
}

test "unit: formatters: formatAsJson with control characters" {
    const allocator = testing.allocator;
    
    const issues = [_]zig_tooling.Issue{
        zig_tooling.Issue{
            .file_path = "test.zig",
            .line = 1,
            .column = 1,
            .issue_type = .missing_defer,
            .severity = .err,
            .message = "Control chars: \x00\x01\x02\x08\x0C\x1F",
        },
    };
    
    const result = zig_tooling.AnalysisResult{
        .issues = &issues,
        .files_analyzed = 1,
        .issues_found = 1,
        .analysis_time_ms = 5,
    };
    
    const output = try zig_tooling.formatters.formatAsJson(allocator, result, .{});
    defer allocator.free(output);
    
    // Check that control characters are properly escaped
    try testing.expect(std.mem.indexOf(u8, output, "\\u0000") != null); // NULL
    try testing.expect(std.mem.indexOf(u8, output, "\\u0001") != null); // SOH
    try testing.expect(std.mem.indexOf(u8, output, "\\u0002") != null); // STX
    try testing.expect(std.mem.indexOf(u8, output, "\\b") != null);     // Backspace
    try testing.expect(std.mem.indexOf(u8, output, "\\f") != null);     // Form feed
    try testing.expect(std.mem.indexOf(u8, output, "\\u001F") != null); // Unit separator
}

test "unit: formatters: formatAsGitHubActions with special characters" {
    const allocator = testing.allocator;
    
    const issues = [_]zig_tooling.Issue{
        zig_tooling.Issue{
            .file_path = "file:with,special%chars.zig",
            .line = 10,
            .column = 5,
            .issue_type = .missing_defer,
            .severity = .err,
            .message = "Error: 50% failed\r\nNew line here",
            .suggestion = "Add defer: statement",
        },
    };
    
    const result = zig_tooling.AnalysisResult{
        .issues = &issues,
        .files_analyzed = 1,
        .issues_found = 1,
        .analysis_time_ms = 5,
    };
    
    const output = try zig_tooling.formatters.formatAsGitHubActions(allocator, result, .{ .verbose = true });
    defer allocator.free(output);
    
    // Check that GitHub Actions special characters are properly escaped
    try testing.expect(std.mem.indexOf(u8, output, "file%3Awith%2Cspecial%25chars.zig") != null); // File path escaping
    try testing.expect(std.mem.indexOf(u8, output, "50%25 failed") != null); // % escaping in message
    try testing.expect(std.mem.indexOf(u8, output, "%0D%0ANew line") != null); // \r\n escaping
    try testing.expect(std.mem.indexOf(u8, output, "defer: statement") != null); // : not escaped in message
}

test "unit: formatters: formatAsGitHubActions basic functionality" {
    const allocator = testing.allocator;
    
    const issues = [_]zig_tooling.Issue{
        zig_tooling.Issue{
            .file_path = "src/main.zig",
            .line = 15,
            .column = 8,
            .issue_type = .missing_defer,
            .severity = .err,
            .message = "Memory leak detected",
            .suggestion = "Add defer statement",
        },
        zig_tooling.Issue{
            .file_path = "src/utils.zig",
            .line = 22,
            .column = 12,
            .issue_type = .incorrect_allocator,
            .severity = .warning,
            .message = "Non-standard allocator usage",
        },
    };
    
    const result = zig_tooling.AnalysisResult{
        .issues = &issues,
        .files_analyzed = 2,
        .issues_found = 2,
        .analysis_time_ms = 30,
    };
    
    const output = try zig_tooling.formatters.formatAsGitHubActions(allocator, result, .{});
    defer allocator.free(output);
    
    // Check GitHub Actions annotation format
    try testing.expect(std.mem.indexOf(u8, output, "::error file=src/main.zig,line=15,col=8::Memory leak detected") != null);
    try testing.expect(std.mem.indexOf(u8, output, "::warning file=src/utils.zig,line=22,col=12::Non-standard allocator usage") != null);
    try testing.expect(std.mem.indexOf(u8, output, "::notice::Analysis completed") != null);
    try testing.expect(std.mem.indexOf(u8, output, "1 errors, 1 warnings") != null);
}

test "unit: formatters: formatAsGitHubActions with verbose option" {
    const allocator = testing.allocator;
    
    const issues = [_]zig_tooling.Issue{
        zig_tooling.Issue{
            .file_path = "test.zig",
            .line = 10,
            .column = 5,
            .issue_type = .missing_defer,
            .severity = .err,
            .message = "Missing defer",
            .suggestion = "Add defer statement",
        },
    };
    
    const result = zig_tooling.AnalysisResult{
        .issues = &issues,
        .files_analyzed = 1,
        .issues_found = 1,
        .analysis_time_ms = 10,
    };
    
    const output = try zig_tooling.formatters.formatAsGitHubActions(allocator, result, .{ .verbose = true });
    defer allocator.free(output);
    
    // Check for verbose content in annotations
    try testing.expect(std.mem.indexOf(u8, output, "[type: missing_defer]") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Suggestion: Add defer statement") != null);
}

test "unit: formatters: customFormatter functionality" {
    const allocator = testing.allocator;
    
    const TestFormatter = struct {
        fn format(
            alloc: std.mem.Allocator,
            result: zig_tooling.AnalysisResult,
            options: zig_tooling.formatters.FormatOptions,
        ) ![]const u8 {
            _ = options;
            return try std.fmt.allocPrint(alloc, "Custom: {} issues in {} files", .{ result.issues_found, result.files_analyzed });
        }
    };
    
    const result = zig_tooling.AnalysisResult{
        .issues = &[_]zig_tooling.Issue{},
        .files_analyzed = 3,
        .issues_found = 7,
        .analysis_time_ms = 20,
    };
    
    const formatter = zig_tooling.formatters.customFormatter(TestFormatter.format);
    const output = try formatter.format(allocator, result, .{});
    defer allocator.free(output);
    
    try testing.expectEqualStrings("Custom: 7 issues in 3 files", output);
}

test "unit: formatters: detectFormat utility function" {
    // Test JSON detection
    try testing.expect(zig_tooling.formatters.detectFormat("output.json") == .json);
    try testing.expect(zig_tooling.formatters.detectFormat("results.json") == .json);
    
    // Test text detection
    try testing.expect(zig_tooling.formatters.detectFormat("output.txt") == .text);
    try testing.expect(zig_tooling.formatters.detectFormat("analysis.log") == .text);
    
    // Test GitHub Actions detection
    try testing.expect(zig_tooling.formatters.detectFormat("github-output") == .github_actions);
    try testing.expect(zig_tooling.formatters.detectFormat("actions-log") == .github_actions);
    
    // Test no match
    try testing.expect(zig_tooling.formatters.detectFormat("unknown.xyz") == null);
    try testing.expect(zig_tooling.formatters.detectFormat("") == null);
}

test "unit: formatters: FormatOptions different configurations" {
    const allocator = testing.allocator;
    
    const issues = [_]zig_tooling.Issue{
        zig_tooling.Issue{
            .file_path = "test.zig",
            .line = 1,
            .column = 1,
            .issue_type = .missing_defer,
            .severity = .err,
            .message = "Test error",
        },
    };
    
    const result = zig_tooling.AnalysisResult{
        .issues = &issues,
        .files_analyzed = 1,
        .issues_found = 1,
        .analysis_time_ms = 5,
    };
    
    // Test without stats
    const output_no_stats = try zig_tooling.formatters.formatAsText(allocator, result, .{ 
        .include_stats = false, 
        .color = false 
    });
    defer allocator.free(output_no_stats);
    
    try testing.expect(std.mem.indexOf(u8, output_no_stats, "Analysis Results") == null);
    try testing.expect(std.mem.indexOf(u8, output_no_stats, "Files analyzed") == null);
    
    // Test with custom JSON indent
    const output_json = try zig_tooling.formatters.formatAsJson(allocator, result, .{ 
        .json_indent = 4 
    });
    defer allocator.free(output_json);
    
    // Should have 4-space indentation
    try testing.expect(std.mem.indexOf(u8, output_json, "    \"metadata\"") != null);
}

test "unit: formatters: empty result handling" {
    const allocator = testing.allocator;
    
    const result = zig_tooling.AnalysisResult{
        .issues = &[_]zig_tooling.Issue{},
        .files_analyzed = 1,
        .issues_found = 0,
        .analysis_time_ms = 5,
    };
    
    // Test text formatter with no issues
    const text_output = try zig_tooling.formatters.formatAsText(allocator, result, .{ .color = false });
    defer allocator.free(text_output);
    try testing.expect(std.mem.indexOf(u8, text_output, "No issues found! ✓") != null);
    
    // Test JSON formatter with no issues
    const json_output = try zig_tooling.formatters.formatAsJson(allocator, result, .{});
    defer allocator.free(json_output);
    try testing.expect(std.mem.indexOf(u8, json_output, "\"issues\": []") != null);
    
    // Test GitHub Actions formatter with no issues (should be minimal output)
    const gh_output = try zig_tooling.formatters.formatAsGitHubActions(allocator, result, .{});
    defer allocator.free(gh_output);
    try testing.expect(std.mem.indexOf(u8, gh_output, "0 errors, 0 warnings") != null);
}

test "unit: formatters: AnalysisOptions integration with analysis" {
    const allocator = testing.allocator;
    
    const source = 
        \\pub fn main() !void {
        \\    const allocator = std.heap.page_allocator;
        \\    const data1 = try allocator.alloc(u8, 100); // Missing defer
        \\    const data2 = try allocator.alloc(u8, 200); // Missing defer
        \\    const data3 = try allocator.alloc(u8, 300); // Missing defer
        \\}
    ;
    
    // Test with max_issues limit
    const config_limited = zig_tooling.Config{
        .options = .{
            .max_issues = 2,
            .verbose = true,
        },
    };
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", config_limited);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should be limited to 2 issues despite having 3 missing defers
    try testing.expect(result.issues.len <= 2);
    
    // Test formatting the limited result
    const output = try zig_tooling.formatters.formatAsText(allocator, result, .{ .color = false });
    defer allocator.free(output);
    
    // Should contain the limited issues
    try testing.expect(std.mem.indexOf(u8, output, "test.zig") != null);
}

test "LC057: Function context parsing memory safety" {
    const allocator = testing.allocator;
    
    // This test verifies that parseFunctionSignature and findFunctionContext
    // properly manage memory when parsing function signatures
    const source = 
        \\fn simpleFunction() void {}
        \\pub fn allocFunction() !void {
        \\    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        \\    const allocator = gpa.allocator();
        \\    const data = try allocator.alloc(u8, 100);
        \\}
        \\fn errorFunction() !MyError {}
        \\// This is a comment with fn in it
        \\const fn_ptr = struct { fn call() void {} };
    ;
    
    // This should not crash with segfault (LC057)
    const result = try zig_tooling.analyzeMemory(allocator, source, "test_lc057.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should find at least one missing defer issue
    try testing.expect(result.hasErrors());
    
    // Verify issue is for the allocation
    var found_missing_defer = false;
    for (result.issues) |issue| {
        if (issue.issue_type == .missing_defer) {
            found_missing_defer = true;
            break;
        }
    }
    try testing.expect(found_missing_defer);
}

test "unit: API: LC069: disable default patterns configuration" {
    const allocator = testing.allocator;
    
    const source =
        \\const std = @import("std");
        \\test "test" {
        \\    const allocator = std.testing.allocator;
        \\    const data = try allocator.alloc(u8, 100);
        \\}
    ;
    
    // Test with default patterns disabled
    const config = zig_tooling.Config{
        .memory = .{
            .use_default_patterns = false,
            .allowed_allocators = &.{ "UnknownAllocator" },
        },
    };
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", config);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should treat std.testing.allocator as unknown since defaults are disabled
    var found_allocator_issue = false;
    for (result.issues) |issue| {
        if (issue.issue_type == .incorrect_allocator) {
            found_allocator_issue = true;
            // Should mention the exact string as unknown
            try testing.expect(std.mem.indexOf(u8, issue.message, "std.testing.allocator") != null);
        }
    }
    try testing.expect(found_allocator_issue);
}

test "unit: API: LC069: selective default pattern disable" {
    const allocator = testing.allocator;
    
    const source =
        \\const std = @import("std");
        \\test "test" {
        \\    const allocator1 = std.testing.allocator;
        \\    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        \\    const allocator2 = gpa.allocator();
        \\    
        \\    const data1 = try allocator1.alloc(u8, 100);
        \\    const data2 = try allocator2.alloc(u8, 100);
        \\}
    ;
    
    // Disable std.testing.allocator but keep GeneralPurposeAllocator
    const config = zig_tooling.Config{
        .memory = .{
            .disabled_default_patterns = &.{ "std.testing.allocator" },
            .allowed_allocators = &.{ "GeneralPurposeAllocator" },
        },
    };
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", config);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should have one incorrect allocator (std.testing.allocator disabled)
    // and two missing defer warnings
    var incorrect_allocator_count: u32 = 0;
    var missing_defer_count: u32 = 0;
    
    for (result.issues) |issue| {
        switch (issue.issue_type) {
            .incorrect_allocator => incorrect_allocator_count += 1,
            .missing_defer => missing_defer_count += 1,
            else => {},
        }
    }
    
    try testing.expectEqual(@as(u32, 1), incorrect_allocator_count);
    try testing.expectEqual(@as(u32, 2), missing_defer_count);
}

// Tests for LC068 - Ownership Transfer Detection

test "LC068: ownership transfer - immediate return" {
    const allocator = testing.allocator;
    
    // Function that immediately returns allocated memory
    const source =
        \\pub fn createBuffer(allocator: std.mem.Allocator) ![]u8 {
        \\    return try allocator.alloc(u8, 100);
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should not report missing defer for ownership transfer
    for (result.issues) |issue| {
        if (issue.issue_type == .missing_defer) {
            std.debug.print("Unexpected missing defer issue: {s}\n", .{issue.message});
        }
        try testing.expect(issue.issue_type != .missing_defer);
    }
}

test "LC068: ownership transfer - with errdefer" {
    const allocator = testing.allocator;
    
    // Function that properly handles errors with errdefer
    const source =
        \\pub fn createWithErrdefer(allocator: std.mem.Allocator) ![]u8 {
        \\    const buffer = try allocator.alloc(u8, 100);
        \\    errdefer allocator.free(buffer);
        \\    
        \\    // Some operation that might fail
        \\    try doSomething();
        \\    
        \\    return buffer;
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should not report missing defer or errdefer for ownership transfer
    for (result.issues) |issue| {
        if (issue.issue_type == .missing_defer or issue.issue_type == .missing_errdefer) {
            std.debug.print("Unexpected issue: {s}\n", .{issue.message});
        }
        try testing.expect(issue.issue_type != .missing_defer);
        try testing.expect(issue.issue_type != .missing_errdefer);
    }
}

test "LC068: ownership transfer - stored and returned later" {
    const allocator = testing.allocator;
    
    // Function that stores allocation in variable and returns it later
    const source =
        \\pub fn createAndProcess(allocator: std.mem.Allocator) ![]u8 {
        \\    const buffer = try allocator.alloc(u8, 100);
        \\    errdefer allocator.free(buffer);
        \\    
        \\    // Process the buffer
        \\    for (buffer) |*byte| {
        \\        byte.* = 0;
        \\    }
        \\    
        \\    return buffer;
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should not report missing defer for ownership transfer
    for (result.issues) |issue| {
        try testing.expect(issue.issue_type != .missing_defer);
    }
}

test "LC068: ownership transfer - function name patterns" {
    const allocator = testing.allocator;
    
    // Functions with common ownership transfer names
    const source =
        \\pub fn createData(allocator: std.mem.Allocator) []u8 {
        \\    const data = allocator.alloc(u8, 100) catch unreachable;
        \\    return data;
        \\}
        \\
        \\pub fn makeString(allocator: std.mem.Allocator) []u8 {
        \\    const str = allocator.alloc(u8, 50) catch unreachable;
        \\    return str;
        \\}
        \\
        \\pub fn initBuffer(allocator: std.mem.Allocator) []u8 {
        \\    const buf = allocator.alloc(u8, 200) catch unreachable;
        \\    return buf;
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should not report missing defer for functions with ownership transfer names
    for (result.issues) |issue| {
        try testing.expect(issue.issue_type != .missing_defer);
    }
}

test "LC068: ownership transfer - complex return types" {
    const allocator = testing.allocator;
    
    // Functions with various return types
    const source =
        \\pub fn optionalAlloc(allocator: std.mem.Allocator) ?[]u8 {
        \\    const data = allocator.alloc(u8, 100) catch return null;
        \\    return data;
        \\}
        \\
        \\pub fn errorUnionAlloc(allocator: std.mem.Allocator) anyerror![]u8 {
        \\    const data = try allocator.alloc(u8, 100);
        \\    return data;
        \\}
        \\
        \\pub fn pointerReturn(allocator: std.mem.Allocator) !*MyStruct {
        \\    const ptr = try allocator.create(MyStruct);
        \\    return ptr;
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should not report missing defer for ownership transfer return types
    for (result.issues) |issue| {
        try testing.expect(issue.issue_type != .missing_defer);
    }
}

test "LC068: ownership transfer - custom patterns" {
    const allocator = testing.allocator;
    
    // Function that doesn't match default patterns
    const source =
        \\pub fn getBuffer(allocator: std.mem.Allocator) ![]u8 {
        \\    const buffer = try allocator.alloc(u8, 100);
        \\    return buffer;
        \\}
    ;
    
    // Configure custom ownership patterns
    const config = zig_tooling.Config{
        .memory = .{
            .ownership_patterns = &.{
                .{ .function_pattern = "get", .description = "Custom getter pattern" },
            },
        },
    };
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", config);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should not report missing defer with custom pattern
    for (result.issues) |issue| {
        try testing.expect(issue.issue_type != .missing_defer);
    }
}

test "LC068: ownership transfer - should still require defer when not returning" {
    const allocator = testing.allocator;
    
    // Function that allocates but doesn't return the allocation
    const source =
        \\pub fn processData(allocator: std.mem.Allocator) !void {
        \\    const buffer = try allocator.alloc(u8, 100);
        \\    // Missing defer - this should still be flagged
        \\    doSomethingWithBuffer(buffer);
        \\}
        \\
        \\pub fn createButReturnVoid(allocator: std.mem.Allocator) !void {
        \\    const data = try allocator.alloc(u8, 50);
        \\    // Missing defer - even though function name has "create"
        \\    // it doesn't return the allocation
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should report missing defer for allocations not returned
    var missing_defer_count: u32 = 0;
    for (result.issues) |issue| {
        if (issue.issue_type == .missing_defer) {
            missing_defer_count += 1;
        }
    }
    try testing.expectEqual(@as(u32, 2), missing_defer_count);
}

test "LC068: ownership transfer - struct initialization pattern" {
    const allocator = testing.allocator;
    
    // Function that returns struct with allocated field
    const source =
        \\const MyStruct = struct {
        \\    data: []u8,
        \\    size: usize,
        \\};
        \\
        \\pub fn createStruct(allocator: std.mem.Allocator) !MyStruct {
        \\    const buffer = try allocator.alloc(u8, 100);
        \\    errdefer allocator.free(buffer);
        \\    
        \\    return MyStruct{
        \\        .data = buffer,
        \\        .size = 100,
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
    
    // Should not report missing defer for ownership transfer via struct
    for (result.issues) |issue| {
        try testing.expect(issue.issue_type != .missing_defer);
    }
}

test "LC072: getMigrationHistory ownership transfer example" {
    const allocator = testing.allocator;
    
    // This test replicates the exact pattern from GitHub issue #2
    const source =
        \\pub fn getMigrationHistory(allocator: std.mem.Allocator) ![]Migration {
        \\    const data = try allocator.alloc(Migration, 10);
        \\    errdefer allocator.free(data);
        \\    
        \\    // Process migrations...
        \\    return data;
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should not report missing defer for getMigrationHistory function (starts with "get")
    for (result.issues) |issue| {
        try testing.expect(issue.issue_type != .missing_defer);
    }
}

test "LC072: get function pattern detection" {
    const allocator = testing.allocator;
    
    // Test various "get" function patterns
    const source =
        \\pub fn getBuffer(allocator: std.mem.Allocator) ![]u8 {
        \\    return try allocator.alloc(u8, 100);
        \\}
        \\
        \\pub fn getData(allocator: std.mem.Allocator) ![]const u8 {
        \\    const buffer = try allocator.alloc(u8, 50);
        \\    errdefer allocator.free(buffer);
        \\    // Process buffer...
        \\    return buffer;
        \\}
        \\
        \\pub fn getConfig(allocator: std.mem.Allocator) !*Config {
        \\    return try allocator.create(Config);
        \\}
    ;
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should not report missing defer for any of these "get" functions
    for (result.issues) |issue| {
        try testing.expect(issue.issue_type != .missing_defer);
    }
}

test "LC072: array element struct field assignment - initialization" {
    const allocator = testing.allocator;
    
    // Test pattern: result[i] = Struct{ .field = allocation }
    const source =
        \\pub fn buildArray(allocator: std.mem.Allocator) ![]Item {
        \\    var result = try allocator.alloc(Item, 10);
        \\    errdefer allocator.free(result);
        \\    
        \\    for (result, 0..) |*item, i| {
        \\        const data = try allocator.alloc(u8, 100);
        \\        result[i] = Item{ .data = data, .len = 100 };
        \\    }
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
    
    // Should not report missing defer for allocation assigned to array element struct field
    var found_missing_defer = false;
    for (result.issues) |issue| {
        if (issue.issue_type == .missing_defer and std.mem.indexOf(u8, issue.message, "data") != null) {
            found_missing_defer = true;
        }
    }
    try testing.expect(!found_missing_defer);
}

test "LC072: array element struct field assignment - direct assignment" {
    const allocator = testing.allocator;
    
    // Test pattern: result[i].field = allocation
    const source =
        \\pub fn initializeArray(allocator: std.mem.Allocator) ![]Item {
        \\    var result = try allocator.alloc(Item, 10);
        \\    errdefer allocator.free(result);
        \\    
        \\    for (result, 0..) |*item, i| {
        \\        const data = try allocator.alloc(u8, 100);
        \\        result[i].data = data;
        \\        result[i].len = 100;
        \\    }
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
    
    // Should not report missing defer for allocation assigned directly to array element field
    var found_missing_defer = false;
    for (result.issues) |issue| {
        if (issue.issue_type == .missing_defer and std.mem.indexOf(u8, issue.message, "data") != null) {
            found_missing_defer = true;
        }
    }
    try testing.expect(!found_missing_defer);
}

test "LC072: struct field assignment - general case" {
    const allocator = testing.allocator;
    
    // Test general struct field assignment patterns
    const source =
        \\pub fn createStruct(allocator: std.mem.Allocator) !MyStruct {
        \\    var result: MyStruct = undefined;
        \\    
        \\    const buffer = try allocator.alloc(u8, 100);
        \\    result.buffer = buffer;
        \\    result.len = 100;
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
    
    // Should not report missing defer for allocation assigned to struct field
    var found_missing_defer = false;
    for (result.issues) |issue| {
        if (issue.issue_type == .missing_defer and std.mem.indexOf(u8, issue.message, "buffer") != null) {
            found_missing_defer = true;
        }
    }
    try testing.expect(!found_missing_defer);
}

test "LC086: function parameter allocator - basic case" {
    const allocator = testing.allocator;
    
    // Test that function parameter named 'allocator' is not flagged
    const source =
        \\pub fn processData(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
        \\    const result = try allocator.alloc(u8, data.len * 2);
        \\    defer allocator.free(result);
        \\    // Process data...
        \\    return result;
        \\}
    ;
    
    const config = zig_tooling.Config{
        .memory = .{
            .allowed_allocators = &.{"std.heap.page_allocator", "std.testing.allocator"},
        },
    };
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", config);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should not find any incorrect_allocator issues for parameter
    for (result.issues) |issue| {
        if (issue.issue_type == .incorrect_allocator) {
            try testing.expect(false); // Fail if we find incorrect_allocator issue
        }
    }
}

test "LC086: multiple parameters including allocator" {
    const allocator = testing.allocator;
    
    const source =
        \\pub fn createBuffer(allocator: std.mem.Allocator, size: usize, initial_value: u8) ![]u8 {
        \\    const buffer = try allocator.alloc(u8, size);
        \\    errdefer allocator.free(buffer);
        \\    @memset(buffer, initial_value);
        \\    return buffer;
        \\}
        \\
        \\pub fn copyData(dest_allocator: std.mem.Allocator, src: []const u8) ![]u8 {
        \\    return try dest_allocator.dupe(u8, src);
        \\}
    ;
    
    const config = zig_tooling.Config{
        .memory = .{
            .allowed_allocators = &.{"std.heap.page_allocator"},
        },
    };
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", config);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should not flag 'allocator' or 'dest_allocator' parameters
    for (result.issues) |issue| {
        if (issue.issue_type == .incorrect_allocator) {
            // Check that the issue is not about parameter allocators
            try testing.expect(std.mem.indexOf(u8, issue.message, "allocator") == null or
                              std.mem.indexOf(u8, issue.message, "dest_allocator") == null);
        }
    }
}

test "LC086: method with self and allocator parameters" {
    const allocator = testing.allocator;
    
    const source =
        \\const MyStruct = struct {
        \\    data: []u8,
        \\    
        \\    pub fn init(self: *MyStruct, allocator: std.mem.Allocator, size: usize) !void {
        \\        self.data = try allocator.alloc(u8, size);
        \\    }
        \\    
        \\    pub fn deinit(self: *MyStruct, allocator: std.mem.Allocator) void {
        \\        allocator.free(self.data);
        \\    }
        \\};
    ;
    
    const config = zig_tooling.Config{
        .memory = .{
            .allowed_allocators = &.{"gpa.allocator()"},
        },
    };
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", config);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should not flag parameter allocators in methods
    var found_incorrect_allocator = false;
    for (result.issues) |issue| {
        if (issue.issue_type == .incorrect_allocator) {
            found_incorrect_allocator = true;
        }
    }
    try testing.expect(!found_incorrect_allocator);
}

test "LC086: distinguish parameter from local variable" {
    const allocator = testing.allocator;
    
    const source =
        \\pub fn example(allocator: std.mem.Allocator) !void {
        \\    // Parameter allocator should not be flagged
        \\    const data1 = try allocator.alloc(u8, 100);
        \\    defer allocator.free(data1);
        \\    
        \\    // But this local allocator should be flagged
        \\    const page_allocator = std.heap.page_allocator;
        \\    const data2 = try page_allocator.alloc(u8, 100);
        \\    defer page_allocator.free(data2);
        \\}
    ;
    
    const config = zig_tooling.Config{
        .memory = .{
            .allowed_allocators = &.{"std.testing.allocator"},
        },
    };
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", config);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should find exactly one incorrect_allocator issue for page_allocator
    var incorrect_allocator_count: u32 = 0;
    for (result.issues) |issue| {
        if (issue.issue_type == .incorrect_allocator) {
            incorrect_allocator_count += 1;
            // Verify it's about page_allocator, not the parameter
            try testing.expect(std.mem.indexOf(u8, issue.message, "page_allocator") != null);
        }
    }
    try testing.expectEqual(@as(u32, 1), incorrect_allocator_count);
}

test "LC086: generic function with allocator parameter" {
    const allocator = testing.allocator;
    
    const source =
        \\pub fn genericCreate(comptime T: type, allocator: std.mem.Allocator) !*T {
        \\    const ptr = try allocator.create(T);
        \\    ptr.* = std.mem.zeroes(T);
        \\    return ptr;
        \\}
        \\
        \\pub fn genericDestroy(comptime T: type, allocator: std.mem.Allocator, ptr: *T) void {
        \\    allocator.destroy(ptr);
        \\}
    ;
    
    const config = zig_tooling.Config{
        .memory = .{
            .allowed_allocators = &.{"arena.allocator()"},
        },
    };
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", config);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Should not flag allocator parameters in generic functions
    for (result.issues) |issue| {
        try testing.expect(issue.issue_type != .incorrect_allocator);
    }
}
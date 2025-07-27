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
                .allocator_patterns = &[_]@import("../src/types.zig").AllocatorPattern{
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
                .allocator_patterns = &[_]@import("../src/types.zig").AllocatorPattern{
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
                .allocator_patterns = &[_]@import("../src/types.zig").AllocatorPattern{
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
                .allocator_patterns = &[_]@import("../src/types.zig").AllocatorPattern{
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
                .allocator_patterns = &[_]@import("../src/types.zig").AllocatorPattern{
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
                .allocator_patterns = &[_]@import("../src/types.zig").AllocatorPattern{
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
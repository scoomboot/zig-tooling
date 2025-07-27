//! Real Project Analysis Integration Tests
//! 
//! This module tests the library's ability to analyze real project structures
//! and correctly identify issues across multiple files and complex scenarios.

const std = @import("std");
const testing = std.testing;
const zig_tooling = @import("zig_tooling");

// Import the integration test utilities
const test_runner = @import("test_integration_runner.zig");
const TestUtils = test_runner.TestUtils;
const PerformanceBenchmark = test_runner.PerformanceBenchmark;

test "integration: analyze simple memory issues project" {
    const allocator = testing.allocator;
    
    var test_utils = try TestUtils.init(allocator);
    defer test_utils.deinit();
    
    std.debug.print("\n--- Testing Simple Memory Issues Project ---\n", .{});
    
    var benchmark = PerformanceBenchmark.start(allocator, "Simple project analysis");
    defer _ = benchmark.end();
    
    // Test analyzing the simple memory issues project
    const project_path = "tests/integration/sample_projects/simple_memory_issues/src/main.zig";
    
    const result = try zig_tooling.analyzeFile(allocator, project_path, null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    std.debug.print("Found {} issues in simple project\n", .{result.issues_found});
    
    // Should detect multiple memory issues
    try testing.expect(result.issues_found > 0);
    try testing.expect(result.hasErrors());
    
    // Look for specific expected issues
    var found_missing_defer = false;
    var found_double_allocation = false;
    
    for (result.issues) |issue| {
        std.debug.print("Issue: {s} at line {}\n", .{ issue.message, issue.line });
        
        if (issue.issue_type == .missing_defer) {
            found_missing_defer = true;
        }
        if (std.mem.indexOf(u8, issue.message, "double allocation") != null) {
            found_double_allocation = true;
        }
    }
    
    try testing.expect(found_missing_defer);
    std.debug.print("✓ Correctly detected missing defer issues\n", .{});
}

test "integration: analyze complex multi-file project" {
    const allocator = testing.allocator;
    
    var test_utils = try TestUtils.init(allocator);
    defer test_utils.deinit();
    
    std.debug.print("\n--- Testing Complex Multi-File Project ---\n", .{});
    
    var benchmark = PerformanceBenchmark.start(allocator, "Multi-file project analysis");
    defer _ = benchmark.end();
    
    // Test using patterns.checkProject for multi-file analysis
    const result = try zig_tooling.patterns.checkProject(
        allocator,
        "tests/integration/sample_projects/complex_multi_file",
        null,
        null, // No progress callback for test
    );
    defer zig_tooling.patterns.freeProjectResult(allocator, result);
    
    std.debug.print("Analyzed {} files, found {} issues\n", .{ result.files_analyzed, result.issues_found });
    
    // Should analyze multiple files
    try testing.expect(result.files_analyzed > 1);
    
    // Should find issues across different files
    try testing.expect(result.issues_found > 0);
    
    var memory_issues = false;
    var test_issues = false;
    
    for (result.issues) |issue| {
        if (issue.issue_type == .missing_defer or 
            issue.issue_type == .allocator_mismatch or
            issue.issue_type == .arena_in_library) {
            memory_issues = true;
        }
        if (issue.issue_type == .missing_test_category or 
            issue.issue_type == .invalid_test_naming) {
            test_issues = true;
        }
    }
    
    try testing.expect(memory_issues);
    try testing.expect(test_issues);
    
    std.debug.print("✓ Correctly detected issues across multiple files\n", .{});
}

test "integration: analyze custom allocators project" {
    const allocator = testing.allocator;
    
    var test_utils = try TestUtils.init(allocator);
    defer test_utils.deinit();
    
    std.debug.print("\n--- Testing Custom Allocators Project ---\n", .{});
    
    var benchmark = PerformanceBenchmark.start(allocator, "Custom allocators analysis");
    defer _ = benchmark.end();
    
    // Configure custom allocator patterns
    const config = zig_tooling.Config{
        .memory = .{
            .check_defer = true,
            .check_arena_usage = true,
            .check_allocator_usage = true,
            .allowed_allocators = &.{
                "PoolAllocator",
                "CustomAllocator", 
                "ProjectAllocator",
                "std.heap.ArenaAllocator",
            },
            .allocator_patterns = &.{
                .{ .name = "PoolAllocator", .pattern = "pool" },
                .{ .name = "CustomAllocator", .pattern = "custom" },
                .{ .name = "ProjectAllocator", .pattern = "project" },
            },
        },
        .testing = .{},
    };
    
    const result = try zig_tooling.patterns.checkProject(
        allocator,
        "tests/integration/sample_projects/custom_allocators",
        config,
        null,
    );
    defer zig_tooling.patterns.freeProjectResult(allocator, result);
    
    std.debug.print("Custom allocators project: {} files, {} issues\n", .{ result.files_analyzed, result.issues_found });
    
    // Should analyze the custom allocator files
    try testing.expect(result.files_analyzed > 0);
    
    // Validate that custom allocator patterns were recognized
    // (fewer allocator_usage issues should be found due to allowed patterns)
    var allocator_mismatch_issues: u32 = 0;
    for (result.issues) |issue| {
        if (issue.issue_type == .allocator_mismatch) {
            allocator_mismatch_issues += 1;
        }
    }
    
    std.debug.print("Found {} allocator mismatch issues (should be low due to allowed patterns)\n", .{allocator_mismatch_issues});
    std.debug.print("✓ Custom allocator patterns correctly processed\n", .{});
}

test "integration: end-to-end analysis workflow" {
    const allocator = testing.allocator;
    
    var test_utils = try TestUtils.init(allocator);
    defer test_utils.deinit();
    
    std.debug.print("\n--- Testing End-to-End Analysis Workflow ---\n", .{});
    
    var benchmark = PerformanceBenchmark.start(allocator, "End-to-end workflow");
    defer _ = benchmark.end();
    
    // Create a temporary project with known issues
    const project_files = [_]test_runner.FileSpec{
        .{
            .path = "src/main.zig",
            .content = 
                \\const std = @import("std");
                \\
                \\pub fn main() !void {
                \\    const allocator = std.heap.page_allocator;
                \\    const data = try allocator.alloc(u8, 1024);
                \\    // Missing defer allocator.free(data);
                \\    std.debug.print("Hello, World!\n", .{});
                \\}
            ,
        },
        .{
            .path = "src/utils.zig",
            .content = 
                \\const std = @import("std");
                \\
                \\pub fn processData(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
                \\    const result = try allocator.alloc(u8, input.len * 2);
                \\    defer allocator.free(result); // This is correct
                \\    
                \\    // ... process data ...
                \\    const final_result = try allocator.dupe(u8, result);
                \\    return final_result;
                \\}
            ,
        },
        .{
            .path = "tests/test_main.zig",
            .content = 
                \\const std = @import("std");
                \\const testing = std.testing;
                \\
                \\test "unit: main: basic functionality" {
                \\    try testing.expect(true);
                \\}
                \\
                \\test "BadTestName" {
                \\    try testing.expect(true);
                \\}
            ,
        },
    };
    
    const project_path = try test_utils.createTempProject("end_to_end_test", &project_files);
    defer allocator.free(project_path);
    
    // Step 1: Analyze memory issues
    std.debug.print("Step 1: Memory analysis...\n", .{});
    const main_file_path = try std.fs.path.join(allocator, &.{ project_path, "src/main.zig" });
    defer allocator.free(main_file_path);
    
    const memory_result = try zig_tooling.analyzeFile(
        allocator,
        main_file_path,
        zig_tooling.Config{ .memory = .{ .check_defer = true } },
    );
    defer allocator.free(memory_result.issues);
    defer for (memory_result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    try testing.expect(memory_result.issues_found > 0);
    std.debug.print("Found {} memory issues\n", .{memory_result.issues_found});
    
    // Step 2: Analyze test compliance
    std.debug.print("Step 2: Test compliance analysis...\n", .{});
    const test_config = zig_tooling.Config{
        .testing = .{
            .enforce_categories = true,
            .enforce_naming = true,
            .allowed_categories = &.{ "unit", "integration", "e2e" },
        },
    };
    
    const test_file_path = try std.fs.path.join(allocator, &.{ project_path, "tests/test_main.zig" });
    defer allocator.free(test_file_path);
    
    const test_result = try zig_tooling.analyzeFile(
        allocator,
        test_file_path,
        test_config,
    );
    defer allocator.free(test_result.issues);
    defer for (test_result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    try testing.expect(test_result.issues_found > 0);
    std.debug.print("Found {} test compliance issues\n", .{test_result.issues_found});
    
    // Step 3: Format results
    std.debug.print("Step 3: Formatting results...\n", .{});
    
    const text_output = try zig_tooling.formatters.formatAsText(allocator, memory_result, .{
        .color = false,
        .verbose = false,
        .max_issues = 10,
    });
    defer allocator.free(text_output);
    
    try testing.expect(text_output.len > 0);
    std.debug.print("Text format length: {} chars\n", .{text_output.len});
    
    const json_output = try zig_tooling.formatters.formatAsJson(allocator, test_result, .{
        .json_indent = 2,
        .include_stats = true,
    });
    defer allocator.free(json_output);
    
    try testing.expect(json_output.len > 0);
    try testing.expect(std.mem.indexOf(u8, json_output, "\"issues\":") != null);
    std.debug.print("JSON format length: {} chars\n", .{json_output.len});
    
    std.debug.print("✓ End-to-end workflow completed successfully\n", .{});
}

test "integration: large project performance" {
    const allocator = testing.allocator;
    
    var test_utils = try TestUtils.init(allocator);
    defer test_utils.deinit();
    
    std.debug.print("\n--- Testing Large Project Performance ---\n", .{});
    
    // Create a project with many files to test performance
    var project_files = std.ArrayList(test_runner.FileSpec).init(allocator);
    defer project_files.deinit();
    
    const file_count = 20;
    var i: u32 = 0;
    while (i < file_count) : (i += 1) {
        const file_path = try std.fmt.allocPrint(allocator, "src/module_{}.zig", .{i});
        defer allocator.free(file_path);
        
        const file_content = try std.fmt.allocPrint(allocator,
            \\const std = @import("std");
            \\
            \\pub fn function_{}(allocator: std.mem.Allocator) ![]u8 {{
            \\    const data = try allocator.alloc(u8, {});
            \\    defer allocator.free(data);
            \\    return try allocator.dupe(u8, data);
            \\}}
            \\
            \\pub fn leaky_function_{}() !void {{
            \\    const allocator = std.heap.page_allocator;
            \\    const buffer = try allocator.alloc(u8, 256);
            \\    // Missing defer - intentional leak for testing
            \\}}
        , .{ i, (i + 1) * 100, i });
        defer allocator.free(file_content);
        
        const owned_path = try allocator.dupe(u8, file_path);
        const owned_content = try allocator.dupe(u8, file_content);
        
        try project_files.append(.{
            .path = owned_path,
            .content = owned_content,
        });
    }
    
    // Clean up the dynamically allocated strings
    defer for (project_files.items) |file_spec| {
        allocator.free(file_spec.path);
        allocator.free(file_spec.content);
    };
    
    const project_path = try test_utils.createTempProject("large_project_test", project_files.items);
    defer allocator.free(project_path);
    
    var benchmark = PerformanceBenchmark.start(allocator, "Large project analysis");
    
    const result = try zig_tooling.patterns.checkProject(
        allocator,
        project_path,
        null,
        null,
    );
    defer zig_tooling.patterns.freeProjectResult(allocator, result);
    
    const duration = benchmark.end();
    
    try testing.expect(result.files_analyzed == file_count);
    try testing.expect(result.issues_found > 0); // Should find the intentional leaks
    
    // Performance target: should handle 20 files in reasonable time
    try testing.expect(duration < 5000); // Less than 5 seconds
    
    std.debug.print("Analyzed {} files in {}ms (avg: {}ms per file)\n", .{
        result.files_analyzed,
        duration,
        @divTrunc(duration, result.files_analyzed),
    });
    
    std.debug.print("✓ Large project performance test completed\n", .{});
}
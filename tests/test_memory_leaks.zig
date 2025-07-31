//! Comprehensive memory leak tests for analyzeMemory() and analyzeTests() functions
//! 
//! This test file specifically targets issue LC103: Use-after-free bug in analyzeMemory()
//! and analyzeTests() where analyzer-owned memory was accessed after analyzer.deinit().
//! 
//! The tests use GeneralPurposeAllocator to detect memory leaks and verify that the
//! functions properly manage memory ownership when copying strings from analyzer results.
//!
//! ## Background
//! LC103 was caused by:
//! 1. Using `defer analyzer.deinit()` at function start
//! 2. Accessing analyzer.getIssues() memory after the defer executed
//! 3. This caused use-after-free when copying issue strings
//!
//! ## Fix Verification
//! These tests verify that:
//! 1. Manual deinit() after string copying prevents use-after-free
//! 2. No memory leaks occur in normal operation
//! 3. Error paths properly clean up resources
//! 4. Multiple analyses don't accumulate leaks

const std = @import("std");
const testing = std.testing;
const zig_tooling = @import("zig_tooling");

// Test valid source code samples
const VALID_MEMORY_SOURCE = 
    \\pub fn validFunction() void {
    \\    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    \\    defer _ = gpa.deinit();
    \\    const allocator = gpa.allocator();
    \\    
    \\    const data = allocator.alloc(u8, 100) catch return;
    \\    defer allocator.free(data);
    \\    
    \\    // Use the data
    \\    for (data, 0..) |*byte, i| {
    \\        byte.* = @intCast(i % 256);
    \\    }
    \\}
    ;

const VALID_TEST_SOURCE = 
    \\test "unit: example: basic functionality test" {
    \\    const allocator = std.testing.allocator;
    \\    const buffer = try allocator.alloc(u8, 50);
    \\    defer allocator.free(buffer);
    \\    
    \\    try std.testing.expect(buffer.len == 50);
    \\}
    \\
    \\test "integration: example: complex workflow test" {
    \\    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    \\    defer _ = gpa.deinit();
    \\    const allocator = gpa.allocator();
    \\    
    \\    const items = try allocator.alloc(i32, 10);
    \\    defer allocator.free(items);
    \\    
    \\    for (items, 0..) |*item, i| {
    \\        item.* = @intCast(i * 2);
    \\    }
    \\}
    ;

const PROBLEMATIC_MEMORY_SOURCE = 
    \\pub fn problematicFunction() void {
    \\    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    \\    defer _ = gpa.deinit();
    \\    const allocator = gpa.allocator();
    \\    
    \\    // Missing defer - should be detected
    \\    const data = allocator.alloc(u8, 100) catch return;
    \\    
    \\    // Use disallowed allocator - should be detected
    \\    var page_alloc = std.heap.page_allocator;
    \\    const page_data = page_alloc.alloc(u8, 200) catch return;
    \\    defer page_alloc.free(page_data);
    \\}
    ;

const PROBLEMATIC_TEST_SOURCE = 
    \\test "badNamedTest" {
    \\    const allocator = std.testing.allocator;
    \\    const buffer = try allocator.alloc(u8, 50);
    \\    defer allocator.free(buffer);
    \\}
    \\
    \\test "another bad test name" {
    \\    // Missing category prefix
    \\    try std.testing.expect(true);
    \\}
    ;

// Invalid source code for testing error paths - actual syntax error
const INVALID_SOURCE = 
    \\const x = @import("std");
    \\pub fn broken() void {
    \\    const y = "unterminated string
    \\    missing_semicolon()
    \\}
    ;

// Custom test configuration
const TEST_CONFIG = zig_tooling.Config{
    .memory = .{
        .check_defer = true,
        .check_allocator_usage = true,
        .check_arena_usage = true,
        .check_ownership_transfer = true,
        .allowed_allocators = &.{
            "std.heap.GeneralPurposeAllocator",
            "std.testing.allocator",
            "std.heap.ArenaAllocator",
        },
    },
    .testing = .{
        .enforce_naming = true,
        .enforce_categories = true,
        .enforce_test_files = true,
        .allowed_categories = &.{
            "unit",
            "integration", 
            "benchmark",
            "fuzz",
        },
    },
};

// Helper function to verify no memory leaks with GPA
fn verifyNoLeaks(gpa: *std.heap.GeneralPurposeAllocator(.{})) !void {
    const leaked = gpa.deinit();
    if (leaked == .leak) {
        // Print detailed leak information for debugging
        std.debug.print("\n=== MEMORY LEAK DETECTED ===\n", .{});
        std.debug.print("GeneralPurposeAllocator detected leaked allocations.\n", .{});
        std.debug.print("This indicates the test failed to properly clean up memory.\n", .{});
        std.debug.print("=============================\n", .{});
    }
    try testing.expect(leaked == .ok);
}

// Helper function to properly free AnalysisResult
fn freeAnalysisResult(allocator: std.mem.Allocator, result: zig_tooling.AnalysisResult) void {
    for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    }
    allocator.free(result.issues);
}

test "LC103: analyzeMemory basic memory leak test with valid code" {
    // Use GPA to detect any memory leaks
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    // Test the main function that had the use-after-free bug
    const result = try zig_tooling.analyzeMemory(
        allocator,
        VALID_MEMORY_SOURCE,
        "test_valid.zig",
        null
    );
    
    // Verify we got a result
    try testing.expect(result.files_analyzed == 1);
    
    // Properly clean up the result
    freeAnalysisResult(allocator, result);
    
    // Verify no memory leaks occurred
    try verifyNoLeaks(&gpa);
}

test "LC103: analyzeMemory with custom config - no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    // Use custom config to ensure config path is tested
    const result = try zig_tooling.analyzeMemory(
        allocator,
        VALID_MEMORY_SOURCE,
        "test_valid_config.zig",
        TEST_CONFIG
    );
    
    try testing.expect(result.files_analyzed == 1);
    
    freeAnalysisResult(allocator, result);
    try verifyNoLeaks(&gpa);
}

test "LC103: analyzeMemory with problematic code - detects issues without leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    // This should detect memory issues but not leak memory
    const result = try zig_tooling.analyzeMemory(
        allocator,
        PROBLEMATIC_MEMORY_SOURCE,
        "test_problematic.zig",
        TEST_CONFIG
    );
    
    // Should have found issues (missing defer, disallowed allocator)
    try testing.expect(result.issues_found > 0);
    
    // Verify we have actual issue data
    try testing.expect(result.issues.len > 0);
    for (result.issues) |issue| {
        try testing.expect(issue.file_path.len > 0);
        try testing.expect(issue.message.len > 0);
    }
    
    freeAnalysisResult(allocator, result);
    try verifyNoLeaks(&gpa);
}

test "LC103: analyzeMemory error path - invalid source code cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    // Even if the code doesn't trigger parse error, ensure no leaks in any case
    const result = zig_tooling.analyzeMemory(
        allocator,
        INVALID_SOURCE,
        "test_invalid.zig",
        null
    ) catch |err| {
        // If we do get an error, make sure it's handled without leaks
        try testing.expect(err == zig_tooling.AnalysisError.ParseError or 
                          err == zig_tooling.AnalysisError.OutOfMemory);
        try verifyNoLeaks(&gpa);
        return;
    };
    
    // If no error, clean up normally and verify no leaks
    freeAnalysisResult(allocator, result);
    try verifyNoLeaks(&gpa);
}

test "LC103: analyzeMemory repeated calls - no accumulating leaks" {
    // Test multiple analyses to ensure no leaks accumulate
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    // Run multiple analyses
    for (0..10) |i| {
        const file_path = try std.fmt.allocPrint(allocator, "test_repeated_{}.zig", .{i});
        defer allocator.free(file_path);
        
        const result = try zig_tooling.analyzeMemory(
            allocator,
            VALID_MEMORY_SOURCE,
            file_path,
            if (i % 2 == 0) null else TEST_CONFIG
        );
        
        try testing.expect(result.files_analyzed == 1);
        freeAnalysisResult(allocator, result);
    }
    
    try verifyNoLeaks(&gpa);
}

test "LC103: analyzeTests basic memory leak test with valid code" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    const result = try zig_tooling.analyzeTests(
        allocator,
        VALID_TEST_SOURCE,
        "test_valid_tests.zig",
        null
    );
    
    try testing.expect(result.files_analyzed == 1);
    
    freeAnalysisResult(allocator, result);
    try verifyNoLeaks(&gpa);
}

test "LC103: analyzeTests with custom config - no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    const result = try zig_tooling.analyzeTests(
        allocator,
        VALID_TEST_SOURCE,
        "test_valid_tests_config.zig",
        TEST_CONFIG
    );
    
    try testing.expect(result.files_analyzed == 1);
    
    freeAnalysisResult(allocator, result);
    try verifyNoLeaks(&gpa);
}

test "LC103: analyzeTests with problematic code - detects issues without leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    const result = try zig_tooling.analyzeTests(
        allocator,
        PROBLEMATIC_TEST_SOURCE,
        "test_problematic_tests.zig",
        TEST_CONFIG
    );
    
    // Should detect naming issues
    try testing.expect(result.issues_found > 0);
    try testing.expect(result.issues.len > 0);
    
    // Verify issue data integrity
    for (result.issues) |issue| {
        try testing.expect(issue.file_path.len > 0);
        try testing.expect(issue.message.len > 0);
    }
    
    freeAnalysisResult(allocator, result);
    try verifyNoLeaks(&gpa);
}

test "LC103: analyzeTests error path - invalid source code cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    // Even if the code doesn't trigger parse error, ensure no leaks in any case
    const result = zig_tooling.analyzeTests(
        allocator,
        INVALID_SOURCE,
        "test_invalid_tests.zig",
        null
    ) catch |err| {
        // If we do get an error, make sure it's handled without leaks
        try testing.expect(err == zig_tooling.AnalysisError.ParseError or 
                          err == zig_tooling.AnalysisError.OutOfMemory);
        try verifyNoLeaks(&gpa);
        return;
    };
    
    // If no error, clean up normally and verify no leaks
    freeAnalysisResult(allocator, result);
    try verifyNoLeaks(&gpa);
}

test "LC103: analyzeTests repeated calls - no accumulating leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    for (0..8) |i| {
        const file_path = try std.fmt.allocPrint(allocator, "test_repeated_tests_{}.zig", .{i});
        defer allocator.free(file_path);
        
        const result = try zig_tooling.analyzeTests(
            allocator,
            VALID_TEST_SOURCE,
            file_path,
            if (i % 3 == 0) TEST_CONFIG else null
        );
        
        try testing.expect(result.files_analyzed == 1);
        freeAnalysisResult(allocator, result);
    }
    
    try verifyNoLeaks(&gpa);
}

test "LC103: mixed analyzeMemory and analyzeTests calls - no cross-contamination leaks" {
    // Test alternating between the two functions to ensure no cross-contamination
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    for (0..6) |i| {
        const file_path = try std.fmt.allocPrint(allocator, "test_mixed_{}.zig", .{i});
        defer allocator.free(file_path);
        
        if (i % 2 == 0) {
            const result = try zig_tooling.analyzeMemory(
                allocator,
                VALID_MEMORY_SOURCE,
                file_path,
                null
            );
            freeAnalysisResult(allocator, result);
        } else {
            const result = try zig_tooling.analyzeTests(
                allocator,
                VALID_TEST_SOURCE,
                file_path,
                null
            );
            freeAnalysisResult(allocator, result);
        }
    }
    
    try verifyNoLeaks(&gpa);
}

test "LC103: stress test - many analyses with mixed success/error outcomes" {
    // Stress test to catch any edge case leaks
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    const test_cases = [_]struct {
        source: []const u8,
        should_succeed: bool,
        use_memory_analyzer: bool,
    }{
        .{ .source = VALID_MEMORY_SOURCE, .should_succeed = true, .use_memory_analyzer = true },
        .{ .source = VALID_TEST_SOURCE, .should_succeed = true, .use_memory_analyzer = false },
        .{ .source = PROBLEMATIC_MEMORY_SOURCE, .should_succeed = true, .use_memory_analyzer = true },
        .{ .source = PROBLEMATIC_TEST_SOURCE, .should_succeed = true, .use_memory_analyzer = false },
        .{ .source = INVALID_SOURCE, .should_succeed = false, .use_memory_analyzer = true },
        .{ .source = INVALID_SOURCE, .should_succeed = false, .use_memory_analyzer = false },
    };
    
    for (test_cases, 0..) |test_case, i| {
        const file_path = try std.fmt.allocPrint(allocator, "test_stress_{}.zig", .{i});
        defer allocator.free(file_path);
        
        if (test_case.use_memory_analyzer) {
            if (test_case.should_succeed) {
                const result = try zig_tooling.analyzeMemory(
                    allocator,
                    test_case.source,
                    file_path,
                    if (i % 2 == 0) null else TEST_CONFIG
                );
                freeAnalysisResult(allocator, result);
            } else {
                _ = zig_tooling.analyzeMemory(
                    allocator,
                    test_case.source,
                    file_path,
                    null
                ) catch |err| {
                    try testing.expect(err == zig_tooling.AnalysisError.ParseError);
                };
            }
        } else {
            if (test_case.should_succeed) {
                const result = try zig_tooling.analyzeTests(
                    allocator,
                    test_case.source,
                    file_path,
                    if (i % 3 == 0) TEST_CONFIG else null
                );
                freeAnalysisResult(allocator, result);
            } else {
                _ = zig_tooling.analyzeTests(
                    allocator,
                    test_case.source,
                    file_path,
                    null
                ) catch |err| {
                    try testing.expect(err == zig_tooling.AnalysisError.ParseError);
                };
            }
        }
    }
    
    try verifyNoLeaks(&gpa);
}

test "LC103: empty source code - edge case handling" {
    // Test edge case with empty source
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    const empty_source = "";
    
    const memory_result = try zig_tooling.analyzeMemory(
        allocator,
        empty_source,
        "empty.zig",
        null
    );
    freeAnalysisResult(allocator, memory_result);
    
    const test_result = try zig_tooling.analyzeTests(
        allocator,
        empty_source,
        "empty.zig",
        null
    );
    freeAnalysisResult(allocator, test_result);
    
    try verifyNoLeaks(&gpa);
}

test "LC103: very large source code - memory pressure test" {
    // Test with larger source code to create memory pressure
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    // Build a large source file using testing allocator to avoid leak confusion
    var large_source = std.ArrayList(u8).init(testing.allocator);
    defer large_source.deinit();
    
    // Add many functions to create a large source - use static template
    const func_template = 
        \\pub fn testFunctionA() void {
        \\    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        \\    defer _ = gpa.deinit();
        \\    const alloc = gpa.allocator();
        \\    
        \\    const data = alloc.alloc(u8, 150) catch return;
        \\    defer alloc.free(data);
        \\    
        \\    for (data, 0..) |*byte, idx| {
        \\        byte.* = @intCast(idx % 256);
        \\    }
        \\}
        \\
        ;
    
    // Repeat the template many times to create memory pressure
    for (0..50) |_| {
        try large_source.appendSlice(func_template);
    }
    
    const result = try zig_tooling.analyzeMemory(
        allocator,
        large_source.items,
        "large_test.zig",
        null
    );
    
    try testing.expect(result.files_analyzed == 1);
    freeAnalysisResult(allocator, result);
    
    try verifyNoLeaks(&gpa);
}

test "LC103: verify Issue string fields are properly owned" {
    // Specifically test that Issue strings are properly copied and owned
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    const result = try zig_tooling.analyzeMemory(
        allocator,
        PROBLEMATIC_MEMORY_SOURCE,
        "test_string_ownership.zig",
        TEST_CONFIG
    );
    
    try testing.expect(result.issues.len > 0);
    
    // Check that all string fields are properly allocated and accessible
    for (result.issues) |issue| {
        // These accesses would crash if use-after-free occurred
        try testing.expect(issue.file_path.len > 0);
        try testing.expect(std.mem.eql(u8, issue.file_path, "test_string_ownership.zig"));
        
        try testing.expect(issue.message.len > 0);
        // Message should contain meaningful content
        try testing.expect(!std.mem.eql(u8, issue.message, ""));
        
        // If suggestion exists, it should be accessible
        if (issue.suggestion) |suggestion| {
            try testing.expect(suggestion.len > 0);
        }
        
        // Verify other fields are valid
        try testing.expect(issue.line > 0);
        try testing.expect(issue.column >= 0);
    }
    
    freeAnalysisResult(allocator, result);
    try verifyNoLeaks(&gpa);
}
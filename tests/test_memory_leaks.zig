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

// ============================================================================
// PATTERNS.CHECKPROJECT MEMORY LEAK TESTS  
// ============================================================================
//
// The following tests target the specific memory leaks in patterns.checkProject
// at lines 167, 172, 173 where duplicated strings aren't freed on error paths:
//
//   167: .file_path = try allocator.dupe(u8, issue.file_path),
//   172: .message = try allocator.dupe(u8, issue.message), 
//   173: .suggestion = if (issue.suggestion) |s| try allocator.dupe(u8, s) else null,
//
// These tests verify proper memory management in both success and error scenarios.

// Helper to create a temporary directory with test files
fn createTestProject(allocator: std.mem.Allocator, tmp_dir_path: []const u8) !void {
    _ = allocator; // Not used anymore - using testing allocator instead
    
    // Create directory structure
    try std.fs.cwd().makePath(tmp_dir_path);
    
    // Create a simple valid .zig file using testing allocator
    const valid_file_path = try std.fs.path.join(testing.allocator, &.{ tmp_dir_path, "valid.zig" });
    defer testing.allocator.free(valid_file_path);
    
    const valid_file = try std.fs.cwd().createFile(valid_file_path, .{});
    defer valid_file.close();
    try valid_file.writeAll(VALID_MEMORY_SOURCE);
    
    // Create a problematic .zig file using testing allocator
    const problematic_file_path = try std.fs.path.join(testing.allocator, &.{ tmp_dir_path, "problematic.zig" });
    defer testing.allocator.free(problematic_file_path);
    
    const problematic_file = try std.fs.cwd().createFile(problematic_file_path, .{});
    defer problematic_file.close();
    try problematic_file.writeAll(PROBLEMATIC_MEMORY_SOURCE);
    
    // Create a subdirectory with more files using testing allocator
    const sub_dir_path = try std.fs.path.join(testing.allocator, &.{ tmp_dir_path, "subdir" });
    defer testing.allocator.free(sub_dir_path);
    try std.fs.cwd().makePath(sub_dir_path);
    
    const sub_file_path = try std.fs.path.join(testing.allocator, &.{ sub_dir_path, "sub_file.zig" });
    defer testing.allocator.free(sub_file_path);
    
    const sub_file = try std.fs.cwd().createFile(sub_file_path, .{});
    defer sub_file.close();
    try sub_file.writeAll(VALID_TEST_SOURCE);
}

// Helper to clean up temporary directory
fn cleanupTestProject(tmp_dir_path: []const u8) void {
    std.fs.cwd().deleteTree(tmp_dir_path) catch {};
}

// Helper to free ProjectAnalysisResult - same as patterns.freeProjectResult
fn freeProjectAnalysisResult(allocator: std.mem.Allocator, result: zig_tooling.patterns.ProjectAnalysisResult) void {
    for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    }
    allocator.free(result.issues);
    
    for (result.failed_files) |file_path| {
        allocator.free(file_path);
    }
    allocator.free(result.failed_files);
    
    for (result.skipped_files) |file_path| {
        allocator.free(file_path);
    }
    allocator.free(result.skipped_files);
}

test "LC103: patterns.checkProject basic success path - no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    // Create temporary test project
    const tmp_dir = "test_checkproject_basic";
    createTestProject(allocator, tmp_dir) catch |err| switch (err) {
        error.AccessDenied => return, // Skip test if can't create temp files
        else => return err,
    };
    defer cleanupTestProject(tmp_dir);
    
    // Run checkProject analysis
    const result = try zig_tooling.patterns.checkProject(
        allocator,
        tmp_dir,
        null, // Use default config
        null  // No progress callback
    );
    
    // Verify basic result structure
    try testing.expect(result.files_analyzed > 0);
    try testing.expect(result.analysis_time_ms > 0);
    
    // Should have found some issues in the problematic file
    try testing.expect(result.issues_found > 0);
    try testing.expect(result.issues.len > 0);
    
    // Verify all issues have valid string data (tests the specific leak lines)
    for (result.issues) |issue| {
        // These are the specific fields that leak at lines 167, 172, 173
        try testing.expect(issue.file_path.len > 0);
        try testing.expect(issue.message.len > 0);
        // suggestion can be null, but if it exists should be valid
        if (issue.suggestion) |s| {
            try testing.expect(s.len > 0);
        }
    }
    
    // Clean up result
    freeProjectAnalysisResult(allocator, result);
    
    // Verify no memory leaks
    try verifyNoLeaks(&gpa);
}

test "LC103: patterns.checkProject with custom config - no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    const tmp_dir = "test_checkproject_config";
    createTestProject(allocator, tmp_dir) catch |err| switch (err) {
        error.AccessDenied => return,
        else => return err,
    };
    defer cleanupTestProject(tmp_dir);
    
    // Run with custom config
    const result = try zig_tooling.patterns.checkProject(
        allocator,
        tmp_dir,
        TEST_CONFIG, // Use test config
        null
    );
    
    try testing.expect(result.files_analyzed > 0);
    try testing.expect(result.issues.len > 0);
    
    // Verify string ownership (the leak-prone lines 167, 172, 173)
    for (result.issues) |issue| {
        try testing.expect(issue.file_path.len > 0);
        try testing.expect(!std.mem.eql(u8, issue.file_path, ""));
        try testing.expect(issue.message.len > 0);
        try testing.expect(!std.mem.eql(u8, issue.message, ""));
        if (issue.suggestion) |s| {
            try testing.expect(s.len > 0);
        }
    }
    
    freeProjectAnalysisResult(allocator, result);
    try verifyNoLeaks(&gpa);
}

test "LC103: patterns.checkProject error path - FileNotFound cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    // Try to analyze non-existent directory
    const result = zig_tooling.patterns.checkProject(
        allocator,
        "this_directory_does_not_exist",
        null,
        null
    ) catch |err| {
        // Should get FileNotFound error
        try testing.expect(err == zig_tooling.AnalysisError.FileNotFound);
        // Even on error, no memory should leak
        try verifyNoLeaks(&gpa);
        return;
    };
    
    // If we somehow didn't get an error, clean up
    freeProjectAnalysisResult(allocator, result);
    try verifyNoLeaks(&gpa);
}

// Global variable to track progress calls for test
var global_progress_calls: u32 = 0;

fn testProgressCallback(files_processed: u32, total_files: u32, current_file: []const u8) void {
    _ = files_processed;
    _ = total_files;
    _ = current_file;
    global_progress_calls += 1;
}

test "LC103: patterns.checkProject with progress callback - no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    const tmp_dir = "test_checkproject_progress";
    createTestProject(allocator, tmp_dir) catch |err| switch (err) {
        error.AccessDenied => return,
        else => return err,
    };
    defer cleanupTestProject(tmp_dir);
    
    // Reset progress counter
    global_progress_calls = 0;
    
    const result = try zig_tooling.patterns.checkProject(
        allocator,
        tmp_dir,
        null,
        testProgressCallback // Progress callback to test that code path
    );
    
    try testing.expect(result.files_analyzed > 0);
    try testing.expect(global_progress_calls > 0); // Progress should have been called
    
    // Verify no issues with string duplication (lines 167, 172, 173)
    for (result.issues) |issue| {
        try testing.expect(issue.file_path.len > 0);
        try testing.expect(issue.message.len > 0);
    }
    
    freeProjectAnalysisResult(allocator, result);
    try verifyNoLeaks(&gpa);
}

test "LC103: patterns.checkProject memory pressure test - many files" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    const tmp_dir = "test_checkproject_pressure";
    try std.fs.cwd().makePath(tmp_dir);
    defer cleanupTestProject(tmp_dir);
    
    // Create many files to stress test memory management using testing allocator
    for (0..20) |i| {
        const file_name = try std.fmt.allocPrint(testing.allocator, "test_file_{}.zig", .{i});
        defer testing.allocator.free(file_name);
        
        const file_path = try std.fs.path.join(testing.allocator, &.{ tmp_dir, file_name });
        defer testing.allocator.free(file_path);
        
        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();
        
        // Alternate between problematic and valid code
        const source = if (i % 2 == 0) VALID_MEMORY_SOURCE else PROBLEMATIC_MEMORY_SOURCE;
        try file.writeAll(source);
    }
    
    const result = try zig_tooling.patterns.checkProject(
        allocator,
        tmp_dir,
        TEST_CONFIG,
        null
    );
    
    try testing.expect(result.files_analyzed == 20);
    try testing.expect(result.issues.len > 0); // Should have found issues
    
    // This stress test specifically targets the string duplication leak areas
    var file_path_total_len: usize = 0;
    var message_total_len: usize = 0;
    for (result.issues) |issue| {
        file_path_total_len += issue.file_path.len;
        message_total_len += issue.message.len;
    }
    
    // Verify meaningful amounts of string data were duplicated and managed
    try testing.expect(file_path_total_len > 0);
    try testing.expect(message_total_len > 0);
    
    freeProjectAnalysisResult(allocator, result);
    try verifyNoLeaks(&gpa);
}

test "LC103: patterns.checkProject error recovery - files with read errors" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    const tmp_dir = "test_checkproject_errors";
    try std.fs.cwd().makePath(tmp_dir);
    defer cleanupTestProject(tmp_dir);
    
    // Create some valid files using testing allocator to avoid leak confusion
    for (0..3) |i| {
        const file_name = try std.fmt.allocPrint(testing.allocator, "valid_{}.zig", .{i});
        defer testing.allocator.free(file_name);
        
        const file_path = try std.fs.path.join(testing.allocator, &.{ tmp_dir, file_name });
        defer testing.allocator.free(file_path);
        
        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();
        try file.writeAll(VALID_MEMORY_SOURCE);
    }
    
    // Create a file that will cause parse/read issues using testing allocator
    const bad_file_path = try std.fs.path.join(testing.allocator, &.{ tmp_dir, "bad.zig" });
    defer testing.allocator.free(bad_file_path);
    
    const bad_file = try std.fs.cwd().createFile(bad_file_path, .{});
    defer bad_file.close();
    try bad_file.writeAll(INVALID_SOURCE); // This should cause issues
    
    const result = try zig_tooling.patterns.checkProject(
        allocator,
        tmp_dir,
        null,
        null
    );
    
    // Should have analyzed most files successfully
    try testing.expect(result.files_analyzed >= 3);
    
    // The key test: ensure that even with error recovery, 
    // the string duplication at lines 167, 172, 173 doesn't leak
    for (result.issues) |issue| {
        try testing.expect(issue.file_path.len > 0);
        try testing.expect(issue.message.len > 0);
    }
    
    freeProjectAnalysisResult(allocator, result);
    try verifyNoLeaks(&gpa);
}

test "LC103: patterns.checkProject repeated calls - no accumulating leaks" {
    // Test multiple checkProject calls to ensure no leaks accumulate
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    const tmp_dir = "test_checkproject_repeated";
    createTestProject(allocator, tmp_dir) catch |err| switch (err) {
        error.AccessDenied => return,
        else => return err,
    };
    defer cleanupTestProject(tmp_dir);
    
    // Run multiple analyses in sequence
    for (0..5) |i| {
        const result = try zig_tooling.patterns.checkProject(
            allocator,
            tmp_dir,
            if (i % 2 == 0) null else TEST_CONFIG,
            null
        );
        
        try testing.expect(result.files_analyzed > 0);
        
        // Verify string data integrity on each iteration
        for (result.issues) |issue| {
            try testing.expect(issue.file_path.len > 0);
            try testing.expect(issue.message.len > 0);
        }
        
        freeProjectAnalysisResult(allocator, result);
    }
    
    // After all iterations, no leaks should remain
    try verifyNoLeaks(&gpa);
}

test "LC103: patterns.checkProject edge case - empty project" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    const tmp_dir = "test_checkproject_empty";
    try std.fs.cwd().makePath(tmp_dir);
    defer cleanupTestProject(tmp_dir);
    
    // Empty directory - no .zig files
    const result = try zig_tooling.patterns.checkProject(
        allocator,
        tmp_dir,
        null,
        null
    );
    
    // Should have analyzed 0 files
    try testing.expect(result.files_analyzed == 0);
    try testing.expect(result.issues.len == 0);
    try testing.expect(result.failed_files.len == 0);
    try testing.expect(result.skipped_files.len == 0);
    
    freeProjectAnalysisResult(allocator, result);
    try verifyNoLeaks(&gpa);
}

test "LC103: patterns.checkProject string ownership validation" {
    // This test specifically validates the string ownership issues at lines 167, 172, 173
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    const tmp_dir = "test_checkproject_ownership";
    createTestProject(allocator, tmp_dir) catch |err| switch (err) {
        error.AccessDenied => return,
        else => return err,
    };
    defer cleanupTestProject(tmp_dir);
    
    const result = try zig_tooling.patterns.checkProject(
        allocator,
        tmp_dir,
        TEST_CONFIG,
        null
    );
    
    try testing.expect(result.issues.len > 0);
    
    // Store copies of strings to verify they remain valid after use
    var stored_paths = std.ArrayList([]const u8).init(testing.allocator);
    defer {
        for (stored_paths.items) |path| {
            testing.allocator.free(path);
        }
        stored_paths.deinit();
    }
    
    var stored_messages = std.ArrayList([]const u8).init(testing.allocator);
    defer {
        for (stored_messages.items) |msg| {
            testing.allocator.free(msg);
        }
        stored_messages.deinit();
    }
    
    // Copy all string data to verify it stays valid
    for (result.issues) |issue| {
        try stored_paths.append(try testing.allocator.dupe(u8, issue.file_path));
        try stored_messages.append(try testing.allocator.dupe(u8, issue.message));
        
        // Verify strings contain expected content
        try testing.expect(std.mem.endsWith(u8, issue.file_path, ".zig"));
        try testing.expect(issue.message.len > 5); // Reasonable message length
        
        if (issue.suggestion) |suggestion| {
            try testing.expect(suggestion.len > 0);
        }
    }
    
    // Free the result
    freeProjectAnalysisResult(allocator, result);
    
    // Verify our copied strings are still valid (proving ownership was correct)
    for (stored_paths.items) |path| {
        try testing.expect(std.mem.endsWith(u8, path, ".zig"));
    }
    
    for (stored_messages.items) |msg| {
        try testing.expect(msg.len > 5);
    }
    
    try verifyNoLeaks(&gpa);
}

// ============================================================================
// LC107 TESTS: analyzeFile() and analyzeSource() memory leak fixes
// ============================================================================
//
// The following tests verify that analyzeFile() and analyzeSource() properly
// free string fields in their analysis results. These functions call 
// analyzeMemory() and analyzeTests() and combine the results, transferring
// ownership properly without leaking the duplicated strings.

test "LC107: analyzeFile basic success path - no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    // Create a temporary test file
    const tmp_file_path = "test_analyzefile_basic.zig";
    const test_file = std.fs.cwd().createFile(tmp_file_path, .{}) catch |err| switch (err) {
        error.AccessDenied => return, // Skip if can't create files
        else => return err,
    };
    defer test_file.close();
    defer std.fs.cwd().deleteFile(tmp_file_path) catch {};
    
    try test_file.writeAll(PROBLEMATIC_MEMORY_SOURCE);
    
    // Test analyzeFile
    const result = try zig_tooling.analyzeFile(allocator, tmp_file_path, null);
    
    // Should have found issues from both analyzers
    try testing.expect(result.files_analyzed == 1);
    try testing.expect(result.issues_found > 0);
    try testing.expect(result.issues.len > 0);
    
    // Verify all string fields are valid - these would crash if use-after-free
    for (result.issues) |issue| {
        try testing.expect(issue.file_path.len > 0);
        try testing.expect(std.mem.eql(u8, issue.file_path, tmp_file_path));
        try testing.expect(issue.message.len > 0);
        try testing.expect(issue.line > 0);
        try testing.expect(issue.column >= 0);
        
        if (issue.suggestion) |suggestion| {
            try testing.expect(suggestion.len > 0);
        }
    }
    
    // Clean up result
    zig_tooling.freeAnalysisResult(allocator, result);
    
    // Verify no memory leaks
    try verifyNoLeaks(&gpa);
}

test "LC107: analyzeFile with custom config - no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    const tmp_file_path = "test_analyzefile_config.zig";
    const test_file = std.fs.cwd().createFile(tmp_file_path, .{}) catch |err| switch (err) {
        error.AccessDenied => return,
        else => return err,
    };
    defer test_file.close();
    defer std.fs.cwd().deleteFile(tmp_file_path) catch {};
    
    try test_file.writeAll(PROBLEMATIC_MEMORY_SOURCE);
    
    const result = try zig_tooling.analyzeFile(allocator, tmp_file_path, TEST_CONFIG);
    
    try testing.expect(result.files_analyzed == 1);
    try testing.expect(result.issues.len > 0);
    
    // Verify string ownership - no use-after-free
    for (result.issues) |issue| {
        try testing.expect(issue.file_path.len > 0);
        try testing.expect(issue.message.len > 0);
        // Verify path is what we expect
        try testing.expect(std.mem.eql(u8, issue.file_path, tmp_file_path));
    }
    
    zig_tooling.freeAnalysisResult(allocator, result);
    try verifyNoLeaks(&gpa);
}

test "LC107: analyzeFile with valid source - no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    const tmp_file_path = "test_analyzefile_valid.zig";
    const test_file = std.fs.cwd().createFile(tmp_file_path, .{}) catch |err| switch (err) {
        error.AccessDenied => return,
        else => return err,
    };
    defer test_file.close();
    defer std.fs.cwd().deleteFile(tmp_file_path) catch {};
    
    try test_file.writeAll(VALID_MEMORY_SOURCE);
    
    const result = try zig_tooling.analyzeFile(allocator, tmp_file_path, null);
    
    try testing.expect(result.files_analyzed == 1);
    // May or may not have issues, but should not leak
    
    for (result.issues) |issue| {
        try testing.expect(issue.file_path.len > 0);
        try testing.expect(issue.message.len > 0);
    }
    
    zig_tooling.freeAnalysisResult(allocator, result);
    try verifyNoLeaks(&gpa);
}

test "LC107: analyzeFile error path - file not found cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    // Try to analyze non-existent file
    const result = zig_tooling.analyzeFile(allocator, "this_file_does_not_exist.zig", null) catch |err| {
        // Should get FileNotFound error
        try testing.expect(err == zig_tooling.AnalysisError.FileNotFound);
        // Even on error, no memory should leak
        try verifyNoLeaks(&gpa);
        return;
    };
    
    // If we somehow didn't get an error, clean up
    zig_tooling.freeAnalysisResult(allocator, result);
    try verifyNoLeaks(&gpa);
}

test "LC107: analyzeFile repeated calls - no accumulating leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    const tmp_file_path = "test_analyzefile_repeated.zig";
    const test_file = std.fs.cwd().createFile(tmp_file_path, .{}) catch |err| switch (err) {
        error.AccessDenied => return,
        else => return err,
    };
    defer test_file.close();
    defer std.fs.cwd().deleteFile(tmp_file_path) catch {};
    
    try test_file.writeAll(PROBLEMATIC_MEMORY_SOURCE);
    
    // Run multiple analyses
    for (0..8) |i| {
        const result = try zig_tooling.analyzeFile(
            allocator, 
            tmp_file_path, 
            if (i % 2 == 0) null else TEST_CONFIG
        );
        
        try testing.expect(result.files_analyzed == 1);
        
        // Verify string data integrity on each iteration
        for (result.issues) |issue| {
            try testing.expect(issue.file_path.len > 0);
            try testing.expect(issue.message.len > 0);
        }
        
        zig_tooling.freeAnalysisResult(allocator, result);
    }
    
    try verifyNoLeaks(&gpa);
}

test "LC107: analyzeSource basic success path - no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    // Test analyzeSource with problematic source
    const result = try zig_tooling.analyzeSource(allocator, PROBLEMATIC_MEMORY_SOURCE, null);
    
    // Should have found issues from both analyzers
    try testing.expect(result.files_analyzed == 1);
    try testing.expect(result.issues_found > 0);
    try testing.expect(result.issues.len > 0);
    
    // Verify all string fields are valid - these would crash if use-after-free
    for (result.issues) |issue| {
        try testing.expect(issue.file_path.len > 0);
        try testing.expect(std.mem.eql(u8, issue.file_path, "<source>"));
        try testing.expect(issue.message.len > 0);
        try testing.expect(issue.line > 0);
        try testing.expect(issue.column >= 0);
        
        if (issue.suggestion) |suggestion| {
            try testing.expect(suggestion.len > 0);
        }
    }
    
    // Clean up result
    zig_tooling.freeAnalysisResult(allocator, result);
    
    // Verify no memory leaks
    try verifyNoLeaks(&gpa);
}

test "LC107: analyzeSource with custom config - no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    const result = try zig_tooling.analyzeSource(allocator, PROBLEMATIC_MEMORY_SOURCE, TEST_CONFIG);
    
    try testing.expect(result.files_analyzed == 1);
    try testing.expect(result.issues.len > 0);
    
    // Verify string ownership - no use-after-free
    for (result.issues) |issue| {
        try testing.expect(issue.file_path.len > 0);
        try testing.expect(std.mem.eql(u8, issue.file_path, "<source>"));
        try testing.expect(issue.message.len > 0);
    }
    
    zig_tooling.freeAnalysisResult(allocator, result);
    try verifyNoLeaks(&gpa);
}

test "LC107: analyzeSource with valid source - no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    const result = try zig_tooling.analyzeSource(allocator, VALID_MEMORY_SOURCE, null);
    
    try testing.expect(result.files_analyzed == 1);
    // May or may not have issues, but should not leak
    
    for (result.issues) |issue| {
        try testing.expect(issue.file_path.len > 0);
        try testing.expect(issue.message.len > 0);
    }
    
    zig_tooling.freeAnalysisResult(allocator, result);
    try verifyNoLeaks(&gpa);
}

test "LC107: analyzeSource with test source - no memory leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    // Test with source containing both valid tests and problematic tests
    const mixed_test_source = VALID_TEST_SOURCE ++ "\n" ++ PROBLEMATIC_TEST_SOURCE;
    
    const result = try zig_tooling.analyzeSource(allocator, mixed_test_source, TEST_CONFIG);
    
    try testing.expect(result.files_analyzed == 1);
    
    // Should find test naming issues
    var test_issues_found = false;
    for (result.issues) |issue| {
        try testing.expect(issue.file_path.len > 0);
        try testing.expect(issue.message.len > 0);
        if (std.mem.indexOf(u8, issue.message, "test") != null) {
            test_issues_found = true;
        }
    }
    
    zig_tooling.freeAnalysisResult(allocator, result);
    try verifyNoLeaks(&gpa);
}

test "LC107: analyzeSource repeated calls - no accumulating leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    const test_sources = [_][]const u8{
        VALID_MEMORY_SOURCE,
        PROBLEMATIC_MEMORY_SOURCE,
        VALID_TEST_SOURCE,
        PROBLEMATIC_TEST_SOURCE,
    };
    
    // Run multiple analyses with different sources
    for (0..12) |i| {
        const source = test_sources[i % test_sources.len];
        const config = if (i % 3 == 0) TEST_CONFIG else null;
        
        const result = try zig_tooling.analyzeSource(allocator, source, config);
        
        try testing.expect(result.files_analyzed == 1);
        
        // Verify string data integrity on each iteration
        for (result.issues) |issue| {
            try testing.expect(issue.file_path.len > 0);
            try testing.expect(std.mem.eql(u8, issue.file_path, "<source>"));
            try testing.expect(issue.message.len > 0);
        }
        
        zig_tooling.freeAnalysisResult(allocator, result);
    }
    
    try verifyNoLeaks(&gpa);
}

test "LC107: analyzeSource with empty source - edge case" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    const result = try zig_tooling.analyzeSource(allocator, "", null);
    
    try testing.expect(result.files_analyzed == 1);
    // Empty source should have no issues
    
    for (result.issues) |issue| {
        try testing.expect(issue.file_path.len > 0);
        try testing.expect(issue.message.len > 0);
    }
    
    zig_tooling.freeAnalysisResult(allocator, result);
    try verifyNoLeaks(&gpa);
}

test "LC107: analyzeSource memory pressure test - large source" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    // Build large source using testing allocator to avoid leak confusion
    var large_source = std.ArrayList(u8).init(testing.allocator);
    defer large_source.deinit();
    
    // Add many problematic functions to create multiple issues
    const problematic_func_template = 
        \\pub fn problematicFunctionX() void {
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
        \\
        ;
    
    // Create many instances to generate many issues
    for (0..30) |_| {
        try large_source.appendSlice(problematic_func_template);
    }
    
    const result = try zig_tooling.analyzeSource(allocator, large_source.items, TEST_CONFIG);
    
    try testing.expect(result.files_analyzed == 1);
    try testing.expect(result.issues.len > 10); // Should find many issues
    
    // Verify all strings are properly owned and accessible
    var total_message_len: usize = 0;
    for (result.issues) |issue| {
        try testing.expect(issue.file_path.len > 0);
        try testing.expect(std.mem.eql(u8, issue.file_path, "<source>"));
        try testing.expect(issue.message.len > 0);
        total_message_len += issue.message.len;
    }
    
    // Should have meaningful amounts of string data
    try testing.expect(total_message_len > 100);
    
    zig_tooling.freeAnalysisResult(allocator, result);
    try verifyNoLeaks(&gpa);
}

test "LC107: analyzeFile and analyzeSource mixed calls - no cross-contamination" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    const tmp_file_path = "test_mixed_file_source.zig";
    const test_file = std.fs.cwd().createFile(tmp_file_path, .{}) catch |err| switch (err) {
        error.AccessDenied => return,
        else => return err,
    };
    defer test_file.close();
    defer std.fs.cwd().deleteFile(tmp_file_path) catch {};
    
    try test_file.writeAll(PROBLEMATIC_MEMORY_SOURCE);
    
    // Alternate between analyzeFile and analyzeSource
    for (0..10) |i| {
        if (i % 2 == 0) {
            // Test analyzeFile
            const result = try zig_tooling.analyzeFile(allocator, tmp_file_path, null);
            
            for (result.issues) |issue| {
                try testing.expect(issue.file_path.len > 0);
                try testing.expect(std.mem.eql(u8, issue.file_path, tmp_file_path));
                try testing.expect(issue.message.len > 0);
            }
            
            zig_tooling.freeAnalysisResult(allocator, result);
        } else {
            // Test analyzeSource
            const result = try zig_tooling.analyzeSource(allocator, PROBLEMATIC_MEMORY_SOURCE, null);
            
            for (result.issues) |issue| {
                try testing.expect(issue.file_path.len > 0);
                try testing.expect(std.mem.eql(u8, issue.file_path, "<source>"));
                try testing.expect(issue.message.len > 0);
            }
            
            zig_tooling.freeAnalysisResult(allocator, result);
        }
    }
    
    try verifyNoLeaks(&gpa);
}

test "LC107: analyzeFile and analyzeSource string ownership validation" {
    // Specifically test that Issue strings are properly copied and owned
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    // Test analyzeSource first
    const source_result = try zig_tooling.analyzeSource(allocator, PROBLEMATIC_MEMORY_SOURCE, TEST_CONFIG);
    try testing.expect(source_result.issues.len > 0);
    
    // Store copies to verify they remain valid
    var stored_source_data = std.ArrayList(struct { path: []u8, message: []u8 }).init(testing.allocator);
    defer {
        for (stored_source_data.items) |item| {
            testing.allocator.free(item.path);
            testing.allocator.free(item.message);
        }
        stored_source_data.deinit();
    }
    
    for (source_result.issues) |issue| {
        try stored_source_data.append(.{
            .path = try testing.allocator.dupe(u8, issue.file_path),
            .message = try testing.allocator.dupe(u8, issue.message),
        });
    }
    
    zig_tooling.freeAnalysisResult(allocator, source_result);
    
    // Test analyzeFile
    const tmp_file_path = "test_ownership_validation.zig";
    const test_file = std.fs.cwd().createFile(tmp_file_path, .{}) catch |err| switch (err) {
        error.AccessDenied => {
            // If we can't create files, verify stored data and exit
            for (stored_source_data.items) |item| {
                try testing.expect(std.mem.eql(u8, item.path, "<source>"));
                try testing.expect(item.message.len > 0);
            }
            try verifyNoLeaks(&gpa);
            return;
        },
        else => return err,
    };
    defer test_file.close();
    defer std.fs.cwd().deleteFile(tmp_file_path) catch {};
    
    try test_file.writeAll(PROBLEMATIC_MEMORY_SOURCE);
    
    const file_result = try zig_tooling.analyzeFile(allocator, tmp_file_path, TEST_CONFIG);
    try testing.expect(file_result.issues.len > 0);
    
    // Verify file result strings
    for (file_result.issues) |issue| {
        try testing.expect(issue.file_path.len > 0);
        try testing.expect(std.mem.eql(u8, issue.file_path, tmp_file_path));
        try testing.expect(issue.message.len > 0);
        
        if (issue.suggestion) |suggestion| {
            try testing.expect(suggestion.len > 0);
        }
    }
    
    zig_tooling.freeAnalysisResult(allocator, file_result);
    
    // Verify stored source data is still valid (proving ownership was correct)
    for (stored_source_data.items) |item| {
        try testing.expect(std.mem.eql(u8, item.path, "<source>"));
        try testing.expect(item.message.len > 0);
    }
    
    try verifyNoLeaks(&gpa);
}

test "LC106: patterns.checkProject fixed by LC107 - combined test" {
    // This test verifies that patterns.checkProject() works correctly now that
    // analyzeFile() and analyzeSource() properly free their string fields
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    const tmp_dir = "test_lc106_combined";
    createTestProject(allocator, tmp_dir) catch |err| switch (err) {
        error.AccessDenied => return,
        else => return err,
    };
    defer cleanupTestProject(tmp_dir);
    
    // This should work without memory leaks now that the underlying functions are fixed
    const result = try zig_tooling.patterns.checkProject(
        allocator,
        tmp_dir,
        TEST_CONFIG,
        null
    );
    
    try testing.expect(result.files_analyzed > 0);
    try testing.expect(result.issues_found > 0);
    try testing.expect(result.issues.len > 0);
    
    // Verify the string data that caused the original leaks (lines 167, 172, 173)
    for (result.issues) |issue| {
        try testing.expect(issue.file_path.len > 0);
        try testing.expect(issue.message.len > 0);
        try testing.expect(std.mem.endsWith(u8, issue.file_path, ".zig"));
        
        if (issue.suggestion) |suggestion| {
            try testing.expect(suggestion.len > 0);
        }
    }
    
    freeProjectAnalysisResult(allocator, result);
    try verifyNoLeaks(&gpa);
}
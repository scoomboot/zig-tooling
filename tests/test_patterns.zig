const std = @import("std");
const testing = std.testing;
const zig_tooling = @import("zig_tooling");
const patterns = @import("../src/patterns.zig");

test "unit: patterns: checkSource with valid code" {
    const allocator = testing.allocator;
    
    const source =
        \\pub fn main() !void {
        \\    const allocator = std.heap.page_allocator;
        \\    const data = try allocator.alloc(u8, 100);
        \\    defer allocator.free(data);
        \\    std.debug.print("Hello, World!\n", .{});
        \\}
    ;
    
    const result = try patterns.checkSource(allocator, source, null);
    defer patterns.freeResult(allocator, result);
    
    try testing.expectEqual(@as(u32, 1), result.files_analyzed);
    try testing.expect(!result.hasErrors());
}

test "unit: patterns: checkSource detects memory issues" {
    const allocator = testing.allocator;
    
    const source =
        \\pub fn leakyFunction() !void {
        \\    const allocator = std.heap.page_allocator;
        \\    const data = try allocator.alloc(u8, 100);
        \\    // Missing defer allocator.free(data);
        \\}
    ;
    
    const result = try patterns.checkSource(allocator, source, null);
    defer patterns.freeResult(allocator, result);
    
    try testing.expect(result.issues_found > 0);
    try testing.expect(result.hasErrors());
    
    // Check that we got the expected issue type
    var found_missing_defer = false;
    for (result.issues) |issue| {
        if (issue.issue_type == .missing_defer) {
            found_missing_defer = true;
            break;
        }
    }
    try testing.expect(found_missing_defer);
}

test "unit: patterns: checkSource with custom config" {
    const allocator = testing.allocator;
    
    const source =
        \\test "sample_test" {
        \\    try std.testing.expect(true);
        \\}
    ;
    
    // Custom config that enforces test categories
    const config = zig_tooling.Config{
        .memory = .{},
        .testing = .{
            .enforce_categories = true,
            .allowed_categories = &.{ "unit", "integration" },
        },
    };
    
    const result = try patterns.checkSource(allocator, source, config);
    defer patterns.freeResult(allocator, result);
    
    // Should detect missing test category
    try testing.expect(result.issues_found > 0);
    
    var found_missing_category = false;
    for (result.issues) |issue| {
        if (issue.issue_type == .missing_test_category) {
            found_missing_category = true;
            break;
        }
    }
    try testing.expect(found_missing_category);
}

test "unit: patterns: checkFile with valid file" {
    const allocator = testing.allocator;
    
    // Create a temporary test file
    const test_file_content =
        \\pub fn add(a: i32, b: i32) i32 {
        \\    return a + b;
        \\}
        \\
        \\test "unit: add function works correctly" {
        \\    const result = add(2, 3);
        \\    try std.testing.expect(result == 5);
        \\}
    ;
    
    // Write to a temporary file
    const test_dir = testing.tmpDir(.{});
    defer test_dir.cleanup();
    
    const file = try test_dir.dir.createFile("test_add.zig", .{});
    defer file.close();
    try file.writeAll(test_file_content);
    
    // Get the full path
    const file_path = try test_dir.dir.realpathAlloc(allocator, "test_add.zig");
    defer allocator.free(file_path);
    
    const result = try patterns.checkFile(allocator, file_path, null);
    defer patterns.freeResult(allocator, result);
    
    try testing.expectEqual(@as(u32, 1), result.files_analyzed);
    // This code should be clean
    try testing.expect(!result.hasErrors());
}

test "unit: patterns: checkFile with nonexistent file" {
    const allocator = testing.allocator;
    
    const result = patterns.checkFile(allocator, "/nonexistent/file.zig", null);
    try testing.expectError(zig_tooling.AnalysisError.FileNotFound, result);
}

test "unit: patterns: checkProject with sample directory" {
    const allocator = testing.allocator;
    
    // Create a temporary directory structure
    const test_dir = testing.tmpDir(.{});
    defer test_dir.cleanup();
    
    // Create src directory with some files
    try test_dir.dir.makeDir("src");
    
    // Create a main file
    const main_content =
        \\pub fn main() !void {
        \\    const allocator = std.heap.page_allocator;
        \\    const data = try allocator.alloc(u8, 100);
        \\    defer allocator.free(data);
        \\    std.debug.print("Hello from main!\n", .{});
        \\}
    ;
    
    const main_file = try test_dir.dir.createFile("src/main.zig", .{});
    defer main_file.close();
    try main_file.writeAll(main_content);
    
    // Create a utils file  
    const utils_content =
        \\pub fn helper() void {
        \\    std.debug.print("Helper function\n", .{});
        \\}
        \\
        \\test "unit: helper function" {
        \\    helper();
        \\}
    ;
    
    const utils_file = try test_dir.dir.createFile("src/utils.zig", .{});
    defer utils_file.close();
    try utils_file.writeAll(utils_content);
    
    // Get the test directory path
    const dir_path = try test_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dir_path);
    
    // Track progress
    var progress_calls: u32 = 0;
    const ProgressTracker = struct {
        calls: *u32,
        
        fn callback(calls: *u32, files_processed: u32, total_files: u32, current_file: []const u8) void {
            _ = files_processed;
            _ = total_files;
            _ = current_file;
            calls.* += 1;
        }
    };
    
    var tracker = ProgressTracker{ .calls = &progress_calls };
    
    const result = try patterns.checkProject(
        allocator, 
        dir_path, 
        null, 
        @ptrCast(&tracker.callback)
    );
    defer patterns.freeProjectResult(allocator, result);
    
    // Should have analyzed 2 files
    try testing.expectEqual(@as(u32, 2), result.files_analyzed);
    try testing.expect(progress_calls > 0);
    
    // Files should be clean
    try testing.expect(!result.hasErrors());
    try testing.expectEqual(@as(u32, 0), result.failed_files.len);
}

test "unit: patterns: checkProject with memory issues" {
    const allocator = testing.allocator;
    
    // Create a temporary directory structure
    const test_dir = testing.tmpDir(.{});
    defer test_dir.cleanup();
    
    // Create src directory
    try test_dir.dir.makeDir("src");
    
    // Create a file with memory leak
    const leaky_content =
        \\pub fn leakyFunction() !void {
        \\    const allocator = std.heap.page_allocator;
        \\    const data = try allocator.alloc(u8, 100);
        \\    // Missing defer allocator.free(data);
        \\}
    ;
    
    const leaky_file = try test_dir.dir.createFile("src/leaky.zig", .{});
    defer leaky_file.close();
    try leaky_file.writeAll(leaky_content);
    
    // Get the test directory path
    const dir_path = try test_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dir_path);
    
    const result = try patterns.checkProject(allocator, dir_path, null, null);
    defer patterns.freeProjectResult(allocator, result);
    
    // Should have found issues
    try testing.expect(result.issues_found > 0);
    try testing.expect(result.hasErrors());
    
    // Should have analyzed 1 file
    try testing.expectEqual(@as(u32, 1), result.files_analyzed);
}

test "unit: patterns: checkProject respects exclude patterns" {
    const allocator = testing.allocator;
    
    // Create a temporary directory structure
    const test_dir = testing.tmpDir(.{});
    defer test_dir.cleanup();
    
    // Create directories
    try test_dir.dir.makeDir("src");
    try test_dir.dir.makeDir("zig-cache");
    
    // Create files in both directories
    const src_content = "pub fn main() void {}";
    const cache_content = "pub fn cached() void {}";
    
    const src_file = try test_dir.dir.createFile("src/main.zig", .{});
    defer src_file.close();
    try src_file.writeAll(src_content);
    
    const cache_file = try test_dir.dir.createFile("zig-cache/cached.zig", .{});
    defer cache_file.close();
    try cache_file.writeAll(cache_content);
    
    // Get the test directory path
    const dir_path = try test_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dir_path);
    
    const result = try patterns.checkProject(allocator, dir_path, null, null);
    defer patterns.freeProjectResult(allocator, result);
    
    // Should only analyze src file, not zig-cache file
    try testing.expectEqual(@as(u32, 1), result.files_analyzed);
}

test "unit: patterns: ProjectAnalysisResult helper methods" {
    const allocator = testing.allocator;
    
    // Create sample issues
    const issues = try allocator.alloc(zig_tooling.Issue, 3);
    defer allocator.free(issues);
    
    issues[0] = zig_tooling.Issue{
        .file_path = "test.zig",
        .line = 1,
        .column = 1,
        .issue_type = .missing_defer,
        .severity = .err,
        .message = "Error message",
    };
    
    issues[1] = zig_tooling.Issue{
        .file_path = "test.zig",
        .line = 2,
        .column = 1,
        .issue_type = .missing_test_category,
        .severity = .warning,
        .message = "Warning message",
    };
    
    issues[2] = zig_tooling.Issue{
        .file_path = "test.zig",
        .line = 3,
        .column = 1,
        .issue_type = .memory_leak,
        .severity = .err,
        .message = "Another error",
    };
    
    const result = patterns.ProjectAnalysisResult{
        .issues = issues,
        .files_analyzed = 1,
        .issues_found = 3,
        .analysis_time_ms = 100,
        .failed_files = &.{},
        .skipped_files = &.{},
    };
    
    // Test helper methods
    try testing.expect(result.hasErrors());
    try testing.expect(result.hasWarnings());
    try testing.expectEqual(@as(u32, 2), result.getErrorCount());
    try testing.expectEqual(@as(u32, 1), result.getWarningCount());
}

test "unit: patterns: checkSource uses sensible defaults" {
    const allocator = testing.allocator;
    
    // Test that checkSource works with null config (uses defaults)
    const source = "pub fn test_fn() void {}";
    const result = try patterns.checkSource(allocator, source, null);
    defer patterns.freeResult(allocator, result);
    
    try testing.expectEqual(@as(u32, 1), result.files_analyzed);
}

test "unit: patterns: memory cleanup functions work correctly" {
    const allocator = testing.allocator;
    
    // Test freeResult
    const source = "pub fn test_fn() void {}";
    const result = try patterns.checkSource(allocator, source, null);
    
    // This should not leak memory
    patterns.freeResult(allocator, result);
    
    // Test freeProjectResult  
    // Create a minimal project result
    const issues = try allocator.alloc(zig_tooling.Issue, 1);
    issues[0] = zig_tooling.Issue{
        .file_path = try allocator.dupe(u8, "test.zig"),
        .line = 1,
        .column = 1,
        .issue_type = .missing_defer,
        .severity = .err,
        .message = try allocator.dupe(u8, "Test message"),
    };
    
    const failed_files = try allocator.alloc([]const u8, 1);
    failed_files[0] = try allocator.dupe(u8, "failed.zig");
    
    const skipped_files = try allocator.alloc([]const u8, 1);
    skipped_files[0] = try allocator.dupe(u8, "skipped.zig");
    
    const project_result = patterns.ProjectAnalysisResult{
        .issues = issues,
        .files_analyzed = 1,
        .issues_found = 1,
        .analysis_time_ms = 100,
        .failed_files = failed_files,
        .skipped_files = skipped_files,
    };
    
    // This should not leak memory
    patterns.freeProjectResult(allocator, project_result);
}
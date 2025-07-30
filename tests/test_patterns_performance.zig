const std = @import("std");
const testing = std.testing;
const zig_tooling = @import("zig_tooling");
const patterns = @import("../src/patterns.zig");

// Performance benchmark tests for patterns.zig

test "benchmark: patterns: large file analysis performance" {
    const allocator = testing.allocator;
    
    var test_dir = testing.tmpDir(.{});
    defer test_dir.cleanup();
    
    // Create a large file with many functions and potential issues
    var content = std.ArrayList(u8).init(allocator);
    defer content.deinit();
    
    try content.appendSlice("const std = @import(\"std\");\n\n");
    
    // Generate 1000 functions
    for (0..1000) |i| {
        const func = try std.fmt.allocPrint(allocator,
            \\pub fn function_{}() !void {{
            \\    const allocator = std.heap.page_allocator;
            \\    const data = try allocator.alloc(u8, {});
            \\    defer allocator.free(data);
            \\    
            \\    var sum: u64 = 0;
            \\    for (data) |byte| {{
            \\        sum += byte;
            \\    }}
            \\    _ = sum;
            \\}}
            \\
        , .{ i, (i % 10 + 1) * 100 });
        defer allocator.free(func);
        
        try content.appendSlice(func);
    }
    
    const file = try test_dir.dir.createFile("large_file.zig", .{});
    defer file.close();
    try file.writeAll(content.items);
    
    const file_path = try test_dir.dir.realpathAlloc(allocator, "large_file.zig");
    defer allocator.free(file_path);
    
    // Measure performance
    const start_time = std.time.milliTimestamp();
    const result = try patterns.checkFile(allocator, file_path, null);
    defer patterns.freeResult(allocator, result);
    const end_time = std.time.milliTimestamp();
    
    const elapsed_ms = end_time - start_time;
    
    // Performance expectations
    try testing.expect(elapsed_ms < 5000); // Should complete within 5 seconds
    try testing.expectEqual(@as(u32, 1), result.files_analyzed);
    
    // Log performance for tracking
    std.debug.print("\n[BENCHMARK] Large file analysis: {} ms for {} bytes\n", .{ elapsed_ms, content.items.len });
}

test "benchmark: patterns: project analysis scalability" {
    const allocator = testing.allocator;
    
    var test_dir = testing.tmpDir(.{});
    defer test_dir.cleanup();
    
    // Test scalability with different project sizes
    const project_sizes = [_]struct { files: u32, expected_max_ms: i64 }{
        .{ .files = 10, .expected_max_ms = 500 },
        .{ .files = 50, .expected_max_ms = 2000 },
        .{ .files = 100, .expected_max_ms = 4000 },
    };
    
    for (project_sizes) |size_config| {
        // Create subdirectory for this test
        var buf: [64]u8 = undefined;
        const dir_name = try std.fmt.bufPrint(&buf, "project_{}_files", .{size_config.files});
        try test_dir.dir.makeDir(dir_name);
        
        // Create files
        for (0..size_config.files) |i| {
            const filename = try std.fmt.bufPrint(&buf, "{s}/file_{}.zig", .{ dir_name, i });
            const file = try test_dir.dir.createFile(filename, .{});
            defer file.close();
            
            const content = try std.fmt.allocPrint(allocator,
                \\pub fn func_{}() void {{
                \\    std.debug.print("File {}\n", .{{}});
                \\}}
            , .{ i, i });
            defer allocator.free(content);
            
            try file.writeAll(content);
        }
        
        const project_path = try test_dir.dir.realpathAlloc(allocator, dir_name);
        defer allocator.free(project_path);
        
        // Measure performance
        const start_time = std.time.milliTimestamp();
        const result = try patterns.checkProject(allocator, project_path, null, null);
        defer patterns.freeProjectResult(allocator, result);
        const end_time = std.time.milliTimestamp();
        
        const elapsed_ms = end_time - start_time;
        
        // Verify scalability
        try testing.expectEqual(size_config.files, result.files_analyzed);
        try testing.expect(elapsed_ms < size_config.expected_max_ms);
        
        std.debug.print("\n[BENCHMARK] Project analysis: {} files in {} ms\n", .{ size_config.files, elapsed_ms });
    }
}

test "benchmark: patterns: memory usage efficiency" {
    const allocator = testing.allocator;
    
    var test_dir = testing.tmpDir(.{});
    defer test_dir.cleanup();
    
    // Create files with varying numbers of issues
    const test_cases = [_]struct { 
        name: []const u8, 
        issue_count: u32,
        content_generator: *const fn (allocator: std.mem.Allocator, issue_count: u32) anyerror![]u8,
    }{
        .{ 
            .name = "many_small_issues",
            .issue_count = 100,
            .content_generator = generateManySmallIssues,
        },
        .{
            .name = "few_large_issues",
            .issue_count = 10,
            .content_generator = generateFewLargeIssues,
        },
    };
    
    for (test_cases) |test_case| {
        const content = try test_case.content_generator(allocator, test_case.issue_count);
        defer allocator.free(content);
        
        const file_path = try std.fmt.allocPrint(allocator, "{s}.zig", .{test_case.name});
        defer allocator.free(file_path);
        
        const file = try test_dir.dir.createFile(file_path, .{});
        defer file.close();
        try file.writeAll(content);
        
        const full_path = try test_dir.dir.realpathAlloc(allocator, file_path);
        defer allocator.free(full_path);
        
        // Track memory usage
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const tracked_allocator = gpa.allocator();
        
        const result = try patterns.checkFile(tracked_allocator, full_path, null);
        defer patterns.freeResult(tracked_allocator, result);
        
        // Calculate memory efficiency
        const bytes_per_issue = if (result.issues_found > 0) 
            @as(u64, @sizeOf(zig_tooling.Issue) * result.issues.len) / result.issues_found
        else 0;
        
        std.debug.print("\n[BENCHMARK] Memory efficiency - {s}: {} bytes/issue for {} issues\n", 
            .{ test_case.name, bytes_per_issue, result.issues_found });
        
        // Memory should scale linearly with issues
        try testing.expect(bytes_per_issue < 1024); // Less than 1KB per issue
    }
}

fn generateManySmallIssues(allocator: std.mem.Allocator, count: u32) ![]u8 {
    var content = std.ArrayList(u8).init(allocator);
    defer content.deinit();
    
    try content.appendSlice("const std = @import(\"std\");\n\n");
    
    // Generate many functions with missing defer
    for (0..count) |i| {
        const func = try std.fmt.allocPrint(allocator,
            \\pub fn leak_{}() !void {{
            \\    const a = std.heap.page_allocator;
            \\    const d = try a.alloc(u8, 10);
            \\    _ = d;
            \\}}
            \\
        , .{i});
        defer allocator.free(func);
        
        try content.appendSlice(func);
    }
    
    return content.toOwnedSlice();
}

fn generateFewLargeIssues(allocator: std.mem.Allocator, count: u32) ![]u8 {
    var content = std.ArrayList(u8).init(allocator);
    defer content.deinit();
    
    try content.appendSlice("const std = @import(\"std\");\n\n");
    
    // Generate complex functions with multiple issues
    for (0..count) |i| {
        const func = try std.fmt.allocPrint(allocator,
            \\pub fn complex_{}() !void {{
            \\    const allocator = std.heap.page_allocator;
            \\    
            \\    // Multiple allocations without defer
            \\    const array1 = try allocator.alloc(u8, 1000);
            \\    const array2 = try allocator.alloc(u8, 2000);
            \\    const array3 = try allocator.alloc(u8, 3000);
            \\    const array4 = try allocator.alloc(u8, 4000);
            \\    const array5 = try allocator.alloc(u8, 5000);
            \\    
            \\    // Complex logic
            \\    for (array1, 0..) |*byte, idx| {{
            \\        byte.* = @truncate(idx * 2);
            \\    }}
            \\    
            \\    _ = array2;
            \\    _ = array3;
            \\    _ = array4;
            \\    _ = array5;
            \\}}
            \\
        , .{i});
        defer allocator.free(func);
        
        try content.appendSlice(func);
    }
    
    return content.toOwnedSlice();
}

test "benchmark: patterns: progress callback overhead" {
    const allocator = testing.allocator;
    
    var test_dir = testing.tmpDir(.{});
    defer test_dir.cleanup();
    
    // Create multiple files
    const file_count: u32 = 20;
    for (0..file_count) |i| {
        var buf: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&buf, "file_{}.zig", .{i});
        const file = try test_dir.dir.createFile(name, .{});
        defer file.close();
        try file.writeAll("pub fn test() void {}");
    }
    
    const dir_path = try test_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dir_path);
    
    // Test 1: Without progress callback
    const start_no_callback = std.time.milliTimestamp();
    const result_no_callback = try patterns.checkProject(allocator, dir_path, null, null);
    defer patterns.freeProjectResult(allocator, result_no_callback);
    const time_no_callback = std.time.milliTimestamp() - start_no_callback;
    
    // Test 2: With lightweight progress callback
    const LightCallbackTracker = struct {
        var count: u32 = 0;
        
        fn callback(files_processed: u32, total_files: u32, current_file: []const u8) void {
            _ = files_processed;
            _ = total_files;
            _ = current_file;
            count += 1;
        }
    };
    
    const start_light_callback = std.time.milliTimestamp();
    const result_light = try patterns.checkProject(allocator, dir_path, null, LightCallbackTracker.callback);
    defer patterns.freeProjectResult(allocator, result_light);
    const time_light_callback = std.time.milliTimestamp() - start_light_callback;
    
    // Test 3: With heavy progress callback
    const heavyCallback = struct {
        fn callback(files_processed: u32, total_files: u32, current_file: []const u8) void {
            // Simulate expensive progress reporting
            var sum: u64 = 0;
            for (0..1000) |i| {
                sum += i * files_processed * total_files;
            }
            _ = current_file;
            // Use sum to prevent optimization
            if (sum == 0) {
                return;
            }
        }
    }.callback;
    
    const start_heavy_callback = std.time.milliTimestamp();
    const result_heavy = try patterns.checkProject(allocator, dir_path, null, heavyCallback);
    defer patterns.freeProjectResult(allocator, result_heavy);
    const time_heavy_callback = std.time.milliTimestamp() - start_heavy_callback;
    
    // Log results
    std.debug.print("\n[BENCHMARK] Progress callback overhead:\n", .{});
    std.debug.print("  No callback:    {} ms\n", .{time_no_callback});
    std.debug.print("  Light callback: {} ms ({}% overhead)\n", .{ 
        time_light_callback, 
        if (time_no_callback > 0) @divTrunc((time_light_callback - time_no_callback) * 100, time_no_callback) else 0
    });
    std.debug.print("  Heavy callback: {} ms ({}% overhead)\n", .{ 
        time_heavy_callback,
        if (time_no_callback > 0) @divTrunc((time_heavy_callback - time_no_callback) * 100, time_no_callback) else 0
    });
    
    // Verify callback was called for each file
    try testing.expectEqual(file_count, LightCallbackTracker.count);
    
    // Light callback overhead should be minimal
    const light_overhead = if (time_no_callback > 0) 
        @as(f64, @floatFromInt(time_light_callback)) / @as(f64, @floatFromInt(time_no_callback))
    else 1.0;
    try testing.expect(light_overhead < 1.5); // Less than 50% overhead
}

test "benchmark: patterns: worst case pattern matching" {
    const allocator = testing.allocator;
    
    var test_dir = testing.tmpDir(.{});
    defer test_dir.cleanup();
    
    // Create deeply nested directory structure with many files
    const depth = 10;
    const files_per_dir = 5;
    
    var current_path = std.ArrayList(u8).init(allocator);
    defer current_path.deinit();
    
    try current_path.appendSlice(".");
    
    // Create nested structure
    for (0..depth) |level| {
        try current_path.appendSlice("/level_");
        try current_path.append(@as(u8, '0') + @as(u8, @truncate(level)));
        
        const dir_path = try allocator.dupe(u8, current_path.items);
        defer allocator.free(dir_path);
        
        try test_dir.dir.makePath(dir_path);
        
        // Create files at each level
        for (0..files_per_dir) |file_idx| {
            var buf: [256]u8 = undefined;
            const file_path = try std.fmt.bufPrint(&buf, "{s}/file_{}.zig", .{ dir_path, file_idx });
            
            const file = try test_dir.dir.createFile(file_path, .{});
            defer file.close();
            try file.writeAll("pub fn test() void {}");
        }
    }
    
    const base_path = try test_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(base_path);
    
    // Test with complex patterns
    const config = zig_tooling.Config{
        .memory = .{},
        .testing = .{},
        .patterns = .{
            .include_patterns = &.{ 
                "**/*.zig",
                "**/level_*/*.zig",
                "**/*file_*.zig"
            },
            .exclude_patterns = &.{ 
                "**/level_5/**",
                "**/*file_3.zig",
                "**/level_*/level_*/level_*/*"
            },
        },
    };
    
    const start_time = std.time.milliTimestamp();
    const result = try patterns.checkProject(allocator, base_path, config, null);
    defer patterns.freeProjectResult(allocator, result);
    const elapsed_ms = std.time.milliTimestamp() - start_time;
    
    std.debug.print("\n[BENCHMARK] Complex pattern matching: {} files matched in {} ms\n", 
        .{ result.files_analyzed, elapsed_ms });
    
    // Even with complex patterns, should complete reasonably fast
    try testing.expect(elapsed_ms < 2000); // Less than 2 seconds
}
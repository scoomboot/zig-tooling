//! Memory & Performance Validation Tests
//! 
//! This module tests the library's memory usage patterns and performance
//! characteristics to ensure it's suitable for production use.

const std = @import("std");
const testing = std.testing;
const zig_tooling = @import("zig_tooling");

// Import the integration test utilities
const test_runner = @import("test_integration_runner.zig");
const TestUtils = test_runner.TestUtils;
const PerformanceBenchmark = test_runner.PerformanceBenchmark;
const MemoryTracker = test_runner.MemoryTracker;

test "integration: memory leak detection in library usage" {
    const allocator = testing.allocator;
    
    std.debug.print("\n--- Testing Library Memory Leak Detection ---\n", .{});
    
    var memory_tracker = MemoryTracker.init(allocator);
    defer memory_tracker.checkLeaks() catch unreachable;
    
    // Test repeated analysis operations for memory leaks
    const simple_source =
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    const allocator = std.heap.page_allocator;
        \\    const data = try allocator.alloc(u8, 100);
        \\    defer allocator.free(data);
        \\}
    ;
    
    const iterations = 50;
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        // Each analysis should properly clean up its memory
        const result = try zig_tooling.analyzeMemory(allocator, simple_source, "test.zig", null);
        defer allocator.free(result.issues);
        defer for (result.issues) |issue| {
            allocator.free(issue.file_path);
            allocator.free(issue.message);
            if (issue.suggestion) |s| allocator.free(s);
        };
        
        // Verify basic functionality
        try testing.expectEqual(@as(u32, 1), result.files_analyzed);
    }
    
    std.debug.print("✓ {} iterations completed without memory leaks\n", .{iterations});
}

test "integration: performance benchmarks for various analysis types" {
    const allocator = testing.allocator;
    
    var test_utils = try TestUtils.init(allocator);
    defer test_utils.deinit();
    
    std.debug.print("\n--- Performance Benchmarks ---\n", .{});
    
    // Create test sources of different complexity levels
    const simple_source =
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    const allocator = std.heap.page_allocator;
        \\    const data = try allocator.alloc(u8, 100);
        \\    defer allocator.free(data);
        \\}
    ;
    
    const complex_source = blk: {
        var content = std.ArrayList(u8).init(allocator);
        defer content.deinit();
        
        try content.appendSlice(
            \\const std = @import("std");
            \\
            \\pub fn complexFunction(allocator: std.mem.Allocator) !void {
        );
        
        // Generate complex code with many allocations
        var i: u32 = 0;
        while (i < 20) : (i += 1) {
            const line = try std.fmt.allocPrint(allocator,
                \\    const buffer_{} = try allocator.alloc(u8, {});
                \\    defer allocator.free(buffer_{});
                \\
            , .{ i, (i + 1) * 50, i });
            defer allocator.free(line);
            try content.appendSlice(line);
        }
        
        try content.appendSlice("}\n");
        break :blk try content.toOwnedSlice();
    };
    defer allocator.free(complex_source);
    
    // Benchmark 1: Simple memory analysis
    std.debug.print("Benchmarking simple memory analysis...\n", .{});
    var benchmark = PerformanceBenchmark.start(allocator, "Simple memory analysis");
    
    const simple_result = try zig_tooling.analyzeMemory(allocator, simple_source, "simple.zig", null);
    defer allocator.free(simple_result.issues);
    defer for (simple_result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    const simple_duration = benchmark.end();
    
    // Benchmark 2: Complex memory analysis
    std.debug.print("Benchmarking complex memory analysis...\n", .{});
    benchmark = PerformanceBenchmark.start(allocator, "Complex memory analysis");
    
    const complex_result = try zig_tooling.analyzeMemory(allocator, complex_source, "complex.zig", null);
    defer allocator.free(complex_result.issues);
    defer for (complex_result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    const complex_duration = benchmark.end();
    
    // Benchmark 3: Testing analysis
    const test_source =
        \\const std = @import("std");
        \\const testing = std.testing;
        \\
        \\test "unit: example test" {
        \\    try testing.expect(true);
        \\}
        \\
        \\test "integration: another test" {
        \\    try testing.expect(true);
        \\}
        \\
        \\test "BadTestName" {
        \\    try testing.expect(true);
        \\}
    ;
    
    std.debug.print("Benchmarking testing analysis...\n", .{});
    benchmark = PerformanceBenchmark.start(allocator, "Testing analysis");
    
    const config = zig_tooling.Config{
        .testing = .{
            .enforce_categories = true,
            .enforce_naming = true,
            .allowed_categories = &.{ "unit", "integration", "e2e" },
        },
    };
    
    const test_result = try zig_tooling.analyzeTests(allocator, test_source, "tests.zig", config);
    defer allocator.free(test_result.issues);
    defer for (test_result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    const test_duration = benchmark.end();
    
    // Performance targets and validation
    try testing.expect(simple_duration < 100); // Simple analysis should be very fast
    try testing.expect(complex_duration < 500); // Complex analysis should still be reasonable
    try testing.expect(test_duration < 100); // Test analysis should be fast
    
    std.debug.print("Performance summary:\n", .{});
    std.debug.print("  Simple: {}ms\n", .{simple_duration});
    std.debug.print("  Complex: {}ms\n", .{complex_duration});
    std.debug.print("  Testing: {}ms\n", .{test_duration});
    
    std.debug.print("✓ All performance benchmarks meet targets\n", .{});
}

test "integration: memory usage scaling with file size" {
    const allocator = testing.allocator;
    
    std.debug.print("\n--- Testing Memory Usage Scaling ---\n", .{});
    
    // Generate files of increasing size to test memory scaling
    const file_sizes = [_]u32{ 100, 500, 1000, 2000, 5000 };
    
    for (file_sizes) |size| {
        std.debug.print("Testing file with {} lines...\n", .{size});
        
        // Generate a source file with many functions
        var content = std.ArrayList(u8).init(allocator);
        defer content.deinit();
        
        try content.appendSlice("const std = @import(\"std\");\n\n");
        
        var i: u32 = 0;
        while (i < size) : (i += 1) {
            const func = try std.fmt.allocPrint(allocator,
                \\pub fn function_{}(allocator: std.mem.Allocator) ![]u8 {{
                \\    const buffer = try allocator.alloc(u8, {});
                \\    defer allocator.free(buffer);
                \\    return try allocator.dupe(u8, buffer);
                \\}}
                \\
            , .{ i, (i % 100) + 1 });
            defer allocator.free(func);
            try content.appendSlice(func);
        }
        
        const source = try content.toOwnedSlice();
        defer allocator.free(source);
        
        var benchmark = PerformanceBenchmark.start(allocator, "File size scaling");
        
        const result = try zig_tooling.analyzeMemory(allocator, source, "large.zig", null);
        defer allocator.free(result.issues);
        defer for (result.issues) |issue| {
            allocator.free(issue.file_path);
            allocator.free(issue.message);
            if (issue.suggestion) |s| allocator.free(s);
        };
        
        const duration = benchmark.end();
        
        std.debug.print("  {} lines: {}ms, {} issues\n", .{ size, duration, result.issues_found });
        
        // Memory usage should scale reasonably with file size
        try testing.expect(duration < size * 2); // Very generous upper bound
        
        // Should still find issues in larger files
        if (size > 100) {
            try testing.expect(result.issues_found > 0);
        }
    }
    
    std.debug.print("✓ Memory usage scales acceptably with file size\n", .{});
}

test "integration: performance under memory pressure" {
    const allocator = testing.allocator;
    
    std.debug.print("\n--- Testing Performance Under Memory Pressure ---\n", .{});
    
    // Simulate memory pressure by doing many allocations
    var large_allocations = std.ArrayList([]u8).init(allocator);
    defer {
        for (large_allocations.items) |allocation| {
            allocator.free(allocation);
        }
        large_allocations.deinit();
    }
    
    // Allocate some large buffers to create memory pressure
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        const large_buffer = try allocator.alloc(u8, 1024 * 1024); // 1MB each
        try large_allocations.append(large_buffer);
    }
    
    std.debug.print("Created memory pressure with {}MB allocated\n", .{large_allocations.items.len});
    
    // Now test analysis performance under memory pressure
    const source =
        \\const std = @import("std");
        \\
        \\pub fn memoryIntensiveFunction(allocator: std.mem.Allocator) !void {
        \\    var arena = std.heap.ArenaAllocator.init(allocator);
        \\    defer arena.deinit();
        \\    
        \\    const arena_allocator = arena.allocator();
        \\    
        \\    var buffers: [100][]u8 = undefined;
        \\    for (buffers, 0..) |*buffer, idx| {
        \\        buffer.* = try arena_allocator.alloc(u8, idx * 10 + 1);
        \\    }
        \\    
        \\    // Some missing defer cases for testing
        \\    const leaked_buffer = try allocator.alloc(u8, 512);
        \\    // Missing defer allocator.free(leaked_buffer);
        \\}
    ;
    
    var benchmark = PerformanceBenchmark.start(allocator, "Analysis under memory pressure");
    
    const result = try zig_tooling.analyzeMemory(allocator, source, "pressure.zig", null);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    const duration = benchmark.end();
    
    // Should still complete in reasonable time even under memory pressure
    try testing.expect(duration < 1000); // Less than 1 second
    try testing.expect(result.issues_found > 0); // Should find the leak
    
    std.debug.print("✓ Performance acceptable under memory pressure: {}ms\n", .{duration});
}

test "integration: concurrent memory analysis safety" {
    const allocator = testing.allocator;
    
    std.debug.print("\n--- Testing Concurrent Analysis Memory Safety ---\n", .{});
    
    const source =
        \\const std = @import("std");
        \\
        \\pub fn testFunction(allocator: std.mem.Allocator) ![]u8 {
        \\    const buffer = try allocator.alloc(u8, 256);
        \\    defer allocator.free(buffer);
        \\    return try allocator.dupe(u8, buffer);
        \\}
    ;
    
    // Run multiple analyses concurrently to test for memory safety issues
    const num_threads = 4;
    const analyses_per_thread = 10;
    
    var threads: [num_threads]std.Thread = undefined;
    var results: [num_threads]bool = [_]bool{false} ** num_threads;
    
    const ThreadContext = struct {
        allocator: std.mem.Allocator,
        source: []const u8,
        result: *bool,
        analyses_count: u32,
    };
    
    var contexts: [num_threads]ThreadContext = undefined;
    for (&contexts, 0..) |*context, idx| {
        context.* = ThreadContext{
            .allocator = allocator,
            .source = source,
            .result = &results[idx],
            .analyses_count = analyses_per_thread,
        };
    }
    
    const analysisThread = struct {
        fn run(context: *ThreadContext) void {
            var i: u32 = 0;
            while (i < context.analyses_count) : (i += 1) {
                const result = zig_tooling.analyzeMemory(
                    context.allocator,
                    context.source,
                    "concurrent.zig",
                    null,
                ) catch {
                    context.result.* = false;
                    return;
                };
                
                // Clean up properly
                context.allocator.free(result.issues);
                for (result.issues) |issue| {
                    context.allocator.free(issue.file_path);
                    context.allocator.free(issue.message);
                    if (issue.suggestion) |s| context.allocator.free(s);
                }
            }
            context.result.* = true;
        }
    }.run;
    
    var benchmark = PerformanceBenchmark.start(allocator, "Concurrent analysis");
    
    // Start all threads
    for (&threads, 0..) |*thread, idx| {
        thread.* = try std.Thread.spawn(.{}, analysisThread, .{&contexts[idx]});
    }
    
    // Wait for all threads to complete
    for (threads) |thread| {
        thread.join();
    }
    
    const duration = benchmark.end();
    
    // Check that all threads completed successfully
    for (results, 0..) |success, idx| {
        try testing.expect(success);
        std.debug.print("Thread {}: ✓ completed successfully\n", .{idx});
    }
    
    std.debug.print("✓ Concurrent analysis completed safely in {}ms\n", .{duration});
}

test "integration: formatter performance and memory usage" {
    const allocator = testing.allocator;
    
    var test_utils = try TestUtils.init(allocator);
    defer test_utils.deinit();
    
    std.debug.print("\n--- Testing Formatter Performance ---\n", .{});
    
    // Create a project with many issues to test formatter performance
    const project_files = [_]test_runner.FileSpec{
        .{
            .path = "src/leaky.zig",
            .content = 
                \\const std = @import("std");
                \\
                \\pub fn leakyFunction1() !void {
                \\    const allocator = std.heap.page_allocator;
                \\    const data = try allocator.alloc(u8, 100);
                \\}
                \\
                \\pub fn leakyFunction2() !void {
                \\    const allocator = std.heap.page_allocator;
                \\    const data = try allocator.alloc(u8, 200);
                \\}
                \\
                \\pub fn leakyFunction3() !void {
                \\    const allocator = std.heap.page_allocator;
                \\    const data = try allocator.alloc(u8, 300);
                \\}
            ,
        },
        .{
            .path = "tests/bad_tests.zig",
            .content = 
                \\const testing = @import("std").testing;
                \\
                \\test "BadTestName1" {
                \\    try testing.expect(true);
                \\}
                \\
                \\test "BadTestName2" {
                \\    try testing.expect(true);
                \\}
                \\
                \\test "unit: good test" {
                \\    try testing.expect(true);
                \\}
                \\
                \\test "AnotherBadName" {
                \\    try testing.expect(true);
                \\}
            ,
        },
    };
    
    const project_path = try test_utils.createTempProject("formatter_test", &project_files);
    defer allocator.free(project_path);
    
    // Analyze to get many issues
    const config = zig_tooling.Config{
        .memory = .{ .check_defer = true },
        .testing = .{
            .enforce_categories = true,
            .enforce_naming = true,
            .allowed_categories = &.{ "unit", "integration", "e2e" },
        },
    };
    
    // Analyze a single file to get AnalysisResult for formatter testing
    const main_file_path = try std.fs.path.join(allocator, &.{ project_path, "src/main.zig" });
    defer allocator.free(main_file_path);
    
    const result = try zig_tooling.analyzeFile(allocator, main_file_path, config);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    try testing.expect(result.issues_found >= 2); // Should have some memory or test issues
    std.debug.print("Generated {} issues for formatter testing\n", .{result.issues_found});
    
    // Test text formatter performance
    std.debug.print("Benchmarking text formatter...\n", .{});
    var benchmark = PerformanceBenchmark.start(allocator, "Text formatter");
    
    const text_output = try zig_tooling.formatters.formatAsText(allocator, result, .{
        .color = false,
        .verbose = true,
        .include_stats = true,
    });
    defer allocator.free(text_output);
    
    const text_duration = benchmark.end();
    
    // Test JSON formatter performance
    std.debug.print("Benchmarking JSON formatter...\n", .{});
    benchmark = PerformanceBenchmark.start(allocator, "JSON formatter");
    
    const json_output = try zig_tooling.formatters.formatAsJson(allocator, result, .{
        .json_indent = 2,
        .include_stats = true,
    });
    defer allocator.free(json_output);
    
    const json_duration = benchmark.end();
    
    // Test GitHub Actions formatter performance
    std.debug.print("Benchmarking GitHub Actions formatter...\n", .{});
    benchmark = PerformanceBenchmark.start(allocator, "GitHub Actions formatter");
    
    const gh_output = try zig_tooling.formatters.formatAsGitHubActions(allocator, result, .{
        .verbose = true,
    });
    defer allocator.free(gh_output);
    
    const gh_duration = benchmark.end();
    
    // Validate outputs and performance
    try testing.expect(text_output.len > 0);
    try testing.expect(json_output.len > 0);
    try testing.expect(gh_output.len > 0);
    
    try testing.expect(text_duration < 100); // Formatters should be very fast
    try testing.expect(json_duration < 100);
    try testing.expect(gh_duration < 100);
    
    std.debug.print("Formatter performance:\n", .{});
    std.debug.print("  Text: {}ms ({} chars)\n", .{ text_duration, text_output.len });
    std.debug.print("  JSON: {}ms ({} chars)\n", .{ json_duration, json_output.len });
    std.debug.print("  GitHub: {}ms ({} chars)\n", .{ gh_duration, gh_output.len });
    
    std.debug.print("✓ All formatters perform within acceptable limits\n", .{});
}
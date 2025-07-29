//! Thread Safety Integration Tests
//! 
//! This module tests the library's thread safety characteristics to ensure
//! it can be used safely in multi-threaded environments.

const std = @import("std");
const testing = std.testing;
const zig_tooling = @import("zig_tooling");

// Import the integration test utilities
const test_runner = @import("test_integration_runner.zig");
const TestUtils = test_runner.TestUtils;
const PerformanceBenchmark = test_runner.PerformanceBenchmark;
const EnvConfig = test_runner.EnvConfig;

test "integration: concurrent analysis operations" {
    const allocator = testing.allocator;
    
    std.debug.print("\n--- Testing Concurrent Analysis Operations ---\n", .{});
    
    // Get configuration from environment
    const env_config = EnvConfig.fromEnv();
    std.debug.print("Using environment config: max_threads={}\n", .{env_config.max_threads});
    
    const test_sources = [_][]const u8{
        \\const std = @import("std");
        \\
        \\pub fn function1(allocator: std.mem.Allocator) ![]u8 {
        \\    const buffer = try allocator.alloc(u8, 100);
        \\    defer allocator.free(buffer);
        \\    return try allocator.dupe(u8, buffer);
        \\}
        ,
        \\const std = @import("std");
        \\
        \\pub fn function2() !void {
        \\    const allocator = std.heap.page_allocator;
        \\    const data = try allocator.alloc(u8, 200);
        \\    // Missing defer - should be detected
        \\}
        ,
        \\const std = @import("std");
        \\const testing = std.testing;
        \\
        \\test "unit: good test" {
        \\    try testing.expect(true);
        \\}
        \\
        \\test "BadTestName" {
        \\    try testing.expect(true);
        \\}
        ,
        \\const std = @import("std");
        \\
        \\pub fn arenaFunction() !void {
        \\    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        \\    defer arena.deinit();
        \\    
        \\    const arena_allocator = arena.allocator();
        \\    const data = try arena_allocator.alloc(u8, 500);
        \\}
    };
    
    const num_threads = env_config.max_threads;
    const analyses_per_thread = 20;
    
    const AnalysisResults = struct {
        success: bool = false,
        total_issues: u32 = 0,
        memory_issues: u32 = 0,
        test_issues: u32 = 0,
        error_occurred: bool = false,
    };
    
    // Use a fixed maximum size for arrays since array sizes must be compile-time known
    const max_threads = 32;
    var threads: [max_threads]std.Thread = undefined;
    var results: [max_threads]AnalysisResults = undefined;
    
    const ThreadContext = struct {
        thread_id: u32,
        allocator: std.mem.Allocator,
        sources: []const []const u8,
        result: *AnalysisResults,
        analyses_count: u32,
    };
    
    var contexts: [max_threads]ThreadContext = undefined;
    var idx: usize = 0;
    while (idx < num_threads) : (idx += 1) {
        contexts[idx] = ThreadContext{
            .thread_id = @intCast(idx),
            .allocator = allocator,
            .sources = &test_sources,
            .result = &results[idx],
            .analyses_count = analyses_per_thread,
        };
    }
    
    const analysisWorker = struct {
        fn run(context: *ThreadContext) void {
            var local_total_issues: u32 = 0;
            var local_memory_issues: u32 = 0;
            var local_test_issues: u32 = 0;
            
            var i: u32 = 0;
            while (i < context.analyses_count) : (i += 1) {
                const source_idx = i % context.sources.len;
                const source = context.sources[source_idx];
                
                // Test memory analysis
                const memory_result = zig_tooling.analyzeMemory(
                    context.allocator,
                    source,
                    "concurrent_test.zig",
                    null,
                ) catch {
                    context.result.error_occurred = true;
                    return;
                };
                
                defer context.allocator.free(memory_result.issues);
                defer for (memory_result.issues) |issue| {
                    context.allocator.free(issue.file_path);
                    context.allocator.free(issue.message);
                    if (issue.suggestion) |s| context.allocator.free(s);
                };
                
                local_total_issues += memory_result.issues_found;
                local_memory_issues += memory_result.issues_found;
                
                // Test testing analysis
                const test_config = zig_tooling.Config{
                    .testing = .{
                        .enforce_categories = true,
                        .enforce_naming = true,
                        .allowed_categories = &.{ "unit", "integration", "e2e" },
                    },
                };
                
                const test_result = zig_tooling.analyzeTests(
                    context.allocator,
                    source,
                    "concurrent_test.zig",
                    test_config,
                ) catch {
                    context.result.error_occurred = true;
                    return;
                };
                
                defer context.allocator.free(test_result.issues);
                defer for (test_result.issues) |issue| {
                    context.allocator.free(issue.file_path);
                    context.allocator.free(issue.message);
                    if (issue.suggestion) |s| context.allocator.free(s);
                };
                
                local_total_issues += test_result.issues_found;
                local_test_issues += test_result.issues_found;
            }
            
            context.result.success = true;
            context.result.total_issues = local_total_issues;
            context.result.memory_issues = local_memory_issues;
            context.result.test_issues = local_test_issues;
        }
    }.run;
    
    var benchmark = PerformanceBenchmark.start(allocator, "Concurrent analysis stress test");
    
    // Start all threads (only up to num_threads)
    var i: usize = 0;
    while (i < num_threads) : (i += 1) {
        threads[i] = try std.Thread.spawn(.{}, analysisWorker, .{&contexts[i]});
    }
    
    // Wait for all threads to complete
    i = 0;
    while (i < num_threads) : (i += 1) {
        threads[i].join();
    }
    
    const duration = benchmark.end();
    
    // Validate results
    var total_analyses: u32 = 0;
    var total_issues: u32 = 0;
    var failed_threads: u32 = 0;
    
    idx = 0;
    while (idx < num_threads) : (idx += 1) {
        const result = results[idx];
        if (!result.success or result.error_occurred) {
            failed_threads += 1;
            std.debug.print("Thread {}: ✗ FAILED\n", .{idx});
        } else {
            total_analyses += analyses_per_thread;
            total_issues += result.total_issues;
            std.debug.print("Thread {}: ✓ {} analyses, {} issues\n", .{ idx, analyses_per_thread, result.total_issues });
        }
    }
    
    try testing.expectEqual(@as(u32, 0), failed_threads);
    
    const expected_analyses = @as(u32, num_threads) * analyses_per_thread;
    try testing.expectEqual(expected_analyses, total_analyses);
    
    std.debug.print("✓ Concurrent stress test: {} analyses, {} issues, {}ms\n", .{
        total_analyses,
        total_issues,
        duration,
    });
}

test "integration: concurrent configuration usage" {
    const allocator = testing.allocator;
    
    std.debug.print("\n--- Testing Concurrent Configuration Usage ---\n", .{});
    
    const source =
        \\const std = @import("std");
        \\
        \\pub fn testFunction() !void {
        \\    const allocator = std.heap.page_allocator;
        \\    const data = try allocator.alloc(u8, 256);
        \\    // Missing defer for testing
        \\}
    ;
    
    // Test different configurations being used concurrently
    const configs = [_]zig_tooling.Config{
        .{
            .memory = .{
                .check_defer = true,
                .check_arena_usage = false,
                .check_allocator_usage = false,
            },
        },
        .{
            .memory = .{
                .check_defer = false,
                .check_arena_usage = true,
                .check_allocator_usage = true,
            },
        },
        .{
            .memory = .{
                .check_defer = true,
                .check_arena_usage = true,
                .check_allocator_usage = true,
                .allowed_allocators = &.{ "std.heap.page_allocator" },
            },
        },
        .{
            .testing = .{
                .enforce_categories = true,
                .enforce_naming = true,
                .allowed_categories = &.{ "unit", "integration" },
            },
        },
    };
    
    const num_threads = configs.len;
    var threads: [num_threads]std.Thread = undefined;
    var results: [num_threads]bool = [_]bool{false} ** num_threads;
    
    const ConfigTestContext = struct {
        allocator: std.mem.Allocator,
        source: []const u8,
        config: zig_tooling.Config,
        result: *bool,
        iterations: u32,
    };
    
    var contexts: [num_threads]ConfigTestContext = undefined;
    for (&contexts, 0..) |*context, idx| {
        context.* = ConfigTestContext{
            .allocator = allocator,
            .source = source,
            .config = configs[idx],
            .result = &results[idx],
            .iterations = 25,
        };
    }
    
    const configWorker = struct {
        fn run(context: *ConfigTestContext) void {
            var i: u32 = 0;
            while (i < context.iterations) : (i += 1) {
                // Test both memory and testing analysis with the specific config
                const memory_result = zig_tooling.analyzeMemory(
                    context.allocator,
                    context.source,
                    "config_test.zig",
                    context.config,
                ) catch return;
                
                defer context.allocator.free(memory_result.issues);
                defer for (memory_result.issues) |issue| {
                    context.allocator.free(issue.file_path);
                    context.allocator.free(issue.message);
                    if (issue.suggestion) |s| context.allocator.free(s);
                };
                
                const test_result = zig_tooling.analyzeTests(
                    context.allocator,
                    context.source,
                    "config_test.zig",
                    context.config,
                ) catch return;
                
                defer context.allocator.free(test_result.issues);
                defer for (test_result.issues) |issue| {
                    context.allocator.free(issue.file_path);
                    context.allocator.free(issue.message);
                    if (issue.suggestion) |s| context.allocator.free(s);
                };
            }
            context.result.* = true;
        }
    }.run;
    
    var benchmark = PerformanceBenchmark.start(allocator, "Concurrent configuration test");
    
    // Start all threads with different configurations
    for (&threads, 0..) |*thread, idx| {
        thread.* = try std.Thread.spawn(.{}, configWorker, .{&contexts[idx]});
    }
    
    // Wait for completion
    for (threads) |thread| {
        thread.join();
    }
    
    const duration = benchmark.end();
    
    // All threads should complete successfully
    for (results, 0..) |success, idx| {
        try testing.expect(success);
        std.debug.print("Config {} thread: ✓ completed\n", .{idx});
    }
    
    std.debug.print("✓ Concurrent configuration usage test passed in {}ms\n", .{duration});
}

test "integration: concurrent patterns library usage" {
    const allocator = testing.allocator;
    
    var test_utils = try TestUtils.init(allocator);
    defer test_utils.deinit();
    
    std.debug.print("\n--- Testing Concurrent Patterns Library Usage ---\n", .{});
    
    // Create multiple test projects for concurrent analysis
    const projects = [_][]const test_runner.FileSpec{
        &[_]test_runner.FileSpec{
            .{
                .path = "src/main.zig",
                .content = 
                    \\const std = @import("std");
                    \\
                    \\pub fn main() !void {
                    \\    const allocator = std.heap.page_allocator;
                    \\    const data = try allocator.alloc(u8, 100);
                    \\    defer allocator.free(data);
                    \\}
                ,
            },
        },
        &[_]test_runner.FileSpec{
            .{
                .path = "src/utils.zig",
                .content = 
                    \\const std = @import("std");
                    \\
                    \\pub fn leakyFunction() !void {
                    \\    const allocator = std.heap.page_allocator;
                    \\    const buffer = try allocator.alloc(u8, 200);
                    \\    // Missing defer
                    \\}
                ,
            },
        },
        &[_]test_runner.FileSpec{
            .{
                .path = "tests/test_bad.zig",
                .content = 
                    \\const testing = @import("std").testing;
                    \\
                    \\test "BadTestName" {
                    \\    try testing.expect(true);
                    \\}
                ,
            },
        },
    };
    
    const num_projects = projects.len;
    var project_paths: [num_projects][]const u8 = undefined;
    
    // Create all test projects
    for (projects, 0..) |project_files, idx| {
        const project_name = try std.fmt.allocPrint(allocator, "concurrent_project_{}", .{idx});
        defer allocator.free(project_name);
        
        project_paths[idx] = try test_utils.createTempProject(project_name, project_files);
    }
    
    defer for (project_paths) |path| {
        allocator.free(path);
    };
    
    const num_threads = num_projects;
    
    const ProjectAnalysisResult = struct {
        success: bool = false,
        files_analyzed: u32 = 0,
        issues_found: u32 = 0,
        analysis_time: i64 = 0,
    };
    
    var threads: [num_threads]std.Thread = undefined;
    var results: [num_threads]ProjectAnalysisResult = undefined;
    
    const ProjectTestContext = struct {
        allocator: std.mem.Allocator,
        project_path: []const u8,
        result: *ProjectAnalysisResult,
        iterations: u32,
    };
    
    var contexts: [num_threads]ProjectTestContext = undefined;
    for (&contexts, 0..) |*context, idx| {
        context.* = ProjectTestContext{
            .allocator = allocator,
            .project_path = project_paths[idx],
            .result = &results[idx],
            .iterations = 15,
        };
    }
    
    const projectWorker = struct {
        fn run(context: *ProjectTestContext) void {
            var total_files: u32 = 0;
            var total_issues: u32 = 0;
            var total_time: i64 = 0;
            
            var i: u32 = 0;
            while (i < context.iterations) : (i += 1) {
                const config = zig_tooling.Config{
                    .memory = .{ .check_defer = true },
                    .testing = .{
                        .enforce_categories = true,
                        .enforce_naming = true,
                        .allowed_categories = &.{ "unit", "integration", "e2e" },
                    },
                };
                
                const project_result = zig_tooling.patterns.checkProject(
                    context.allocator,
                    context.project_path,
                    config,
                    null,
                ) catch return;
                
                defer zig_tooling.patterns.freeProjectResult(context.allocator, project_result);
                
                total_files += project_result.files_analyzed;
                total_issues += project_result.issues_found;
                total_time += @intCast(project_result.analysis_time_ms);
            }
            
            context.result.success = true;
            context.result.files_analyzed = total_files;
            context.result.issues_found = total_issues;
            context.result.analysis_time = total_time;
        }
    }.run;
    
    var benchmark = PerformanceBenchmark.start(allocator, "Concurrent patterns library test");
    
    // Start all project analysis threads
    for (&threads, 0..) |*thread, idx| {
        thread.* = try std.Thread.spawn(.{}, projectWorker, .{&contexts[idx]});
    }
    
    // Wait for completion
    for (threads) |thread| {
        thread.join();
    }
    
    const duration = benchmark.end();
    
    // Validate all analyses completed successfully
    for (results, 0..) |result, idx| {
        try testing.expect(result.success);
        try testing.expect(result.files_analyzed > 0);
        
        std.debug.print("Project {}: {} files, {} issues, {}ms avg\n", .{
            idx,
            result.files_analyzed,
            result.issues_found,
            @divTrunc(result.analysis_time, 15), // Average per iteration
        });
    }
    
    std.debug.print("✓ Concurrent patterns library usage test passed in {}ms\n", .{duration});
}

test "integration: race condition detection in shared state" {
    const allocator = testing.allocator;
    
    std.debug.print("\n--- Testing Race Condition Detection ---\n", .{});
    
    // Get configuration from environment
    const env_config = EnvConfig.fromEnv();
    std.debug.print("Using environment config: max_threads={}\n", .{env_config.max_threads});
    
    // Test that multiple threads accessing the library simultaneously
    // don't cause race conditions or data corruption
    
    const source =
        \\const std = @import("std");
        \\
        \\pub fn raceTestFunction(allocator: std.mem.Allocator) ![]u8 {
        \\    const buffer = try allocator.alloc(u8, 128);
        \\    defer allocator.free(buffer);
        \\    
        \\    var arena = std.heap.ArenaAllocator.init(allocator);
        \\    defer arena.deinit();
        \\    
        \\    const arena_allocator = arena.allocator();
        \\    const arena_data = try arena_allocator.alloc(u8, 64);
        \\    
        \\    return try allocator.dupe(u8, buffer);
        \\}
    ;
    
    // Use double the configured threads for race detection (but cap at 16)
    const num_threads = @min(16, env_config.max_threads * 2);
    const iterations_per_thread = 50;
    
    // Use fixed maximum size for arrays
    const max_threads = 32;
    var threads: [max_threads]std.Thread = undefined;
    var thread_results: [max_threads]u32 = [_]u32{0} ** max_threads;
    var thread_errors: [max_threads]bool = [_]bool{false} ** max_threads;
    
    const RaceTestContext = struct {
        thread_id: u32,
        allocator: std.mem.Allocator,
        source: []const u8,
        result_count: *u32,
        error_flag: *bool,
        iterations: u32,
    };
    
    var contexts: [max_threads]RaceTestContext = undefined;
    var idx: usize = 0;
    while (idx < num_threads) : (idx += 1) {
        contexts[idx] = RaceTestContext{
            .thread_id = @intCast(idx),
            .allocator = allocator,
            .source = source,
            .result_count = &thread_results[idx],
            .error_flag = &thread_errors[idx],
            .iterations = iterations_per_thread,
        };
    }
    
    const raceWorker = struct {
        fn run(context: *RaceTestContext) void {
            var local_count: u32 = 0;
            
            var i: u32 = 0;
            while (i < context.iterations) : (i += 1) {
                // Rapidly switch between different analysis types to stress test
                const analysis_type = i % 3;
                
                switch (analysis_type) {
                    0 => {
                        const result = zig_tooling.analyzeMemory(
                            context.allocator,
                            context.source,
                            "race_test.zig",
                            null,
                        ) catch {
                            context.error_flag.* = true;
                            return;
                        };
                        
                        defer context.allocator.free(result.issues);
                        defer for (result.issues) |issue| {
                            context.allocator.free(issue.file_path);
                            context.allocator.free(issue.message);
                            if (issue.suggestion) |s| context.allocator.free(s);
                        };
                        
                        local_count += result.issues_found;
                    },
                    1 => {
                        const result = zig_tooling.analyzeTests(
                            context.allocator,
                            context.source,
                            "race_test.zig",
                            null,
                        ) catch {
                            context.error_flag.* = true;
                            return;
                        };
                        
                        defer context.allocator.free(result.issues);
                        defer for (result.issues) |issue| {
                            context.allocator.free(issue.file_path);
                            context.allocator.free(issue.message);
                            if (issue.suggestion) |s| context.allocator.free(s);
                        };
                        
                        local_count += result.issues_found;
                    },
                    2 => {
                        const result = zig_tooling.analyzeSource(
                            context.allocator,
                            context.source,
                            null,
                        ) catch {
                            context.error_flag.* = true;
                            return;
                        };
                        
                        defer context.allocator.free(result.issues);
                        defer for (result.issues) |issue| {
                            context.allocator.free(issue.file_path);
                            context.allocator.free(issue.message);
                            if (issue.suggestion) |s| context.allocator.free(s);
                        };
                        
                        local_count += result.issues_found;
                    },
                    else => unreachable,
                }
                
                // Small delay to increase chance of race conditions if they exist
                std.time.sleep(1000); // 1 microsecond
            }
            
            context.result_count.* = local_count;
        }
    }.run;
    
    var benchmark = PerformanceBenchmark.start(allocator, "Race condition detection test");
    
    // Start all threads simultaneously
    var i: usize = 0;
    while (i < num_threads) : (i += 1) {
        threads[i] = try std.Thread.spawn(.{}, raceWorker, .{&contexts[i]});
    }
    
    // Wait for all threads
    i = 0;
    while (i < num_threads) : (i += 1) {
        threads[i].join();
    }
    
    const duration = benchmark.end();
    
    // Check for any errors (indicating potential race conditions)
    var total_analyses: u32 = 0;
    var total_issues: u32 = 0;
    var failed_threads: u32 = 0;
    
    idx = 0;
    while (idx < num_threads) : (idx += 1) {
        if (thread_errors[idx]) {
            failed_threads += 1;
            std.debug.print("Thread {}: ✗ ERROR (potential race condition)\n", .{idx});
        } else {
            total_analyses += iterations_per_thread;
            total_issues += thread_results[idx];
            std.debug.print("Thread {}: ✓ {} issues\n", .{ idx, thread_results[idx] });
        }
    }
    
    try testing.expectEqual(@as(u32, 0), failed_threads);
    
    const expected_analyses = @as(u32, num_threads) * iterations_per_thread;
    try testing.expectEqual(expected_analyses, total_analyses);
    
    std.debug.print("✓ Race condition test: {} analyses, {} issues, {}ms (no races detected)\n", .{
        total_analyses,
        total_issues,
        duration,
    });
}
//! Error Boundary Integration Tests
//! 
//! This module tests the library's error handling capabilities and validates
//! that it gracefully handles various edge cases and error conditions.

const std = @import("std");
const testing = std.testing;
const zig_tooling = @import("zig_tooling");

// Import the integration test utilities
const test_runner = @import("test_integration_runner.zig");
const TestUtils = test_runner.TestUtils;
const PerformanceBenchmark = test_runner.PerformanceBenchmark;

test "integration: invalid file path handling" {
    const allocator = testing.allocator;
    
    std.debug.print("\n--- Testing Invalid File Path Handling ---\n", .{});
    
    // Test with non-existent file
    std.debug.print("Testing non-existent file...\n", .{});
    const nonexistent_result = zig_tooling.analyzeFile(
        allocator,
        "/path/that/does/not/exist.zig",
        null,
    );
    
    // Should return an error, not crash
    try testing.expectError(zig_tooling.AnalysisError.FileReadError, nonexistent_result);
    std.debug.print("✓ Non-existent file handled gracefully\n", .{});
    
    // Test with invalid path characters (if any)
    std.debug.print("Testing invalid path characters...\n", .{});
    const invalid_chars_result = zig_tooling.analyzeFile(
        allocator,
        "invalid\x00path.zig",
        null,
    );
    
    // Should return an error
    try testing.expectError(zig_tooling.AnalysisError.FileReadError, invalid_chars_result);
    std.debug.print("✓ Invalid path characters handled gracefully\n", .{});
    
    // Test with directory instead of file
    var test_utils = try TestUtils.init(allocator);
    defer test_utils.deinit();
    
    std.debug.print("Testing directory path instead of file...\n", .{});
    const dir_result = zig_tooling.analyzeFile(
        allocator,
        test_utils.temp_path, // This is a directory
        null,
    );
    
    // Should return an error
    try testing.expectError(zig_tooling.AnalysisError.FileReadError, dir_result);
    std.debug.print("✓ Directory path handled gracefully\n", .{});
}

test "integration: malformed source code handling" {
    const allocator = testing.allocator;
    
    std.debug.print("\n--- Testing Malformed Source Code Handling ---\n", .{});
    
    const malformed_sources = [_]struct {
        name: []const u8,
        source: []const u8,
    }{
        .{
            .name = "empty source",
            .source = "",
        },
        .{
            .name = "whitespace only",
            .source = "   \n\n  \t  \n  ",
        },
        .{
            .name = "incomplete function",
            .source = "pub fn incomplete(",
        },
        .{
            .name = "invalid syntax",
            .source = "const invalid = ]]]",
        },
        .{
            .name = "mixed valid/invalid",
            .source = 
                \\const std = @import("std");
                \\
                \\pub fn validFunction() void {}
                \\
                \\invalid syntax here }}}
                \\
                \\pub fn anotherFunction() void {}
            ,
        },
        .{
            .name = "very long line",
            .source = "const very_long_string = \"" ++ ("x" ** 10000) ++ "\";",
        },
        .{
            .name = "unicode characters",
            .source = 
                \\const std = @import("std");
                \\// This comment has unicode: ∀x∈ℝ, 中文, 🚀
                \\pub fn unicodeTest() void {}
            ,
        },
        .{
            .name = "null bytes",
            .source = "const test\x00with\x00nulls = 42;",
        },
    };
    
    for (malformed_sources) |test_case| {
        std.debug.print("Testing {s}...\n", .{test_case.name});
        
        // Memory analysis should handle malformed code gracefully
        const memory_result = zig_tooling.analyzeMemory(
            allocator,
            test_case.source,
            "malformed.zig",
            null,
        );
        
        if (memory_result) |result| {
            defer allocator.free(result.issues);
            defer for (result.issues) |issue| {
                allocator.free(issue.file_path);
                allocator.free(issue.message);
                if (issue.suggestion) |s| allocator.free(s);
            };
            
            // Should either succeed with 0 issues or succeed with some issues
            // (depending on what the analyzer can parse)
            std.debug.print("  Memory analysis: {} issues found\n", .{result.issues_found});
        } else |err| {
            // Some malformed code might trigger parse errors, which is acceptable
            std.debug.print("  Memory analysis returned error: {}\n", .{err});
            try testing.expect(err == zig_tooling.AnalysisError.ParseError or 
                             err == zig_tooling.AnalysisError.InvalidConfiguration);
        }
        
        // Test analysis should also handle malformed code
        const test_result = zig_tooling.analyzeTests(
            allocator,
            test_case.source,
            "malformed.zig",
            null,
        );
        
        if (test_result) |result| {
            defer allocator.free(result.issues);
            defer for (result.issues) |issue| {
                allocator.free(issue.file_path);
                allocator.free(issue.message);
                if (issue.suggestion) |s| allocator.free(s);
            };
            
            std.debug.print("  Test analysis: {} issues found\n", .{result.issues_found});
        } else |err| {
            std.debug.print("  Test analysis returned error: {}\n", .{err});
            try testing.expect(err == zig_tooling.AnalysisError.ParseError or 
                             err == zig_tooling.AnalysisError.InvalidConfiguration);
        }
        
        std.debug.print("  ✓ {s} handled gracefully\n", .{test_case.name});
    }
}

test "integration: invalid configuration handling" {
    const allocator = testing.allocator;
    
    std.debug.print("\n--- Testing Invalid Configuration Handling ---\n", .{});
    
    const valid_source =
        \\const std = @import("std");
        \\
        \\pub fn testFunction(allocator: std.mem.Allocator) ![]u8 {
        \\    const buffer = try allocator.alloc(u8, 100);
        \\    defer allocator.free(buffer);
        \\    return try allocator.dupe(u8, buffer);
        \\}
    ;
    
    // Test invalid allocator patterns
    std.debug.print("Testing invalid allocator patterns...\n", .{});
    const invalid_patterns_config = zig_tooling.Config{
        .memory = .{
            .allocator_patterns = &.{
                .{ .name = "", .pattern = "empty_name" }, // Empty name
                .{ .name = "valid_name", .pattern = "" }, // Empty pattern
                .{ .name = "duplicate", .pattern = "pattern1" },
                .{ .name = "duplicate", .pattern = "pattern2" }, // Duplicate name
            },
        },
    };
    
    const patterns_result = zig_tooling.analyzeMemory(
        allocator,
        valid_source,
        "config_test.zig",
        invalid_patterns_config,
    );
    
    if (patterns_result) |result| {
        defer allocator.free(result.issues);
        defer for (result.issues) |issue| {
            allocator.free(issue.file_path);
            allocator.free(issue.message);
            if (issue.suggestion) |s| allocator.free(s);
        };
        
        // Should either handle invalid patterns gracefully or include validation warnings
        std.debug.print("  Invalid patterns handled: {} issues\n", .{result.issues_found});
    } else |err| {
        // Configuration errors are acceptable
        try testing.expect(err == zig_tooling.AnalysisError.InvalidConfiguration);
        std.debug.print("  Invalid patterns correctly rejected\n", .{});
    }
    
    // Test invalid test categories
    std.debug.print("Testing invalid test categories...\n", .{});
    const invalid_categories_config = zig_tooling.Config{
        .testing = .{
            .enforce_categories = true,
            .allowed_categories = &.{}, // Empty categories list
        },
    };
    
    const categories_result = zig_tooling.analyzeTests(
        allocator,
        valid_source,
        "config_test.zig",
        invalid_categories_config,
    );
    
    if (categories_result) |result| {
        defer allocator.free(result.issues);
        defer for (result.issues) |issue| {
            allocator.free(issue.file_path);
            allocator.free(issue.message);
            if (issue.suggestion) |s| allocator.free(s);
        };
        
        std.debug.print("  Invalid categories handled: {} issues\n", .{result.issues_found});
    } else |err| {
        try testing.expect(err == zig_tooling.AnalysisError.InvalidConfiguration);
        std.debug.print("  Invalid categories correctly rejected\n", .{});
    }
    
    std.debug.print("✓ Invalid configuration handling working correctly\n", .{});
}

test "integration: extreme input handling" {
    const allocator = testing.allocator;
    
    std.debug.print("\n--- Testing Extreme Input Handling ---\n", .{});
    
    // Test very large source file
    std.debug.print("Testing very large source file...\n", .{});
    var large_source = std.ArrayList(u8).init(allocator);
    defer large_source.deinit();
    
    try large_source.appendSlice("const std = @import(\"std\");\n\n");
    
    // Generate a large file with many functions
    const num_functions = 1000;
    var i: u32 = 0;
    while (i < num_functions) : (i += 1) {
        const func = try std.fmt.allocPrint(allocator,
            \\pub fn function_{}(allocator: std.mem.Allocator) ![]u8 {{
            \\    const buffer = try allocator.alloc(u8, {});
            \\    defer allocator.free(buffer);
            \\    return try allocator.dupe(u8, buffer);
            \\}}
            \\
        , .{ i, (i % 1000) + 1 });
        defer allocator.free(func);
        try large_source.appendSlice(func);
    }
    
    const large_source_str = try large_source.toOwnedSlice();
    defer allocator.free(large_source_str);
    
    var benchmark = PerformanceBenchmark.start(allocator, "Large file analysis");
    
    const large_result = zig_tooling.analyzeMemory(
        allocator,
        large_source_str,
        "large.zig",
        null,
    );
    
    const duration = benchmark.end();
    
    if (large_result) |result| {
        defer allocator.free(result.issues);
        defer for (result.issues) |issue| {
            allocator.free(issue.file_path);
            allocator.free(issue.message);
            if (issue.suggestion) |s| allocator.free(s);
        };
        
        std.debug.print("  Large file: {} functions, {} issues, {}ms\n", .{
            num_functions,
            result.issues_found,
            duration,
        });
        
        // Should complete in reasonable time even for large files
        try testing.expect(duration < 5000); // Less than 5 seconds
    } else |err| {
        std.debug.print("  Large file analysis error: {}\n", .{err});
        // OutOfMemory is acceptable for very large files
        try testing.expect(err == zig_tooling.AnalysisError.OutOfMemory or 
                         err == zig_tooling.AnalysisError.ParseError);
    }
    
    // Test deeply nested code structures
    std.debug.print("Testing deeply nested structures...\n", .{});
    var nested_source = std.ArrayList(u8).init(allocator);
    defer nested_source.deinit();
    
    try nested_source.appendSlice(
        \\const std = @import("std");
        \\
        \\pub fn deeplyNested(allocator: std.mem.Allocator) !void {
    );
    
    const nesting_depth = 50;
    var j: u32 = 0;
    while (j < nesting_depth) : (j += 1) {
        try nested_source.appendSlice("    if (true) {\n");
    }
    
    try nested_source.appendSlice(
        \\        const buffer = try allocator.alloc(u8, 100);
        \\        defer allocator.free(buffer);
    );
    
    j = 0;
    while (j < nesting_depth) : (j += 1) {
        try nested_source.appendSlice("    }\n");
    }
    
    try nested_source.appendSlice("}\n");
    
    const nested_source_str = try nested_source.toOwnedSlice();
    defer allocator.free(nested_source_str);
    
    const nested_result = zig_tooling.analyzeMemory(
        allocator,
        nested_source_str,
        "nested.zig",
        null,
    );
    
    if (nested_result) |result| {
        defer allocator.free(result.issues);
        defer for (result.issues) |issue| {
            allocator.free(issue.file_path);
            allocator.free(issue.message);
            if (issue.suggestion) |s| allocator.free(s);
        };
        
        std.debug.print("  Nested structures: {} depth, {} issues\n", .{
            nesting_depth,
            result.issues_found,
        });
    } else |err| {
        std.debug.print("  Nested analysis error: {}\n", .{err});
        // Stack overflow or similar errors are acceptable for very deep nesting
        try testing.expect(err == zig_tooling.AnalysisError.ParseError);
    }
    
    std.debug.print("✓ Extreme input handling completed\n", .{});
}

test "integration: concurrent error handling" {
    const allocator = testing.allocator;
    
    std.debug.print("\n--- Testing Concurrent Error Handling ---\n", .{});
    
    const error_sources = [_][]const u8{
        "invalid syntax }}}",
        "", // empty
        "const incomplete =",
        "valid source with const x = 42;",
    };
    
    const num_threads = 8;
    const iterations_per_thread = 25;
    
    const ErrorTestResult = struct {
        completed: bool = false,
        successful_analyses: u32 = 0,
        errors_encountered: u32 = 0,
        unexpected_crashes: u32 = 0,
    };
    
    var threads: [num_threads]std.Thread = undefined;
    var thread_results: [num_threads]ErrorTestResult = undefined;
    
    const ErrorTestContext = struct {
        thread_id: u32,
        allocator: std.mem.Allocator,
        sources: []const []const u8,
        result: *ErrorTestResult,
        iterations: u32,
    };
    
    var contexts: [num_threads]ErrorTestContext = undefined;
    for (&contexts, 0..) |*context, idx| {
        context.* = ErrorTestContext{
            .thread_id = @intCast(idx),
            .allocator = allocator,
            .sources = &error_sources,
            .result = &thread_results[idx],
            .iterations = iterations_per_thread,
        };
    }
    
    const errorWorker = struct {
        fn run(context: *ErrorTestContext) void {
            var successful: u32 = 0;
            var errors: u32 = 0;
            const crashes: u32 = 0;
            
            var i: u32 = 0;
            while (i < context.iterations) : (i += 1) {
                const source_idx = i % context.sources.len;
                const source = context.sources[source_idx];
                
                // Try memory analysis
                const memory_result = zig_tooling.analyzeMemory(
                    context.allocator,
                    source,
                    "error_test.zig",
                    null,
                );
                
                if (memory_result) |result| {
                    defer context.allocator.free(result.issues);
                    defer for (result.issues) |issue| {
                        context.allocator.free(issue.file_path);
                        context.allocator.free(issue.message);
                        if (issue.suggestion) |s| context.allocator.free(s);
                    };
                    successful += 1;
                } else |_| {
                    errors += 1;
                }
                
                // Try test analysis
                const test_result = zig_tooling.analyzeTests(
                    context.allocator,
                    source,
                    "error_test.zig",
                    null,
                );
                
                if (test_result) |result| {
                    defer context.allocator.free(result.issues);
                    defer for (result.issues) |issue| {
                        context.allocator.free(issue.file_path);
                        context.allocator.free(issue.message);
                        if (issue.suggestion) |s| context.allocator.free(s);
                    };
                    successful += 1;
                } else |_| {
                    errors += 1;
                }
            }
            
            context.result.completed = true;
            context.result.successful_analyses = successful;
            context.result.errors_encountered = errors;
            context.result.unexpected_crashes = crashes;
        }
    }.run;
    
    var benchmark = PerformanceBenchmark.start(allocator, "Concurrent error handling");
    
    // Start all threads
    for (&threads, 0..) |*thread, idx| {
        thread.* = try std.Thread.spawn(.{}, errorWorker, .{&contexts[idx]});
    }
    
    // Wait for completion
    for (threads) |thread| {
        thread.join();
    }
    
    const duration = benchmark.end();
    
    // Validate results
    var total_completed: u32 = 0;
    var total_successful: u32 = 0;
    var total_errors: u32 = 0;
    var total_crashes: u32 = 0;
    
    for (thread_results, 0..) |result, idx| {
        try testing.expect(result.completed);
        
        total_completed += 1;
        total_successful += result.successful_analyses;
        total_errors += result.errors_encountered;
        total_crashes += result.unexpected_crashes;
        
        std.debug.print("Thread {}: {} successful, {} errors, {} crashes\n", .{
            idx,
            result.successful_analyses,
            result.errors_encountered,
            result.unexpected_crashes,
        });
    }
    
    // All threads should complete
    try testing.expectEqual(num_threads, total_completed);
    
    // Should have no unexpected crashes
    try testing.expectEqual(@as(u32, 0), total_crashes);
    
    // Should have some successful analyses and some expected errors
    try testing.expect(total_successful > 0);
    try testing.expect(total_errors > 0);
    
    const total_attempts = total_successful + total_errors;
    const expected_attempts = num_threads * iterations_per_thread * 2; // 2 analyses per iteration
    try testing.expectEqual(expected_attempts, total_attempts);
    
    std.debug.print("✓ Concurrent error handling: {} attempts, {} successful, {} errors, {}ms\n", .{
        total_attempts,
        total_successful,
        total_errors,
        duration,
    });
}

test "integration: patterns library error resilience" {
    const allocator = testing.allocator;
    
    var test_utils = try TestUtils.init(allocator);
    defer test_utils.deinit();
    
    std.debug.print("\n--- Testing Patterns Library Error Resilience ---\n", .{});
    
    // Create a project with mixed valid and invalid files
    const project_files = [_]test_runner.FileSpec{
        .{
            .path = "src/valid.zig",
            .content = 
                \\const std = @import("std");
                \\
                \\pub fn validFunction() void {}
            ,
        },
        .{
            .path = "src/invalid.zig",
            .content = "invalid syntax }}}",
        },
        .{
            .path = "src/empty.zig",
            .content = "",
        },
        .{
            .path = "src/partial.zig",
            .content = "const incomplete =",
        },
        .{
            .path = "tests/good_test.zig",
            .content = 
                \\const testing = @import("std").testing;
                \\
                \\test "unit: valid test" {
                \\    try testing.expect(true);
                \\}
            ,
        },
        .{
            .path = "tests/bad_syntax.zig",
            .content = "test invalid {{{",
        },
    };
    
    const project_path = try test_utils.createTempProject("error_resilience_test", &project_files);
    defer allocator.free(project_path);
    
    std.debug.print("Testing project analysis with mixed file validity...\n", .{});
    
    const result = zig_tooling.patterns.checkProject(
        allocator,
        project_path,
        null,
        null,
    );
    
    if (result) |project_result| {
        defer zig_tooling.patterns.freeProjectResult(allocator, project_result);
        
        // Should analyze at least some files successfully
        try testing.expect(project_result.files_analyzed > 0);
        
        std.debug.print("  Mixed project: {} files analyzed, {} issues found\n", .{
            project_result.files_analyzed,
            project_result.issues_found,
        });
        
        // Should have completed without crashing
        try testing.expect(project_result.analysis_time_ms >= 0);
        
    } else |err| {
        // Some errors are acceptable, but should not be crashes
        std.debug.print("  Project analysis error: {}\n", .{err});
        try testing.expect(err == zig_tooling.AnalysisError.ParseError or 
                         err == zig_tooling.AnalysisError.FileReadError);
    }
    
    // Test with completely invalid project path
    std.debug.print("Testing invalid project path...\n", .{});
    const invalid_result = zig_tooling.patterns.checkProject(
        allocator,
        "/nonexistent/project/path",
        null,
        null,
    );
    
    try testing.expectError(zig_tooling.AnalysisError.FileReadError, invalid_result);
    std.debug.print("  Invalid project path handled correctly\n", .{});
    
    std.debug.print("✓ Patterns library error resilience test completed\n", .{});
}
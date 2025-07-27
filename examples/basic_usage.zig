//! Basic Usage Example - Getting Started with zig-tooling
//!
//! This example demonstrates the simplest way to use zig-tooling to analyze
//! Zig source code for memory safety issues and testing compliance.

const std = @import("std");
const zig_tooling = @import("zig_tooling");

pub fn main() !void {
    // Initialize allocator - in real usage, choose appropriate allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Example 1: Analyze a single file
    try analyzeFile(allocator);
    std.debug.print("\n", .{});

    // Example 2: Analyze source code directly
    try analyzeSourceCode(allocator);
    std.debug.print("\n", .{});

    // Example 3: Use convenience patterns
    try usePatterns(allocator);
    std.debug.print("\n", .{});

    // Example 4: Custom configuration
    try customConfiguration(allocator);
}

/// Example 1: Analyze a file from disk
fn analyzeFile(allocator: std.mem.Allocator) !void {
    std.debug.print("=== Example 1: Analyzing a file ===\n", .{});

    // Analyze the sample memory issues file
    const result = try zig_tooling.analyzeFile(
        allocator,
        "examples/sample_project/memory_issues.zig",
        null, // Use default configuration
    );
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };

    // Check results
    if (result.hasErrors()) {
        std.debug.print("Found {} errors and {} warnings\n", .{
            result.getErrorCount(),
            result.getWarningCount(),
        });

        // Display issues
        for (result.issues) |issue| {
            std.debug.print("{s}:{}:{}: {s}: {s}\n", .{
                issue.file_path,
                issue.line,
                issue.column,
                @tagName(issue.severity),
                issue.message,
            });
        }
    } else {
        std.debug.print("No issues found!\n", .{});
    }
}

/// Example 2: Analyze source code directly (without file I/O)
fn analyzeSourceCode(allocator: std.mem.Allocator) !void {
    std.debug.print("=== Example 2: Analyzing source code directly ===\n", .{});

    const source_code =
        \\const std = @import("std");
        \\
        \\pub fn leakyFunction(allocator: std.mem.Allocator) ![]u8 {
        \\    const buffer = try allocator.alloc(u8, 1024);
        \\    // Missing defer allocator.free(buffer);
        \\    return buffer;
        \\}
        \\
        \\test "unit: missing category" {
        \\    // This test is missing a category
        \\    try std.testing.expect(true);
        \\}
    ;

    // Analyze just memory issues
    const memory_result = try zig_tooling.analyzeMemory(
        allocator,
        source_code,
        "inline_code.zig",
        null,
    );
    defer allocator.free(memory_result.issues);
    defer for (memory_result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };

    std.debug.print("Memory analysis found {} issues\n", .{memory_result.issues_found});

    // Analyze just testing compliance
    const test_result = try zig_tooling.analyzeTests(
        allocator,
        source_code,
        "inline_code.zig",
        null,
    );
    defer allocator.free(test_result.issues);
    defer for (test_result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };

    std.debug.print("Test analysis found {} issues\n", .{test_result.issues_found});
}

/// Example 3: Use high-level patterns for common scenarios
fn usePatterns(allocator: std.mem.Allocator) !void {
    std.debug.print("=== Example 3: Using patterns library ===\n", .{});

    // Quick file check with optimized defaults
    const result = try zig_tooling.patterns.checkFile(
        allocator,
        "examples/sample_project/test_examples.zig",
        null,
    );
    defer zig_tooling.patterns.freeResult(allocator, result);

    // The patterns library provides convenience methods
    std.debug.print("Analysis completed in {}ms\n", .{result.analysis_time_ms});
    std.debug.print("Found {} issues (errors: {}, warnings: {})\n", .{
        result.issues_found,
        result.getErrorCount(),
        result.getWarningCount(),
    });

    // Format results as text
    const output = try zig_tooling.formatters.formatAsText(allocator, result, .{
        .color = false, // Disable color for example output
        .verbose = true,
    });
    defer allocator.free(output);

    std.debug.print("\nFormatted output:\n{s}\n", .{output});
}

/// Example 4: Custom configuration
fn customConfiguration(allocator: std.mem.Allocator) !void {
    std.debug.print("=== Example 4: Custom configuration ===\n", .{});

    // Create custom configuration
    const config = zig_tooling.Config{
        .memory = .{
            // Only check for missing defer statements
            .check_defer = true,
            .check_arena_usage = false,
            .check_allocator_usage = false,
            
            // Only allow specific allocators
            .allowed_allocators = &.{ 
                "std.heap.GeneralPurposeAllocator",
                "std.testing.allocator",
            },
            
            // Custom allocator patterns
            .allocator_patterns = &.{
                .{ .name = "MyCustomAllocator", .pattern = "custom_alloc" },
            },
        },
        .testing = .{
            // Enforce test categories
            .enforce_categories = true,
            .enforce_naming = true,
            
            // Define allowed test categories
            .allowed_categories = &.{ "unit", "integration", "e2e" },
        },
        .options = .{
            // Limit output
            .max_issues = 10,
            .verbose = true,
            .continue_on_error = true,
        },
        .logging = .{
            // Enable logging to stderr
            .enabled = true,
            .callback = zig_tooling.stderrLogCallback,
            .min_level = .warn,
        },
    };

    // Create a source file with various issues
    const test_source =
        \\const std = @import("std");
        \\
        \\// Custom allocator that should be allowed
        \\var custom_alloc = MyCustomAllocator.init();
        \\
        \\pub fn example(allocator: std.mem.Allocator) !void {
        \\    const data = try allocator.alloc(u8, 100);
        \\    // Will trigger missing defer warning
        \\}
        \\
        \\test "integration: custom allocator" {
        \\    // This test has proper categorization
        \\    const allocator = custom_alloc.allocator();
        \\    try std.testing.expect(true);
        \\}
        \\
        \\test "bad test name" {
        \\    // Will trigger naming convention warning
        \\    try std.testing.expect(true);
        \\}
    ;

    // Analyze with custom configuration
    const result = try zig_tooling.analyzeSource(
        allocator,
        test_source,
        config,
    );
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };

    std.debug.print("Custom analysis found {} issues\n", .{result.issues_found});

    // Use JSON formatter for structured output
    const json_output = try zig_tooling.formatters.formatAsJson(allocator, result, .{
        .json_indent = 2,
        .include_stats = true,
    });
    defer allocator.free(json_output);

    std.debug.print("\nJSON output:\n{s}\n", .{json_output});
}
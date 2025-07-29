const std = @import("std");
const zig_tooling = @import("zig_tooling");

const CheckMode = enum {
    all,
    memory,
    tests,
};

const OutputFormat = enum {
    text,
    json,
    github_actions,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var check_mode: CheckMode = .all;
    var output_format: OutputFormat = .text;
    var fail_on_warnings = false;

    // Simple argument parsing
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--check")) {
            i += 1;
            if (i < args.len) {
                if (std.mem.eql(u8, args[i], "memory")) {
                    check_mode = .memory;
                } else if (std.mem.eql(u8, args[i], "tests")) {
                    check_mode = .tests;
                } else if (std.mem.eql(u8, args[i], "all")) {
                    check_mode = .all;
                }
            }
        } else if (std.mem.eql(u8, args[i], "--format")) {
            i += 1;
            if (i < args.len) {
                if (std.mem.eql(u8, args[i], "text")) {
                    output_format = .text;
                } else if (std.mem.eql(u8, args[i], "json")) {
                    output_format = .json;
                } else if (std.mem.eql(u8, args[i], "github-actions")) {
                    output_format = .github_actions;
                }
            }
        } else if (std.mem.eql(u8, args[i], "--fail-on-warnings")) {
            fail_on_warnings = true;
        } else if (std.mem.eql(u8, args[i], "--help")) {
            printHelp();
            return;
        }
    }

    // Configure analysis based on project needs
    var config = zig_tooling.Config{
        .memory = .{
            // Enable all memory checks
            .check_defer = true,
            .check_arena_usage = true,
            .check_allocator_usage = true,
            
            // Configure allowed allocators for this project
            .allowed_allocators = &.{
                "std.heap.GeneralPurposeAllocator",
                "std.heap.ArenaAllocator",
                "std.testing.allocator",
            },
        },
        .testing = .{
            // Enforce test organization
            .enforce_categories = true,
            .enforce_naming = true,
            
            // Define test categories used in this project
            .allowed_categories = &.{ "unit", "integration", "e2e", "perf" },
        },
        .options = .{
            // Limit output for readability
            .max_issues = 50,
            .verbose = true,
            .continue_on_error = true,
        },
    };

    // Disable checks based on mode
    switch (check_mode) {
        .memory => config.testing = .{},
        .tests => config.memory = .{},
        .all => {}, // Keep both enabled
    }

    // Run analysis
    const stderr = std.io.getStdErr().writer();
    try stderr.print("Running {} analysis...\n", .{check_mode});

    const result = try zig_tooling.patterns.checkProject(
        allocator,
        ".",
        config,
        progressCallback,
    );
    defer zig_tooling.patterns.freeProjectResult(allocator, result);

    // Format output based on requested format
    const output = switch (output_format) {
        .text => try zig_tooling.formatters.formatAsText(allocator, result, .{
            .color = std.io.tty.detectConfig(std.io.getStdOut()) != .none,
            .verbose = true,
            .max_issues = 50,
        }),
        .json => try zig_tooling.formatters.formatAsJson(allocator, result, .{
            .json_indent = 2,
            .include_stats = true,
        }),
        .github_actions => try zig_tooling.formatters.formatAsGitHubActions(allocator, result, .{
            .verbose = false,
        }),
    };
    defer allocator.free(output);

    // Output results
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(output);

    // Print summary to stderr for text format
    if (output_format == .text) {
        try stderr.print("\n", .{});
        try stderr.print("Summary: {} files analyzed in {}ms\n", .{
            result.files_analyzed,
            result.analysis_time_ms,
        });
        
        if (result.hasErrors() or result.hasWarnings()) {
            try stderr.print("Found {} errors and {} warnings\n", .{
                result.getErrorCount(),
                result.getWarningCount(),
            });
        } else {
            try stderr.print("✓ All checks passed!\n", .{});
        }
    }

    // Exit with appropriate code
    if (result.hasErrors() or (fail_on_warnings and result.hasWarnings())) {
        std.process.exit(1);
    }
}

fn progressCallback(files_processed: u32, total_files: u32, current_file: []const u8) void {
    // Clear line and show progress
    const stderr = std.io.getStdErr().writer();
    stderr.print("\r\x1B[K", .{}) catch {}; // Clear line
    stderr.print("Analyzing {}/{}: {s}", .{
        files_processed + 1,
        total_files,
        truncatePath(current_file, 50),
    }) catch {};
}

fn truncatePath(path: []const u8, max_len: usize) []const u8 {
    if (path.len <= max_len) return path;
    
    const start_len = max_len / 3;
    const end_len = max_len - start_len - 3; // 3 for "..."
    
    return path[0..start_len] ++ "..." ++ path[path.len - end_len..];
}

fn printHelp() void {
    const stdout = std.io.getStdOut().writer();
    stdout.print(
        \\Quality Check Tool - Powered by zig-tooling
        \\
        \\USAGE:
        \\    quality_check [OPTIONS]
        \\
        \\OPTIONS:
        \\    --check <mode>         Analysis mode: all, memory, tests (default: all)
        \\    --format <format>      Output format: text, json, github-actions (default: text)
        \\    --fail-on-warnings     Exit with error code if warnings are found
        \\    --help                 Show this help message
        \\
        \\EXAMPLES:
        \\    # Run all checks with text output
        \\    quality_check
        \\
        \\    # Run only memory checks
        \\    quality_check --check memory
        \\
        \\    # Output JSON for CI integration
        \\    quality_check --format json
        \\
        \\    # GitHub Actions integration
        \\    quality_check --format github-actions --fail-on-warnings
        \\
    , .{}) catch {};
}
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
    var fail_on_warnings = true; // Default to failing on warnings for quality checks

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
        } else if (std.mem.eql(u8, args[i], "--no-fail-on-warnings")) {
            fail_on_warnings = false;
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
                "testing.allocator",
            },
            
            // Define custom ownership patterns to reduce false positives
            .ownership_patterns = &.{
                .{ .function_pattern = "create", .description = "Factory functions" },
                .{ .function_pattern = "init", .description = "Initializers" },
                .{ .function_pattern = "dupe", .description = "Duplication functions" },
                .{ .function_pattern = "alloc", .description = "Allocation functions" },
            },
        },
        .testing = .{
            // Enforce test organization
            .enforce_categories = true,
            .enforce_naming = true,
            
            // Define test categories used in this project
            .allowed_categories = &.{ "unit", "integration", "e2e", "performance" },
        },
        .patterns = .{
            // Exclude common build and cache directories
            .exclude_patterns = &.{
                "**/zig-cache/**",
                "**/zig-out/**",
                "**/.zig-cache/**",
            },
        },
        .options = .{
            // Limit output for readability
            .max_issues = 100,
            .verbose = true,
            .continue_on_error = true,
            .fail_on_warnings = fail_on_warnings,
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
    try stderr.print("Running {} analysis on zig-tooling library...\n", .{check_mode});

    // Use patterns.checkProject for comprehensive analysis
    const result = try zig_tooling.patterns.checkProject(
        allocator,
        ".",
        config,
        progressCallback,
    );
    defer zig_tooling.patterns.freeProjectResult(allocator, result);

    // Format output based on requested format
    const output = switch (output_format) {
        .text => try zig_tooling.formatters.formatProjectAsText(allocator, result, .{
            .color = switch (std.io.tty.detectConfig(std.io.getStdOut())) {
                .no_color => false,
                .escape_codes => true,
                .windows_api => true,
            },
            .verbose = true,
            .max_issues = 100,
        }),
        .json => try zig_tooling.formatters.formatProjectAsJson(allocator, result, .{
            .json_indent = 2,
            .include_stats = true,
        }),
        .github_actions => try zig_tooling.formatters.formatProjectAsGitHubActions(allocator, result, .{
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
    
    // Truncate path inline without allocations for progress display
    const display_path = if (current_file.len <= 50) current_file else blk: {
        const start_len = 17; // 50 / 3
        const end_len = 30;   // 50 - 17 - 3
        // Use a static buffer for the truncated path display
        var static_buf: [53]u8 = undefined; // 17 + 3 + 30 + null terminator space
        const result = std.fmt.bufPrint(&static_buf, "{s}...{s}", .{
            current_file[0..start_len],
            current_file[current_file.len - end_len..]
        }) catch current_file[0..@min(current_file.len, 50)];
        break :blk result;
    };
    
    stderr.print("Analyzing {}/{}: {s}", .{
        files_processed + 1,
        total_files,
        display_path,
    }) catch {};
}

fn printHelp() void {
    const stdout = std.io.getStdOut().writer();
    stdout.print(
        \\zig-tooling Quality Check Tool
        \\
        \\USAGE:
        \\    quality_check [OPTIONS]
        \\
        \\OPTIONS:
        \\    --check <mode>         Analysis mode: all, memory, tests (default: all)
        \\    --format <format>      Output format: text, json, github-actions (default: text)
        \\    --no-fail-on-warnings  Don't exit with error code if warnings are found
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
        \\    quality_check --format github-actions
        \\
        \\    # Allow warnings (only fail on errors)
        \\    quality_check --no-fail-on-warnings
        \\
    , .{}) catch {};
}
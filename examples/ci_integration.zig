//! CI/CD Integration Example
//!
//! This example demonstrates how to integrate zig-tooling into continuous
//! integration and deployment pipelines like GitHub Actions, GitLab CI, etc.

const std = @import("std");
const zig_tooling = @import("zig_tooling");

/// Exit codes for CI systems
const ExitCode = enum(u8) {
    success = 0,
    warnings = 1,
    errors = 2,
    fatal = 3,

    pub fn toInt(self: ExitCode) u8 {
        return @intFromEnum(self);
    }
};

/// CI runner configuration
const CiConfig = struct {
    /// Output format for the CI system
    output_format: OutputFormat = .auto,
    /// Fail on warnings (not just errors)
    fail_on_warnings: bool = false,
    /// Maximum number of issues to report
    max_issues: u32 = 100,
    /// Paths to analyze
    paths: []const []const u8 = &.{"."},
    /// File patterns to include
    include_patterns: []const []const u8 = &.{"**/*.zig"},
    /// File patterns to exclude
    exclude_patterns: []const []const u8 = &.{
        "**/zig-cache/**",
        "**/zig-out/**",
        "**/.zig-cache/**",
    },
    /// Generate summary report
    generate_summary: bool = true,
    /// Output file for results (null = stdout)
    output_file: ?[]const u8 = null,
    /// Enable performance metrics
    track_performance: bool = true,
};

const OutputFormat = enum {
    auto,
    text,
    json,
    github_actions,
    gitlab,
    junit,

    /// Detect format based on environment
    pub fn detect() OutputFormat {
        // GitHub Actions
        if (std.process.getEnvVarOwned(std.heap.page_allocator, "GITHUB_ACTIONS")) |_| {
            return .github_actions;
        } else |_| {}

        // GitLab CI
        if (std.process.getEnvVarOwned(std.heap.page_allocator, "GITLAB_CI")) |_| {
            return .gitlab;
        } else |_| {}

        // Default to text
        return .text;
    }
};

/// Main CI runner
pub fn runCiAnalysis(allocator: std.mem.Allocator, config: CiConfig) !ExitCode {
    const start_time = std.time.milliTimestamp();

    // Detect output format if auto
    const format = if (config.output_format == .auto)
        OutputFormat.detect()
    else
        config.output_format;

    // Configure analysis
    const analysis_config = zig_tooling.Config{
        .memory = .{
            .check_defer = true,
            .check_arena_usage = true,
            .check_allocator_usage = true,
            .allowed_allocators = &.{
                "std.heap.GeneralPurposeAllocator",
                "std.testing.allocator",
                "std.heap.ArenaAllocator",
                "std.heap.page_allocator", // Common in tests
            },
        },
        .testing = .{
            .enforce_categories = true,
            .enforce_naming = true,
            .allowed_categories = &.{ "unit", "integration", "e2e", "smoke", "perf" },
        },
        .pattern_config = .{
            .include_patterns = config.include_patterns,
            .exclude_patterns = config.exclude_patterns,
        },
        .options = .{
            .max_issues = config.max_issues,
            .verbose = true,
            .continue_on_error = true,
            .parallel = true, // Enable parallel analysis for CI
        },
    };

    // Run analysis on all paths
    var all_results = std.ArrayList(zig_tooling.patterns.ProjectAnalysisResult).init(allocator);
    defer all_results.deinit();

    for (config.paths) |path| {
        const result = try zig_tooling.patterns.checkProject(
            allocator,
            path,
            analysis_config,
            if (format == .text) ciProgressCallback else null,
        );
        try all_results.append(result);
    }

    // Merge results
    const merged_result = try mergeResults(allocator, all_results.items);
    defer zig_tooling.patterns.freeProjectResult(allocator, merged_result);

    // Format output based on CI system
    const output = switch (format) {
        .text => try zig_tooling.formatters.formatAsText(allocator, merged_result, .{
            .color = false, // CI logs usually don't support color
            .verbose = true,
            .include_stats = config.track_performance,
        }),
        .json => try zig_tooling.formatters.formatAsJson(allocator, merged_result, .{
            .json_indent = 2,
            .include_stats = true,
        }),
        .github_actions => try zig_tooling.formatters.formatAsGitHubActions(allocator, merged_result, .{
            .verbose = false, // GitHub Actions has length limits
        }),
        .gitlab => try formatForGitLab(allocator, merged_result),
        .junit => try formatAsJUnit(allocator, merged_result),
        else => unreachable,
    };
    defer allocator.free(output);

    // Write output
    if (config.output_file) |file_path| {
        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();
        try file.writeAll(output);
    } else {
        const stdout = std.io.getStdOut().writer();
        try stdout.writeAll(output);
    }

    // Generate summary if requested
    if (config.generate_summary) {
        try generateSummary(allocator, merged_result, start_time);
    }

    // Determine exit code
    if (merged_result.hasErrors()) {
        return .errors;
    } else if (merged_result.hasWarnings() and config.fail_on_warnings) {
        return .warnings;
    } else {
        return .success;
    }
}

/// Merge multiple analysis results
fn mergeResults(
    allocator: std.mem.Allocator,
    results: []const zig_tooling.patterns.ProjectAnalysisResult,
) !zig_tooling.patterns.ProjectAnalysisResult {
    var all_issues = std.ArrayList(zig_tooling.Issue).init(allocator);
    defer all_issues.deinit();

    var total_files: u32 = 0;
    var total_time: u64 = 0;
    var all_failed = std.ArrayList([]const u8).init(allocator);
    defer all_failed.deinit();

    for (results) |result| {
        try all_issues.appendSlice(result.issues);
        total_files += result.files_analyzed;
        total_time += result.analysis_time_ms;
        try all_failed.appendSlice(result.failed_files);
    }

    return .{
        .issues = try all_issues.toOwnedSlice(),
        .files_analyzed = total_files,
        .issues_found = @intCast(all_issues.items.len),
        .analysis_time_ms = total_time,
        .failed_files = try all_failed.toOwnedSlice(),
        .skipped_files = &.{}, // Not tracking skipped files in merge
    };
}

/// Format results for GitLab CI
fn formatForGitLab(allocator: std.mem.Allocator, result: zig_tooling.patterns.ProjectAnalysisResult) ![]const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    // GitLab uses a specific format for code quality reports
    try buffer.appendSlice("[\n");

    for (result.issues, 0..) |issue, i| {
        if (i > 0) try buffer.appendSlice(",\n");

        try buffer.writer().print(
            \\  {{
            \\    "description": "{s}",
            \\    "severity": "{s}",
            \\    "location": {{
            \\      "path": "{s}",
            \\      "lines": {{
            \\        "begin": {}
            \\      }}
            \\    }},
            \\    "fingerprint": "{s}:{d}:{d}"
            \\  }}
        , .{
            escapeJson(issue.message),
            if (issue.severity == .err) "major" else "minor",
            issue.file_path,
            issue.line,
            issue.file_path,
            issue.line,
            issue.column,
        });
    }

    try buffer.appendSlice("\n]\n");
    return try buffer.toOwnedSlice();
}

/// Format results as JUnit XML
fn formatAsJUnit(allocator: std.mem.Allocator, result: zig_tooling.patterns.ProjectAnalysisResult) ![]const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    const errors = result.getErrorCount();
    const warnings = result.getWarningCount();

    try buffer.appendSlice("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    try buffer.writer().print(
        \\<testsuite name="zig-tooling" tests="{}" failures="{}" errors="{}" time="{}">
        \\
    , .{ result.files_analyzed, errors, warnings, result.analysis_time_ms / 1000.0 });

    // Group issues by file
    var file_issues = std.StringHashMap(std.ArrayList(zig_tooling.Issue)).init(allocator);
    defer {
        var iter = file_issues.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        file_issues.deinit();
    }

    for (result.issues) |issue| {
        const gop = try file_issues.getOrPut(issue.file_path);
        if (!gop.found_existing) {
            gop.value_ptr.* = std.ArrayList(zig_tooling.Issue).init(allocator);
        }
        try gop.value_ptr.append(issue);
    }

    // Output test cases
    var iter = file_issues.iterator();
    while (iter.next()) |entry| {
        const file_path = entry.key_ptr.*;
        const issues = entry.value_ptr.items;

        if (issues.len == 0) {
            try buffer.writer().print(
                \\  <testcase name="{s}" classname="zig-tooling" time="0.001"/>
                \\
            , .{file_path});
        } else {
            for (issues) |issue| {
                try buffer.writer().print(
                    \\  <testcase name="{s}:{}" classname="zig-tooling" time="0.001">
                    \\
                , .{ file_path, issue.line });

                const tag = if (issue.severity == .err) "failure" else "error";
                try buffer.writer().print(
                    \\    <{s} message="{s}" type="{s}">
                    \\      {s}:{}: {s}
                    \\    </{s}>
                    \\  </testcase>
                    \\
                , .{
                    tag,
                    escapeXml(issue.message),
                    @tagName(issue.issue_type),
                    file_path,
                    issue.line,
                    escapeXml(issue.message),
                    tag,
                });
            }
        }
    }

    try buffer.appendSlice("</testsuite>\n");
    return try buffer.toOwnedSlice();
}

/// Generate a summary report
fn generateSummary(
    allocator: std.mem.Allocator,
    result: zig_tooling.patterns.ProjectAnalysisResult,
    start_time: i64,
) !void {
    const elapsed = std.time.milliTimestamp() - start_time;
    const stderr = std.io.getStdErr().writer();

    try stderr.print("\n=== zig-tooling Analysis Summary ===\n", .{});
    try stderr.print("Files analyzed: {}\n", .{result.files_analyzed});
    try stderr.print("Total issues: {}\n", .{result.issues_found});
    try stderr.print("  - Errors: {}\n", .{result.getErrorCount()});
    try stderr.print("  - Warnings: {}\n", .{result.getWarningCount()});
    try stderr.print("  - Info: {}\n", .{result.issues_found - result.getErrorCount() - result.getWarningCount()});
    try stderr.print("Failed files: {}\n", .{result.failed_files.len});
    try stderr.print("Total time: {}ms\n", .{elapsed});
    try stderr.print("Analysis time: {}ms\n", .{result.analysis_time_ms});
    try stderr.print("Overhead: {}ms\n", .{elapsed - @as(i64, @intCast(result.analysis_time_ms))});

    // Issue breakdown by type
    var issue_counts = std.AutoHashMap(zig_tooling.IssueType, u32).init(allocator);
    defer issue_counts.deinit();

    for (result.issues) |issue| {
        const gop = try issue_counts.getOrPut(issue.issue_type);
        if (!gop.found_existing) gop.value_ptr.* = 0;
        gop.value_ptr.* += 1;
    }

    if (issue_counts.count() > 0) {
        try stderr.print("\nIssue types:\n", .{});
        var iter = issue_counts.iterator();
        while (iter.next()) |entry| {
            try stderr.print("  - {s}: {}\n", .{ @tagName(entry.key_ptr.*), entry.value_ptr.* });
        }
    }
}

/// Progress callback for CI
fn ciProgressCallback(files_processed: u32, total_files: u32, current_file: []const u8) void {
    const stderr = std.io.getStdErr().writer();
    stderr.print("[{}/{}] Analyzing {s}\n", .{
        files_processed + 1,
        total_files,
        current_file,
    }) catch {};
}

/// Escape JSON string
fn escapeJson(str: []const u8) []const u8 {
    // Simple escaping - in production would be more comprehensive
    return str;
}

/// Escape XML string
fn escapeXml(str: []const u8) []const u8 {
    // Simple escaping - in production would be more comprehensive
    return str;
}

/// Example CI runner script
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var config = CiConfig{};

    // Simple argument parsing
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--format")) {
            i += 1;
            if (i < args.len) {
                if (std.mem.eql(u8, args[i], "text")) config.output_format = .text;
                if (std.mem.eql(u8, args[i], "json")) config.output_format = .json;
                if (std.mem.eql(u8, args[i], "github")) config.output_format = .github_actions;
                if (std.mem.eql(u8, args[i], "gitlab")) config.output_format = .gitlab;
                if (std.mem.eql(u8, args[i], "junit")) config.output_format = .junit;
            }
        } else if (std.mem.eql(u8, args[i], "--fail-on-warnings")) {
            config.fail_on_warnings = true;
        } else if (std.mem.eql(u8, args[i], "--output")) {
            i += 1;
            if (i < args.len) {
                config.output_file = args[i];
            }
        } else if (std.mem.eql(u8, args[i], "--no-summary")) {
            config.generate_summary = false;
        } else if (std.mem.eql(u8, args[i], "--help")) {
            try printHelp();
            return;
        }
    }

    // Run analysis
    const exit_code = try runCiAnalysis(allocator, config);

    // Demonstrate different CI configurations
    if (args.len == 1) {
        try demonstrateCiIntegrations(allocator);
    }

    std.process.exit(exit_code.toInt());
}

fn printHelp() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(
        \\zig-tooling CI Runner
        \\
        \\Usage: ci_integration [options]
        \\
        \\Options:
        \\  --format <fmt>      Output format: text, json, github, gitlab, junit (default: auto)
        \\  --fail-on-warnings  Exit with non-zero code on warnings
        \\  --output <file>     Write results to file instead of stdout
        \\  --no-summary        Don't generate summary report
        \\  --help              Show this help message
        \\
        \\Environment Detection:
        \\  - GITHUB_ACTIONS: Automatically uses GitHub Actions format
        \\  - GITLAB_CI: Automatically uses GitLab format
        \\
    );
}

/// Demonstrate different CI integrations
fn demonstrateCiIntegrations(allocator: std.mem.Allocator) !void {
    std.debug.print("=== CI/CD Integration Examples ===\n\n", .{});

    // Example: GitHub Actions workflow
    std.debug.print("1. GitHub Actions (.github/workflows/quality.yml):\n", .{});
    std.debug.print(
        \\---
        \\name: Code Quality
        \\on: [push, pull_request]
        \\
        \\jobs:
        \\  quality-check:
        \\    runs-on: ubuntu-latest
        \\    steps:
        \\      - uses: actions/checkout@v3
        \\      - uses: goto-bus-stop/setup-zig@v2
        \\      
        \\      - name: Run zig-tooling analysis
        \\        run: |
        \\          zig build -Doptimize=ReleaseFast
        \\          ./zig-out/bin/ci_integration --format github --fail-on-warnings
        \\
    , .{});

    // Example: GitLab CI
    std.debug.print("\n2. GitLab CI (.gitlab-ci.yml):\n", .{});
    std.debug.print(
        \\---
        \\code_quality:
        \\  stage: test
        \\  script:
        \\    - zig build -Doptimize=ReleaseFast
        \\    - ./zig-out/bin/ci_integration --format gitlab --output gl-code-quality-report.json
        \\  artifacts:
        \\    reports:
        \\      codequality: gl-code-quality-report.json
        \\
    , .{});

    // Example: Jenkins
    std.debug.print("\n3. Jenkins (Jenkinsfile):\n", .{});
    std.debug.print(
        \\---
        \\pipeline {
        \\    agent any
        \\    stages {
        \\        stage('Quality Check') {
        \\            steps {
        \\                sh 'zig build -Doptimize=ReleaseFast'
        \\                sh './zig-out/bin/ci_integration --format junit --output results.xml'
        \\                junit 'results.xml'
        \\            }
        \\        }
        \\    }
        \\}
        \\
    , .{});

    // Run a demo analysis
    std.debug.print("\n4. Running demo analysis...\n", .{});
    const demo_config = CiConfig{
        .output_format = .text,
        .paths = &.{"examples/sample_project"},
        .generate_summary = true,
        .track_performance = true,
    };

    const exit_code = try runCiAnalysis(allocator, demo_config);
    std.debug.print("\nExit code: {} ({})\n", .{ exit_code.toInt(), @tagName(exit_code) });
}

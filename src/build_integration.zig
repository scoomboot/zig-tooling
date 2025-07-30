//! Build system integration helpers for zig-tooling library
//!
//! This module provides helper functions to integrate zig-tooling analysis
//! directly into Zig build systems, enabling automated code quality checks
//! during builds, testing, and CI/CD pipelines.
//!
//! ## Features
//! - Memory safety analysis build steps
//! - Test compliance validation build steps  
//! - Pre-commit hook generation
//! - Customizable analysis configuration
//!
//! ## Example Usage
//! ```zig
//! // In your build.zig:
//! const zig_tooling = @import("zig_tooling");
//! const build_integration = zig_tooling.build_integration;
//!
//! pub fn build(b: *std.Build) void {
//!     // Add memory check step
//!     const memory_check = build_integration.addMemoryCheckStep(b, .{
//!         .source_paths = &.{ "src/**/*.zig" },
//!         .fail_on_warnings = true,
//!     });
//!     
//!     // Add test compliance step
//!     const test_check = build_integration.addTestComplianceStep(b, .{
//!         .source_paths = &.{ "tests/**/*.zig" },
//!         .enforce_categories = true,
//!     });
//!     
//!     // Create combined quality check step
//!     const quality_step = b.step("quality", "Run all code quality checks");
//!     quality_step.dependOn(&memory_check.step);
//!     quality_step.dependOn(&test_check.step);
//! }
//! ```

const std = @import("std");
const zig_tooling = @import("zig_tooling.zig");
const formatters = @import("formatters.zig");

/// Options for memory safety analysis build step
pub const MemoryCheckOptions = struct {
    /// Source file patterns to analyze (supports glob patterns)
    source_paths: []const []const u8 = &.{"src/**/*.zig"},
    
    /// Exclude patterns (relative to project root)
    exclude_patterns: []const []const u8 = &.{ 
        "**/zig-cache/**", 
        "**/zig-out/**", 
        "**/.zig-cache/**" 
    },
    
    /// Memory analysis configuration
    memory_config: zig_tooling.MemoryConfig = .{},
    
    /// Fail build on warnings (not just errors)
    fail_on_warnings: bool = false,
    
    /// Maximum number of issues to report (null = unlimited)
    max_issues: ?u32 = null,
    
    /// Continue analysis after first error
    continue_on_error: bool = true,
    
    /// Output format for results
    output_format: OutputFormat = .text,
    
    /// Step name for build system
    step_name: []const u8 = "memory-check",
    
    /// Step description for build system
    step_description: []const u8 = "Run memory safety analysis",
};

/// Options for test compliance analysis build step
pub const TestComplianceOptions = struct {
    /// Test file patterns to analyze (supports glob patterns)
    source_paths: []const []const u8 = &.{"tests/**/*.zig"},
    
    /// Exclude patterns (relative to project root)
    exclude_patterns: []const []const u8 = &.{ 
        "**/zig-cache/**", 
        "**/zig-out/**", 
        "**/.zig-cache/**" 
    },
    
    /// Testing analysis configuration
    testing_config: zig_tooling.TestingConfig = .{},
    
    /// Fail build on warnings (not just errors)
    fail_on_warnings: bool = false,
    
    /// Maximum number of issues to report (null = unlimited)
    max_issues: ?u32 = null,
    
    /// Continue analysis after first error
    continue_on_error: bool = true,
    
    /// Output format for results
    output_format: OutputFormat = .text,
    
    /// Step name for build system
    step_name: []const u8 = "test-compliance",
    
    /// Step description for build system
    step_description: []const u8 = "Run test compliance analysis",
};

/// Options for pre-commit hook generation
pub const PreCommitHookOptions = struct {
    /// Include memory safety checks
    include_memory_checks: bool = true,
    
    /// Include test compliance checks
    include_test_compliance: bool = true,
    
    /// Paths to analyze (relative to repository root)
    check_paths: []const []const u8 = &.{ "src/", "tests/" },
    
    /// File patterns to include
    include_patterns: []const []const u8 = &.{"**/*.zig"},
    
    /// File patterns to exclude
    exclude_patterns: []const []const u8 = &.{ 
        "**/zig-cache/**", 
        "**/zig-out/**", 
        "**/.zig-cache/**" 
    },
    
    /// Fail commit on warnings
    fail_on_warnings: bool = true,
    
    /// Hook script language
    hook_type: HookType = .bash,
};

/// Supported output formats for analysis results
pub const OutputFormat = enum {
    text,
    json,
    github_actions,
};

/// Supported pre-commit hook types
pub const HookType = enum {
    bash,
    fish,
    powershell,
};

/// Internal build step for memory analysis
const MemoryCheckStep = struct {
    step: std.Build.Step,
    options: MemoryCheckOptions,
    allocator: std.mem.Allocator,
    builder: *std.Build,

    pub fn create(builder: *std.Build, options: MemoryCheckOptions) *MemoryCheckStep {
        const self = builder.allocator.create(MemoryCheckStep) catch @panic("OOM");
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = options.step_name,
                .owner = builder,
                .makeFn = make,
            }),
            .options = options,
            .allocator = builder.allocator,
            .builder = builder,
        };
        return self;
    }

    fn make(step: *std.Build.Step, _: std.Progress.Node) !void {
        const self: *MemoryCheckStep = @fieldParentPtr("step", step);
        
        var issues_found: u32 = 0;
        var files_analyzed: u32 = 0;
        
        // Build configuration
        const config = zig_tooling.Config{
            .memory = self.options.memory_config,
            .patterns = .{
                .include_patterns = &.{"**/*.zig"}, // Will be filtered by source_paths
                .exclude_patterns = self.options.exclude_patterns,
            },
            .options = .{
                .max_issues = self.options.max_issues,
                .continue_on_error = self.options.continue_on_error,
                .fail_on_warnings = self.options.fail_on_warnings,
            },
        };
        
        // Analyze each source path pattern
        for (self.options.source_paths) |path_pattern| {
            // For now, we'll implement a simple pattern matching
            // In a full implementation, we'd use proper glob pattern matching
            if (analyzePattern(self.allocator, path_pattern, config)) |result| {
                defer self.allocator.free(result.issues);
                defer for (result.issues) |issue| {
                    self.allocator.free(issue.file_path);
                    self.allocator.free(issue.message);
                    if (issue.suggestion) |s| self.allocator.free(s);
                };
                
                issues_found += result.issues_found;
                files_analyzed += result.files_analyzed;
                
                // Print results based on output format
                printResults(result, self.options.output_format);
                
                // Check if we should fail the build
                const has_errors = blk: {
                    for (result.issues) |issue| {
                        if (issue.severity == .@"error" or 
                           (self.options.fail_on_warnings and issue.severity == .warning)) {
                            break :blk true;
                        }
                    }
                    break :blk false;
                };
                
                if (has_errors) {
                    return step.fail("Memory safety analysis failed with {d} issues", .{result.issues_found});
                }
            } else |err| {
                if (!self.options.continue_on_error) {
                    return step.fail("Failed to analyze {s}: {}", .{ path_pattern, err });
                }
                std.log.warn("Failed to analyze {s}: {}", .{ path_pattern, err });
            }
        }
        
        std.log.info("Memory analysis completed: {d} files analyzed, {d} issues found", .{ files_analyzed, issues_found });
    }
};

/// Internal build step for test compliance analysis
const TestComplianceStep = struct {
    step: std.Build.Step,
    options: TestComplianceOptions,
    allocator: std.mem.Allocator,
    builder: *std.Build,

    pub fn create(builder: *std.Build, options: TestComplianceOptions) *TestComplianceStep {
        const self = builder.allocator.create(TestComplianceStep) catch @panic("OOM");
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = options.step_name,
                .owner = builder,
                .makeFn = make,
            }),
            .options = options,
            .allocator = builder.allocator,
            .builder = builder,
        };
        return self;
    }

    fn make(step: *std.Build.Step, _: std.Progress.Node) !void {
        const self: *TestComplianceStep = @fieldParentPtr("step", step);
        
        var issues_found: u32 = 0;
        var files_analyzed: u32 = 0;
        
        // Build configuration
        const config = zig_tooling.Config{
            .testing = self.options.testing_config,
            .patterns = .{
                .include_patterns = &.{"**/*.zig"}, // Will be filtered by source_paths
                .exclude_patterns = self.options.exclude_patterns,
            },
            .options = .{
                .max_issues = self.options.max_issues,
                .continue_on_error = self.options.continue_on_error,
                .fail_on_warnings = self.options.fail_on_warnings,
            },
        };
        
        // Analyze each source path pattern
        for (self.options.source_paths) |path_pattern| {
            if (analyzePatternForTests(self.allocator, path_pattern, config)) |result| {
                defer self.allocator.free(result.issues);
                defer for (result.issues) |issue| {
                    self.allocator.free(issue.file_path);
                    self.allocator.free(issue.message);
                    if (issue.suggestion) |s| self.allocator.free(s);
                };
                
                issues_found += result.issues_found;
                files_analyzed += result.files_analyzed;
                
                // Print results based on output format
                printResults(result, self.options.output_format);
                
                // Check if we should fail the build
                const has_errors = blk: {
                    for (result.issues) |issue| {
                        if (issue.severity == .@"error" or 
                           (self.options.fail_on_warnings and issue.severity == .warning)) {
                            break :blk true;
                        }
                    }
                    break :blk false;
                };
                
                if (has_errors) {
                    return step.fail("Test compliance analysis failed with {d} issues", .{result.issues_found});
                }
            } else |err| {
                if (!self.options.continue_on_error) {
                    return step.fail("Failed to analyze {s}: {}", .{ path_pattern, err });
                }
                std.log.warn("Failed to analyze {s}: {}", .{ path_pattern, err });
            }
        }
        
        std.log.info("Test compliance analysis completed: {d} files analyzed, {d} issues found", .{ files_analyzed, issues_found });
    }
};

/// Add a memory safety analysis step to the build system
///
/// This function creates a build step that analyzes source files for memory safety
/// issues using the zig-tooling memory analyzer. The step can be configured to
/// fail the build on warnings or errors, and supports various output formats.
///
/// ## Parameters
/// - `builder`: The build system instance
/// - `options`: Configuration options for the memory check step
///
/// ## Returns
/// A pointer to the created build step, which can be used as a dependency
/// for other build steps or run independently.
///
/// ## Example
/// ```zig
/// const memory_check = build_integration.addMemoryCheckStep(b, .{
///     .source_paths = &.{ "src/**/*.zig", "lib/**/*.zig" },
///     .fail_on_warnings = true,
///     .memory_config = .{
///         .check_defer = true,
///         .check_arena_usage = true,
///         .allowed_allocators = &.{ "std.heap.GeneralPurposeAllocator" },
///     },
/// });
/// 
/// // Add to a quality check step
/// const quality_step = b.step("quality", "Run all code quality checks");
/// quality_step.dependOn(&memory_check.step);
/// ```
pub fn addMemoryCheckStep(builder: *std.Build, options: MemoryCheckOptions) *MemoryCheckStep {
    return MemoryCheckStep.create(builder, options);
}

/// Add a test compliance analysis step to the build system
///
/// This function creates a build step that analyzes test files for compliance
/// with naming conventions, organization patterns, and other testing best practices.
///
/// ## Parameters
/// - `builder`: The build system instance
/// - `options`: Configuration options for the test compliance step
///
/// ## Returns
/// A pointer to the created build step, which can be used as a dependency
/// for other build steps or run independently.
///
/// ## Example
/// ```zig
/// const test_check = build_integration.addTestComplianceStep(b, .{
///     .source_paths = &.{ "tests/**/*.zig" },
///     .fail_on_warnings = false,
///     .testing_config = .{
///         .enforce_categories = true,
///         .allowed_categories = &.{ "unit", "integration", "e2e" },
///     },
/// });
/// 
/// // Run before main tests
/// const test_step = b.step("test", "Run unit tests");
/// test_step.dependOn(&test_check.step);
/// ```
pub fn addTestComplianceStep(builder: *std.Build, options: TestComplianceOptions) *TestComplianceStep {
    return TestComplianceStep.create(builder, options);
}

/// Generate a pre-commit hook script for automated code quality checks
///
/// This function creates a pre-commit hook script that runs zig-tooling analysis
/// on modified files before allowing commits. The hook can be customized to
/// include different types of analysis and output formats.
///
/// ## Parameters
/// - `allocator`: Memory allocator for the generated script
/// - `options`: Configuration options for the pre-commit hook
///
/// ## Returns
/// A dynamically allocated string containing the complete hook script.
/// Caller must free the returned memory.
///
/// ## Example
/// ```zig
/// const hook_script = try build_integration.createPreCommitHook(allocator, .{
///     .include_memory_checks = true,
///     .include_test_compliance = true,
///     .fail_on_warnings = true,
///     .hook_type = .bash,
/// });
/// defer allocator.free(hook_script);
/// 
/// // Write to .git/hooks/pre-commit
/// try std.fs.cwd().writeFile(".git/hooks/pre-commit", hook_script);
/// ```
pub fn createPreCommitHook(allocator: std.mem.Allocator, options: PreCommitHookOptions) ![]const u8 {
    return switch (options.hook_type) {
        .bash => createBashPreCommitHook(allocator, options),
        .fish => createFishPreCommitHook(allocator, options),
        .powershell => createPowerShellPreCommitHook(allocator, options),
    };
}

// Helper functions for pattern analysis
fn analyzePattern(allocator: std.mem.Allocator, pattern: []const u8, config: zig_tooling.Config) !zig_tooling.AnalysisResult {
    // Find all files matching the pattern
    const matching_files = try findFilesMatchingPattern(allocator, pattern, config.patterns);
    defer {
        for (matching_files) |file_path| {
            allocator.free(file_path);
        }
        allocator.free(matching_files);
    }
    
    if (matching_files.len == 0) {
        return zig_tooling.AnalysisResult{
            .issues = try allocator.alloc(zig_tooling.Issue, 0),
            .files_analyzed = 0,
            .issues_found = 0,
            .analysis_time_ms = 0,
        };
    }
    
    // Analyze each file and aggregate results
    var all_issues = std.ArrayList(zig_tooling.Issue).init(allocator);
    defer all_issues.deinit();
    
    var total_time: i64 = 0;
    
    for (matching_files) |file_path| {
        // Read file content
        const file_content = std.fs.cwd().readFileAlloc(allocator, file_path, 10 * 1024 * 1024) catch |err| {
            std.log.warn("Failed to read {s}: {}", .{ file_path, err });
            continue;
        };
        defer allocator.free(file_content);
        
        const result = zig_tooling.analyzeMemory(allocator, file_content, file_path, config) catch |err| {
            std.log.warn("Failed to analyze {s}: {}", .{ file_path, err });
            continue;
        };
        defer allocator.free(result.issues);
        defer for (result.issues) |issue| {
            allocator.free(issue.file_path);
            allocator.free(issue.message);
            if (issue.suggestion) |s| allocator.free(s);
        };
        
        // Copy issues to our aggregated list
        for (result.issues) |issue| {
            try all_issues.append(zig_tooling.Issue{
                .file_path = try allocator.dupe(u8, issue.file_path),
                .line = issue.line,
                .column = issue.column,
                .issue_type = issue.issue_type,
                .severity = issue.severity,
                .message = try allocator.dupe(u8, issue.message),
                .suggestion = if (issue.suggestion) |s| try allocator.dupe(u8, s) else null,
                .code_snippet = issue.code_snippet,
            });
        }
        
        total_time += result.analysis_time_ms;
    }
    
    return zig_tooling.AnalysisResult{
        .issues = try all_issues.toOwnedSlice(),
        .files_analyzed = @intCast(matching_files.len),
        .issues_found = @intCast(all_issues.items.len),
        .analysis_time_ms = @intCast(total_time),
    };
}

fn analyzePatternForTests(allocator: std.mem.Allocator, pattern: []const u8, config: zig_tooling.Config) !zig_tooling.AnalysisResult {
    // Find all files matching the pattern
    const matching_files = try findFilesMatchingPattern(allocator, pattern, config.patterns);
    defer {
        for (matching_files) |file_path| {
            allocator.free(file_path);
        }
        allocator.free(matching_files);
    }
    
    if (matching_files.len == 0) {
        return zig_tooling.AnalysisResult{
            .issues = try allocator.alloc(zig_tooling.Issue, 0),
            .files_analyzed = 0,
            .issues_found = 0,
            .analysis_time_ms = 0,
        };
    }
    
    // Analyze each file and aggregate results
    var all_issues = std.ArrayList(zig_tooling.Issue).init(allocator);
    defer all_issues.deinit();
    
    var total_time: i64 = 0;
    
    for (matching_files) |file_path| {
        // Read file content
        const file_content = std.fs.cwd().readFileAlloc(allocator, file_path, 10 * 1024 * 1024) catch |err| {
            std.log.warn("Failed to read {s}: {}", .{ file_path, err });
            continue;
        };
        defer allocator.free(file_content);
        
        const result = zig_tooling.analyzeTests(allocator, file_content, file_path, config) catch |err| {
            std.log.warn("Failed to analyze {s}: {}", .{ file_path, err });
            continue;
        };
        defer allocator.free(result.issues);
        defer for (result.issues) |issue| {
            allocator.free(issue.file_path);
            allocator.free(issue.message);
            if (issue.suggestion) |s| allocator.free(s);
        };
        
        // Copy issues to our aggregated list
        for (result.issues) |issue| {
            try all_issues.append(zig_tooling.Issue{
                .file_path = try allocator.dupe(u8, issue.file_path),
                .line = issue.line,
                .column = issue.column,
                .issue_type = issue.issue_type,
                .severity = issue.severity,
                .message = try allocator.dupe(u8, issue.message),
                .suggestion = if (issue.suggestion) |s| try allocator.dupe(u8, s) else null,
                .code_snippet = issue.code_snippet,
            });
        }
        
        total_time += result.analysis_time_ms;
    }
    
    return zig_tooling.AnalysisResult{
        .issues = try all_issues.toOwnedSlice(),
        .files_analyzed = @intCast(matching_files.len),
        .issues_found = @intCast(all_issues.items.len),
        .analysis_time_ms = @intCast(total_time),
    };
}

/// Find files matching a glob pattern with include/exclude filtering
fn findFilesMatchingPattern(allocator: std.mem.Allocator, pattern: []const u8, patterns_config: zig_tooling.PatternConfig) ![][]const u8 {
    var result_files = std.ArrayList([]const u8).init(allocator);
    defer result_files.deinit();
    
    // For simplicity, we'll implement basic pattern matching
    // In a production implementation, we'd use proper glob pattern matching
    
    // If pattern starts with "src/" or "tests/", walk that directory
    const base_dir = if (std.mem.startsWith(u8, pattern, "src/"))
        "src"
    else if (std.mem.startsWith(u8, pattern, "tests/"))
        "tests"
    else
        "."; // Current directory
        
    try walkDirectoryForZigFiles(allocator, &result_files, base_dir, patterns_config);
    
    return result_files.toOwnedSlice();
}

/// Recursively walk directory to find .zig files, respecting include/exclude patterns
fn walkDirectoryForZigFiles(
    allocator: std.mem.Allocator, 
    result_files: *std.ArrayList([]const u8), 
    dir_path: []const u8,
    patterns_config: zig_tooling.PatternConfig
) !void {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return, // Directory doesn't exist, skip
        else => return err,
    };
    defer dir.close();
    
    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        const full_path = try std.fs.path.join(allocator, &.{ dir_path, entry.name });
        defer allocator.free(full_path);
        
        switch (entry.kind) {
            .file => {
                // Check if it's a .zig file
                if (std.mem.endsWith(u8, entry.name, ".zig")) {
                    // Check include patterns
                    var included = false;
                    for (patterns_config.include_patterns) |include_pattern| {
                        if (matchesPattern(full_path, include_pattern)) {
                            included = true;
                            break;
                        }
                    }
                    
                    // Check exclude patterns
                    if (included) {
                        for (patterns_config.exclude_patterns) |exclude_pattern| {
                            if (matchesPattern(full_path, exclude_pattern)) {
                                included = false;
                                break;
                            }
                        }
                    }
                    
                    if (included) {
                        try result_files.append(try allocator.dupe(u8, full_path));
                    }
                }
            },
            .directory => {
                // Skip common cache/build directories
                if (std.mem.eql(u8, entry.name, "zig-cache") or 
                    std.mem.eql(u8, entry.name, "zig-out") or
                    std.mem.eql(u8, entry.name, ".zig-cache")) {
                    continue;
                }
                
                // Recursively walk subdirectory
                try walkDirectoryForZigFiles(allocator, result_files, full_path, patterns_config);
            },
            else => {}, // Skip other types
        }
    }
}

/// Simple pattern matching (basic glob support)
fn matchesPattern(path: []const u8, pattern: []const u8) bool {
    // Handle some basic glob patterns
    if (std.mem.eql(u8, pattern, "**/*.zig")) {
        return std.mem.endsWith(u8, path, ".zig");
    }
    
    if (std.mem.startsWith(u8, pattern, "**/")) {
        const suffix = pattern[3..];
        return std.mem.endsWith(u8, path, suffix) or std.mem.indexOf(u8, path, suffix) != null;
    }
    
    if (std.mem.endsWith(u8, pattern, "/**")) {
        const prefix = pattern[0..pattern.len-3];
        return std.mem.startsWith(u8, path, prefix);
    }
    
    // Exact match
    return std.mem.eql(u8, path, pattern) or std.mem.indexOf(u8, path, pattern) != null;
}

fn printResults(result: zig_tooling.AnalysisResult, format: OutputFormat) void {
    switch (format) {
        .text => printTextResults(result),
        .json => printJsonResults(result),
        .github_actions => printGitHubActionsResults(result),
    }
}

fn printTextResults(result: zig_tooling.AnalysisResult) void {
    if (result.issues_found == 0) {
        std.log.info("✅ No issues found in {d} files", .{result.files_analyzed});
        return;
    }
    
    std.log.info("Found {d} issues in {d} files:", .{ result.issues_found, result.files_analyzed });
    for (result.issues) |issue| {
        const severity_icon = switch (issue.severity) {
            .@"error" => "❌",
            .warning => "⚠️",
            .info => "ℹ️",
        };
        std.log.info("{s} {s}:{d}:{d}: {s}", .{ 
            severity_icon, 
            issue.file_path, 
            issue.line, 
            issue.column, 
            issue.message 
        });
    }
}

fn printJsonResults(result: zig_tooling.AnalysisResult) void {
    // Use a temporary allocator for formatting
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const json_output = formatters.formatAsJson(allocator, result, .{}) catch |err| {
        std.log.err("Failed to format JSON output: {}", .{err});
        return;
    };
    defer allocator.free(json_output);
    
    // Write to stdout
    const stdout = std.io.getStdOut().writer();
    stdout.writeAll(json_output) catch |err| {
        std.log.err("Failed to write JSON output: {}", .{err});
    };
}

fn printGitHubActionsResults(result: zig_tooling.AnalysisResult) void {
    // Use a temporary allocator for formatting
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const gh_output = formatters.formatAsGitHubActions(allocator, result, .{}) catch |err| {
        std.log.err("Failed to format GitHub Actions output: {}", .{err});
        return;
    };
    defer allocator.free(gh_output);
    
    // Write to stdout
    const stdout = std.io.getStdOut().writer();
    stdout.writeAll(gh_output) catch |err| {
        std.log.err("Failed to write GitHub Actions output: {}", .{err});
    };
}

fn createBashPreCommitHook(allocator: std.mem.Allocator, options: PreCommitHookOptions) ![]const u8 {
    var script = std.ArrayList(u8).init(allocator);
    defer script.deinit();

    try script.appendSlice(
        \\#!/bin/bash
        \\# Auto-generated pre-commit hook for zig-tooling
        \\# This hook runs code quality checks on staged files
        \\
        \\set -e
        \\
        \\echo "🔍 Running zig-tooling pre-commit checks..."
        \\
        \\# Get list of staged .zig files
        \\STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.zig$' || true)
        \\
        \\if [ -z "$STAGED_FILES" ]; then
        \\    echo "✅ No Zig files staged, skipping analysis"
        \\    exit 0
        \\fi
        \\
        \\echo "📂 Analyzing staged files:"
        \\echo "$STAGED_FILES"
        \\echo ""
        \\
        \\# Create temporary analysis script
        \\TEMP_SCRIPT=$(mktemp)
        \\trap "rm -f $TEMP_SCRIPT" EXIT
        \\
        \\cat > "$TEMP_SCRIPT" << 'EOF'
        \\const std = @import("std");
        \\const zig_tooling = @import("zig_tooling");
        \\
        \\pub fn main() !void {
        \\    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        \\    defer _ = gpa.deinit();
        \\    const allocator = gpa.allocator();
        \\    
        \\    const args = try std.process.argsAlloc(allocator);
        \\    defer std.process.argsFree(allocator, args);
        \\    
        \\    if (args.len < 2) {
        \\        std.debug.print("Usage: {s} <file>\n", .{args[0]});
        \\        std.process.exit(1);
        \\    }
        \\    
        \\    const config = zig_tooling.Config{
    );

    if (options.include_memory_checks) {
        try script.appendSlice(
            \\        .memory = .{
            \\            .check_defer = true,
            \\            .check_arena_usage = true,
            \\            .check_allocator_usage = true,
            \\        },
        );
    }

    if (options.include_test_compliance) {
        try script.appendSlice(
            \\        .testing = .{
            \\            .enforce_categories = true,
            \\            .enforce_naming = true,
            \\        },
        );
    }

    try script.appendSlice(
        \\    };
        \\    
        \\    var total_issues: u32 = 0;
        \\    for (args[1..]) |file_path| {
        \\        const result = zig_tooling.analyzeFile(allocator, file_path, config) catch |err| {
        \\            std.debug.print("❌ Failed to analyze {s}: {}\n", .{ file_path, err });
        \\            std.process.exit(1);
        \\        };
        \\        defer allocator.free(result.issues);
        \\        defer for (result.issues) |issue| {
        \\            allocator.free(issue.file_path);
        \\            allocator.free(issue.message);
        \\            if (issue.suggestion) |s| allocator.free(s);
        \\        };
        \\        
        \\        total_issues += result.issues_found;
        \\        
        \\        for (result.issues) |issue| {
    );

    if (options.fail_on_warnings) {
        try script.appendSlice(
            \\            if (issue.severity == .@"error" or issue.severity == .warning) {
        );
    } else {
        try script.appendSlice(
            \\            if (issue.severity == .@"error") {
        );
    }

    try script.appendSlice(
        \\                const severity_icon = switch (issue.severity) {
        \\                    .@"error" => "❌",
        \\                    .warning => "⚠️",
        \\                    .info => "ℹ️",
        \\                };
        \\                std.debug.print("{s} {s}:{d}:{d}: {s}\n", .{ 
        \\                    severity_icon, 
        \\                    issue.file_path, 
        \\                    issue.line, 
        \\                    issue.column, 
        \\                    issue.message 
        \\                });
        \\            }
        \\        }
        \\    }
        \\    
        \\    if (total_issues > 0) {
        \\        std.debug.print("\n❌ Found {d} issues. Please fix them before committing.\n", .{total_issues});
        \\        std.process.exit(1);
        \\    } else {
        \\        std.debug.print("✅ All checks passed!\n");
        \\    }
        \\}
        \\EOF
        \\
        \\# Compile and run the analysis
        \\if ! zig run "$TEMP_SCRIPT" -- $STAGED_FILES; then
        \\    echo ""
        \\    echo "💡 Tip: Run 'zig build quality' to analyze all files"
        \\    exit 1
        \\fi
        \\
        \\echo "✅ All pre-commit checks passed!"
    );

    return script.toOwnedSlice();
}

fn createFishPreCommitHook(allocator: std.mem.Allocator, options: PreCommitHookOptions) ![]const u8 {
    // TODO: Implement Fish shell hook
    _ = options;
    return allocator.dupe(u8, "# Fish shell pre-commit hook not yet implemented");
}

fn createPowerShellPreCommitHook(allocator: std.mem.Allocator, options: PreCommitHookOptions) ![]const u8 {
    // TODO: Implement PowerShell hook
    _ = options;
    return allocator.dupe(u8, "# PowerShell pre-commit hook not yet implemented");
}

// Tests
test "unit: build_integration: MemoryCheckOptions initialization" {
    const testing = std.testing;
    
    // Test default initialization
    const options = MemoryCheckOptions{};
    try testing.expect(options.source_paths.len > 0); // Has default value
    try testing.expect(options.exclude_patterns.len > 0); // Has default values
    try testing.expect(options.fail_on_warnings == false); // Default is false
    
    // Test with custom options
    const custom_options = MemoryCheckOptions{
        .source_paths = &.{"src/*.zig", "lib/*.zig"},
        .fail_on_warnings = true,
    };
    try testing.expect(custom_options.source_paths.len == 2);
    try testing.expect(custom_options.fail_on_warnings == true);
}
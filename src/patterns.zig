//! Common usage patterns for zig-tooling library
//!
//! This module provides high-level convenience functions for the most common
//! analysis scenarios, with sensible defaults and enhanced error handling.
//!
//! ## Features
//! - Project-wide analysis with automatic file discovery
//! - Enhanced error reporting and user-friendly messages
//! - Optimized default configurations for common use cases
//! - Progress reporting for large projects
//! - Result aggregation and statistics
//!
//! ## Quick Start
//! ```zig
//! const zig_tooling = @import("zig_tooling");
//! const patterns = zig_tooling.patterns;
//!
//! // Analyze entire project
//! const result = try patterns.checkProject(allocator, ".", null);
//! defer patterns.freeResult(allocator, result);
//!
//! // Quick file check
//! const file_result = try patterns.checkFile(allocator, "src/main.zig", null);
//! defer patterns.freeResult(allocator, file_result);
//! ```

const std = @import("std");
const zig_tooling = @import("zig_tooling.zig");

// Re-export types for convenience
pub const AnalysisResult = zig_tooling.AnalysisResult;
pub const Config = zig_tooling.Config;
pub const Issue = zig_tooling.Issue;
pub const AnalysisError = zig_tooling.AnalysisError;
pub const PatternConfig = zig_tooling.PatternConfig;

/// Progress callback function type for project analysis
pub const ProgressCallback = *const fn (files_processed: u32, total_files: u32, current_file: []const u8) void;

/// Enhanced analysis result with project-level statistics
pub const ProjectAnalysisResult = struct {
    /// All issues found across the project
    issues: []const Issue,
    /// Total number of files analyzed
    files_analyzed: u32,
    /// Total number of issues found
    issues_found: u32,
    /// Total analysis time in milliseconds
    analysis_time_ms: u64,
    /// Files that failed to analyze
    failed_files: []const []const u8,
    /// Files that were skipped due to patterns
    skipped_files: []const []const u8,
    
    pub fn hasErrors(self: ProjectAnalysisResult) bool {
        for (self.issues) |issue| {
            if (issue.severity == .err) return true;
        }
        return false;
    }
    
    pub fn hasWarnings(self: ProjectAnalysisResult) bool {
        for (self.issues) |issue| {
            if (issue.severity == .warning) return true;
        }
        return false;
    }
    
    pub fn getErrorCount(self: ProjectAnalysisResult) u32 {
        var count: u32 = 0;
        for (self.issues) |issue| {
            if (issue.severity == .err) count += 1;
        }
        return count;
    }
    
    pub fn getWarningCount(self: ProjectAnalysisResult) u32 {
        var count: u32 = 0;
        for (self.issues) |issue| {
            if (issue.severity == .warning) count += 1;
        }
        return count;
    }
};

/// Analyzes an entire project directory for both memory safety and test compliance
///
/// This function automatically discovers all .zig files in the specified directory
/// and analyzes them for both memory and testing issues. It provides progress
/// reporting and comprehensive error handling.
///
/// ## Parameters
/// - `allocator`: Allocator for result storage
/// - `project_path`: Path to the project root directory
/// - `config`: Optional configuration (uses optimized defaults if null)
/// - `progress_callback`: Optional callback for progress reporting
///
/// ## Returns
/// `ProjectAnalysisResult` containing all detected issues and project statistics
///
/// ## Example
/// ```zig
/// const result = try patterns.checkProject(allocator, ".", null, null);
/// defer patterns.freeProjectResult(allocator, result);
/// 
/// if (result.hasErrors()) {
///     std.debug.print("Found {} errors in {} files\n", .{
///         result.getErrorCount(), result.files_analyzed
///     });
/// }
/// ```
pub fn checkProject(
    allocator: std.mem.Allocator,
    project_path: []const u8,
    config: ?Config,
    progress_callback: ?ProgressCallback,
) AnalysisError!ProjectAnalysisResult {
    const start_time = std.time.milliTimestamp();
    
    // Use default optimized configuration if none provided
    const analysis_config = config orelse getDefaultProjectConfig();
    
    // Discover all .zig files in the project
    var file_list = std.ArrayList([]const u8).init(allocator);
    defer {
        for (file_list.items) |file_path| {
            allocator.free(file_path);
        }
        file_list.deinit();
    }
    
    try walkProjectDirectory(allocator, &file_list, project_path, analysis_config.patterns);
    
    // Track results and failures
    var all_issues = std.ArrayList(Issue).init(allocator);
    defer all_issues.deinit();
    
    var failed_files = std.ArrayList([]const u8).init(allocator);
    defer failed_files.deinit();
    
    var skipped_files = std.ArrayList([]const u8).init(allocator);
    defer skipped_files.deinit();
    
    // Analyze each file
    for (file_list.items, 0..) |file_path, i| {
        if (progress_callback) |callback| {
            callback(@intCast(i), @intCast(file_list.items.len), file_path);
        }
        
        // Analyze the file
        const file_result = zig_tooling.analyzeFile(allocator, file_path, analysis_config) catch |err| switch (err) {
            AnalysisError.FileNotFound, AnalysisError.AccessDenied, AnalysisError.FileReadError => {
                try failed_files.append(try allocator.dupe(u8, file_path));
                continue;
            },
            else => return err,
        };
        
        // Add all issues to our collection
        for (file_result.issues) |issue| {
            try all_issues.append(Issue{
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
        
        // Clean up file result
        for (file_result.issues) |issue| {
            allocator.free(issue.file_path);
            allocator.free(issue.message);
            if (issue.suggestion) |s| allocator.free(s);
        }
        allocator.free(file_result.issues);
    }
    
    const end_time = std.time.milliTimestamp();
    
    return ProjectAnalysisResult{
        .issues = try all_issues.toOwnedSlice(),
        .files_analyzed = @intCast(file_list.items.len - failed_files.items.len),
        .issues_found = @intCast(all_issues.items.len),
        .analysis_time_ms = @intCast(end_time - start_time),
        .failed_files = try failed_files.toOwnedSlice(),
        .skipped_files = try skipped_files.toOwnedSlice(),
    };
}

/// Analyzes a single file with enhanced error handling and reporting
///
/// This is a convenience wrapper around the core analyzeFile function with
/// better error messages and opinionated defaults for common use cases.
///
/// ## Parameters
/// - `allocator`: Allocator for result storage
/// - `file_path`: Path to the file to analyze
/// - `config`: Optional configuration (uses optimized defaults if null)
///
/// ## Returns
/// `AnalysisResult` containing all detected issues
pub fn checkFile(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    config: ?Config,
) AnalysisError!AnalysisResult {
    // Use default optimized configuration if none provided
    const analysis_config = config orelse getDefaultFileConfig();
    
    // Perform the analysis with enhanced error context
    return zig_tooling.analyzeFile(allocator, file_path, analysis_config) catch |err| switch (err) {
        AnalysisError.FileNotFound => {
            std.log.err("File not found: {s}", .{file_path});
            return err;
        },
        AnalysisError.AccessDenied => {
            std.log.err("Permission denied accessing file: {s}", .{file_path});
            return err;
        },
        AnalysisError.FileReadError => {
            std.log.err("Failed to read file: {s}", .{file_path});
            return err;
        },
        else => return err,
    };
}

/// Analyzes source code directly with enhanced features
///
/// This is a convenience wrapper around the core analyzeSource function with
/// better error handling and opinionated defaults.
///
/// ## Parameters
/// - `allocator`: Allocator for result storage
/// - `source`: Source code to analyze
/// - `config`: Optional configuration (uses optimized defaults if null)
///
/// ## Returns
/// `AnalysisResult` containing all detected issues
pub fn checkSource(
    allocator: std.mem.Allocator,
    source: []const u8,
    config: ?Config,
) AnalysisError!AnalysisResult {
    // Use default optimized configuration if none provided
    const analysis_config = config orelse getDefaultSourceConfig();
    
    return zig_tooling.analyzeSource(allocator, source, analysis_config);
}

/// Frees all memory associated with an AnalysisResult
pub fn freeResult(allocator: std.mem.Allocator, result: AnalysisResult) void {
    for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    }
    allocator.free(result.issues);
}

/// Frees all memory associated with a ProjectAnalysisResult
pub fn freeProjectResult(allocator: std.mem.Allocator, result: ProjectAnalysisResult) void {
    for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    }
    allocator.free(result.issues);
    
    for (result.failed_files) |file_path| {
        allocator.free(file_path);
    }
    allocator.free(result.failed_files);
    
    for (result.skipped_files) |file_path| {
        allocator.free(file_path);
    }
    allocator.free(result.skipped_files);
}

/// Returns optimized default configuration for project analysis
fn getDefaultProjectConfig() Config {
    return Config{
        .memory = .{
            .check_defer = true,
            .check_arena_usage = true,
            .check_allocator_usage = true,
            .allowed_allocators = &.{
                "std.heap.GeneralPurposeAllocator",
                "std.testing.allocator",
                "std.heap.page_allocator",
                "std.heap.c_allocator",
            },
        },
        .testing = .{
            .enforce_categories = true,
            .enforce_naming = true,
            .allowed_categories = &.{ "unit", "integration", "e2e", "performance" },
        },
        .patterns = .{
            .include_patterns = &.{ "**/*.zig" },
            .exclude_patterns = &.{ 
                "**/zig-cache/**", 
                "**/zig-out/**", 
                "**/.zig-cache/**",
                "**/build.zig",
                "**/build.zig.zon"
            },
        },
    };
}

/// Returns optimized default configuration for single file analysis  
fn getDefaultFileConfig() Config {
    return Config{
        .memory = .{
            .check_defer = true,
            .check_arena_usage = true,
            .check_allocator_usage = true,
            .allowed_allocators = &.{
                "std.heap.GeneralPurposeAllocator",
                "std.testing.allocator",
                "std.heap.page_allocator",
                "std.heap.c_allocator",
            },
        },
        .testing = .{
            .enforce_categories = true,
            .enforce_naming = true,
            .allowed_categories = &.{ "unit", "integration", "e2e", "performance" },
        },
    };
}

/// Returns optimized default configuration for source code analysis
fn getDefaultSourceConfig() Config {
    return Config{
        .memory = .{
            .check_defer = true,
            .check_arena_usage = false, // Less relevant for inline source
            .check_allocator_usage = true,
            .allowed_allocators = &.{
                "std.heap.GeneralPurposeAllocator",
                "std.testing.allocator",
                "std.heap.page_allocator",
                "std.heap.c_allocator",
            },
        },
        .testing = .{
            .enforce_categories = false, // More lenient for inline source
            .enforce_naming = true,
            .allowed_categories = &.{ "unit", "integration", "e2e", "performance" },
        },
    };
}

/// Recursively walks a project directory to find .zig files
fn walkProjectDirectory(
    allocator: std.mem.Allocator,
    file_list: *std.ArrayList([]const u8),
    dir_path: []const u8,
    patterns: PatternConfig,
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
                    for (patterns.include_patterns) |include_pattern| {
                        if (matchesPattern(full_path, include_pattern)) {
                            included = true;
                            break;
                        }
                    }
                    
                    // Check exclude patterns
                    if (included) {
                        for (patterns.exclude_patterns) |exclude_pattern| {
                            if (matchesPattern(full_path, exclude_pattern)) {
                                included = false;
                                break;
                            }
                        }
                    }
                    
                    if (included) {
                        try file_list.append(try allocator.dupe(u8, full_path));
                    }
                }
            },
            .directory => {
                // Skip common cache/build directories
                if (std.mem.eql(u8, entry.name, "zig-cache") or 
                    std.mem.eql(u8, entry.name, "zig-out") or
                    std.mem.eql(u8, entry.name, ".zig-cache") or
                    std.mem.eql(u8, entry.name, ".git")) {
                    continue;
                }
                
                // Recursively walk subdirectory
                try walkProjectDirectory(allocator, file_list, full_path, patterns);
            },
            else => {}, // Skip other types
        }
    }
}

/// Simple pattern matching (basic glob support) - reused from build_integration.zig
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
    return std.mem.eql(u8, path, pattern);
}
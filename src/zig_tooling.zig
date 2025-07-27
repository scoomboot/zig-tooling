//! Zig Tooling Library - A comprehensive code analysis toolkit for Zig projects
//! 
//! This library provides static analysis tools for Zig source code, including:
//! - Memory safety analysis (allocation tracking, defer validation, ownership transfer detection)
//! - Testing compliance validation (naming conventions, test organization, coverage tracking)
//! - Scope-aware analysis with 47% false positive reduction
//!
//! ## Quick Start
//! 
//! ```zig
//! const zig_tooling = @import("zig_tooling");
//! 
//! // Analyze a source file
//! const result = try zig_tooling.analyzeFile(allocator, "src/main.zig", null);
//! defer allocator.free(result.issues);
//! 
//! if (result.hasErrors()) {
//!     std.debug.print("Found {} errors\n", .{result.issues_found});
//! }
//! ```

const std = @import("std");
const types = @import("types.zig");

// Re-export core analyzers
pub const MemoryAnalyzer = @import("memory_analyzer.zig").MemoryAnalyzer;
pub const TestingAnalyzer = @import("testing_analyzer.zig").TestingAnalyzer;

// Re-export scope tracking components
const scope_tracker_module = @import("scope_tracker.zig");
pub const ScopeTracker = scope_tracker_module.ScopeTracker;
pub const ScopeTrackerBuilder = scope_tracker_module.ScopeTrackerBuilder;
pub const ScopeType = scope_tracker_module.ScopeType;
pub const ScopeInfo = scope_tracker_module.ScopeInfo;
pub const VariableInfo = scope_tracker_module.VariableInfo;

// Re-export types from types.zig
pub const Issue = types.Issue;
pub const IssueType = types.IssueType;
pub const Severity = types.Severity;
pub const AnalysisResult = types.AnalysisResult;
pub const Config = types.Config;
pub const MemoryConfig = types.MemoryConfig;
pub const TestingConfig = types.TestingConfig;
pub const ScopeConfig = types.ScopeConfig;
pub const PatternConfig = types.PatternConfig;
pub const AnalysisOptions = types.AnalysisOptions;
pub const AnalysisError = types.AnalysisError;
pub const AllocatorPattern = types.AllocatorPattern;

// Re-export other modules for advanced usage
pub const source_context = @import("source_context.zig");

// Re-export logging components
const logger_module = @import("app_logger.zig");
pub const Logger = logger_module.Logger;
pub const LogLevel = logger_module.LogLevel;
pub const LogEvent = logger_module.LogEvent;
pub const LogContext = logger_module.LogContext;
pub const LogCallback = logger_module.LogCallback;
pub const LoggingConfig = logger_module.LoggingConfig;
pub const stderrLogCallback = logger_module.stderrLogCallback;

// Export the entire logger module for advanced usage
pub const app_logger = logger_module;

/// Analyzes memory safety in the provided source code
/// 
/// This function performs comprehensive memory safety analysis including:
/// - Allocation and deallocation tracking
/// - Defer statement validation
/// - Ownership transfer detection
/// - Arena allocator usage in libraries
/// - Allocator type consistency
///
/// ## Parameters
/// - `allocator`: Allocator for result storage
/// - `source`: Source code to analyze
/// - `file_path`: Path of the file being analyzed (for error reporting)
/// - `config`: Optional configuration (uses defaults if null)
///
/// ## Returns
/// `AnalysisResult` containing all detected issues
///
/// ## Example
/// ```zig
/// const source = try std.fs.cwd().readFileAlloc(allocator, "main.zig", 1024 * 1024);
/// defer allocator.free(source);
/// 
/// const result = try analyzeMemory(allocator, source, "main.zig", null);
/// defer allocator.free(result.issues);
/// ```
pub fn analyzeMemory(
    allocator: std.mem.Allocator,
    source: []const u8,
    file_path: []const u8,
    config: ?Config,
) AnalysisError!AnalysisResult {
    const start_time = std.time.milliTimestamp();
    
    var analyzer = if (config) |cfg|
        MemoryAnalyzer.initWithFullConfig(allocator, cfg)
    else
        MemoryAnalyzer.init(allocator);
    defer analyzer.deinit();
    
    analyzer.analyzeSourceCode(file_path, source) catch |err| switch (err) {
        error.OutOfMemory => return AnalysisError.OutOfMemory,
        else => return AnalysisError.ParseError,
    };
    
    const analyzer_issues = analyzer.getIssues();
    const issues = try allocator.alloc(Issue, analyzer_issues.len);
    
    for (analyzer_issues, 0..) |ai, i| {
        issues[i] = Issue{
            .file_path = try allocator.dupe(u8, ai.file_path),
            .line = ai.line,
            .column = ai.column,
            .issue_type = ai.issue_type,
            .severity = ai.severity,
            .message = try allocator.dupe(u8, ai.message),
            .suggestion = if (ai.suggestion) |s| try allocator.dupe(u8, s) else null,
            .code_snippet = ai.code_snippet,
        };
    }
    
    const end_time = std.time.milliTimestamp();
    
    return AnalysisResult{
        .issues = issues,
        .files_analyzed = 1,
        .issues_found = @intCast(issues.len),
        .analysis_time_ms = @intCast(end_time - start_time),
    };
}

/// Analyzes test compliance in the provided source code
///
/// This function validates test organization and naming conventions:
/// - Test naming patterns and categories
/// - Test file organization
/// - Test-to-source mapping
/// - Duplicate test detection
///
/// ## Parameters
/// - `allocator`: Allocator for result storage
/// - `source`: Source code to analyze
/// - `file_path`: Path of the file being analyzed
/// - `config`: Optional configuration (uses defaults if null)
///
/// ## Returns
/// `AnalysisResult` containing all detected issues
pub fn analyzeTests(
    allocator: std.mem.Allocator,
    source: []const u8,
    file_path: []const u8,
    config: ?Config,
) AnalysisError!AnalysisResult {
    const start_time = std.time.milliTimestamp();
    
    var analyzer = if (config) |cfg|
        TestingAnalyzer.initWithFullConfig(allocator, cfg)
    else
        TestingAnalyzer.init(allocator);
    defer analyzer.deinit();
    
    analyzer.analyzeSourceCode(file_path, source) catch {
        return AnalysisError.ParseError;
    };
    
    const analyzer_issues = analyzer.getIssues();
    const issues = try allocator.alloc(Issue, analyzer_issues.len);
    
    for (analyzer_issues, 0..) |ai, i| {
        issues[i] = Issue{
            .file_path = try allocator.dupe(u8, ai.file_path),
            .line = ai.line,
            .column = ai.column,
            .issue_type = ai.issue_type,
            .severity = ai.severity,
            .message = try allocator.dupe(u8, ai.message),
            .suggestion = if (ai.suggestion) |s| try allocator.dupe(u8, s) else null,
            .code_snippet = ai.code_snippet,
        };
    }
    
    const end_time = std.time.milliTimestamp();
    
    return AnalysisResult{
        .issues = issues,
        .files_analyzed = 1,
        .issues_found = @intCast(issues.len),
        .analysis_time_ms = @intCast(end_time - start_time),
    };
}

/// Analyzes a file for both memory safety and test compliance
///
/// This convenience function combines both analyzers to provide
/// comprehensive analysis of a single file.
///
/// ## Parameters
/// - `allocator`: Allocator for result storage
/// - `path`: Path to the file to analyze
/// - `config`: Optional configuration (uses defaults if null)
///
/// ## Returns
/// `AnalysisResult` containing all detected issues from both analyzers
///
/// ## Errors
/// - `FileNotFound`: The specified file does not exist
/// - `AccessDenied`: Cannot read the specified file
/// - `OutOfMemory`: Allocation failure
/// - `ParseError`: Source code parsing failed
pub fn analyzeFile(
    allocator: std.mem.Allocator,
    path: []const u8,
    config: ?Config,
) AnalysisError!AnalysisResult {
    const start_time = std.time.milliTimestamp();
    
    // Read file
    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return AnalysisError.FileNotFound,
        error.AccessDenied => return AnalysisError.AccessDenied,
        else => return AnalysisError.FileReadError,
    };
    defer file.close();
    
    const source = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch |err| switch (err) {
        error.OutOfMemory => return AnalysisError.OutOfMemory,
        else => return AnalysisError.FileReadError,
    };
    defer allocator.free(source);
    
    // Run both analyzers
    const memory_result = try analyzeMemory(allocator, source, path, config);
    defer allocator.free(memory_result.issues);
    
    const testing_result = try analyzeTests(allocator, source, path, config);
    defer allocator.free(testing_result.issues);
    
    // Combine results
    const total_issues = memory_result.issues.len + testing_result.issues.len;
    const combined_issues = try allocator.alloc(Issue, total_issues);
    
    @memcpy(combined_issues[0..memory_result.issues.len], memory_result.issues);
    @memcpy(combined_issues[memory_result.issues.len..], testing_result.issues);
    
    const end_time = std.time.milliTimestamp();
    
    return AnalysisResult{
        .issues = combined_issues,
        .files_analyzed = 1,
        .issues_found = @intCast(total_issues),
        .analysis_time_ms = @intCast(end_time - start_time),
    };
}

/// Analyzes source code directly for both memory safety and test compliance
///
/// This is useful when you already have source code in memory and want
/// to avoid file I/O overhead.
///
/// ## Parameters
/// - `allocator`: Allocator for result storage
/// - `source`: Source code to analyze
/// - `config`: Optional configuration (uses defaults if null)
///
/// ## Returns
/// `AnalysisResult` containing all detected issues from both analyzers
pub fn analyzeSource(
    allocator: std.mem.Allocator,
    source: []const u8,
    config: ?Config,
) AnalysisError!AnalysisResult {
    const file_path = "<source>";
    
    // Run both analyzers
    const memory_result = try analyzeMemory(allocator, source, file_path, config);
    defer allocator.free(memory_result.issues);
    
    const testing_result = try analyzeTests(allocator, source, file_path, config);
    defer allocator.free(testing_result.issues);
    
    // Combine results
    const total_issues = memory_result.issues.len + testing_result.issues.len;
    const combined_issues = try allocator.alloc(Issue, total_issues);
    
    @memcpy(combined_issues[0..memory_result.issues.len], memory_result.issues);
    @memcpy(combined_issues[memory_result.issues.len..], testing_result.issues);
    
    return AnalysisResult{
        .issues = combined_issues,
        .files_analyzed = 1,
        .issues_found = @intCast(total_issues),
        .analysis_time_ms = memory_result.analysis_time_ms + testing_result.analysis_time_ms,
    };
}

// Conversion functions removed - analyzers now use unified types directly from types.zig
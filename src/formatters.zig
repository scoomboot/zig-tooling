//! Result Formatting Utilities for Zig Tooling Library
//!
//! This module provides comprehensive formatting capabilities for analysis results,
//! supporting multiple output formats including text, JSON, and GitHub Actions annotations.
//!
//! ## Quick Start
//!
//! ```zig
//! const formatters = @import("formatters.zig");
//! 
//! // Format as human-readable text
//! const text_output = try formatters.formatAsText(allocator, result, .{});
//! defer allocator.free(text_output);
//!
//! // Format as JSON for programmatic consumption
//! const json_output = try formatters.formatAsJson(allocator, result, .{});
//! defer allocator.free(json_output);
//!
//! // Format for GitHub Actions CI/CD
//! const gh_output = try formatters.formatAsGitHubActions(allocator, result, .{});
//! defer allocator.free(gh_output);
//! ```

const std = @import("std");
const types = @import("types.zig");

// Re-export types for convenience
pub const Issue = types.Issue;
pub const AnalysisResult = types.AnalysisResult;
pub const Severity = types.Severity;
pub const IssueType = types.IssueType;

/// Formatting options that control output appearance and verbosity
pub const FormatOptions = struct {
    /// Include verbose details like code snippets and suggestions
    verbose: bool = false,
    
    /// Include color codes in text output (ANSI escape sequences)
    color: bool = true,
    
    /// Maximum number of issues to include in output (null for no limit)
    max_issues: ?u32 = null,
    
    /// Include performance statistics in output
    include_stats: bool = true,
    
    /// Indent size for JSON formatting
    json_indent: u32 = 2,
};

/// Custom formatter interface for user-defined formatters
/// 
/// Users can implement this interface to create custom output formats:
/// 
/// ```zig
/// const MyFormatter = struct {
///     pub fn format(
///         allocator: std.mem.Allocator,
///         result: AnalysisResult,
///         options: FormatOptions,
///     ) ![]const u8 {
///         // Custom formatting logic here
///         return try std.fmt.allocPrint(allocator, "Custom: {} issues", .{result.issues_found});
///     }
/// };
/// 
/// const output = try MyFormatter.format(allocator, result, .{});
/// ```
pub const CustomFormatter = struct {
    format_fn: *const fn (
        allocator: std.mem.Allocator,
        result: AnalysisResult,
        options: FormatOptions,
    ) anyerror![]const u8,
    
    pub fn format(
        self: CustomFormatter,
        allocator: std.mem.Allocator,
        result: AnalysisResult,
        options: FormatOptions,
    ) ![]const u8 {
        return self.format_fn(allocator, result, options);
    }
};

/// Format analysis results as human-readable text
/// 
/// This formatter produces console-friendly output with optional color support.
/// Perfect for CLI tools and interactive use.
/// 
/// Memory: Caller owns returned string and must free it
pub fn formatAsText(
    allocator: std.mem.Allocator,
    result: AnalysisResult,
    options: FormatOptions,
) ![]const u8 {
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();
    
    const writer = output.writer();
    
    // Header with summary
    if (options.include_stats) {
        try writer.print("Analysis Results\n", .{});
        try writer.print("================\n\n", .{});
        try writer.print("Files analyzed: {}\n", .{result.files_analyzed});
        try writer.print("Issues found: {}\n", .{result.issues_found});
        try writer.print("Analysis time: {}ms\n\n", .{result.analysis_time_ms});
    }
    
    if (result.issues.len == 0) {
        try writer.writeAll("No issues found! ✓\n");
        return output.toOwnedSlice();
    }
    
    // Apply max_issues limit if specified
    const issues_to_show = if (options.max_issues) |max| 
        @min(max, result.issues.len) 
    else 
        result.issues.len;
    
    var error_count: u32 = 0;
    var warning_count: u32 = 0;
    var info_count: u32 = 0;
    
    // Count issues by severity
    for (result.issues[0..issues_to_show]) |issue| {
        switch (issue.severity) {
            .err => error_count += 1,
            .warning => warning_count += 1,
            .info => info_count += 1,
        }
    }
    
    // Summary line
    if (options.color) {
        if (error_count > 0) {
            try writer.print("\x1b[31m", .{}); // Red
        } else if (warning_count > 0) {
            try writer.print("\x1b[33m", .{}); // Yellow
        } else {
            try writer.print("\x1b[32m", .{}); // Green
        }
    }
    
    try writer.print("Found {} errors, {} warnings, {} info", .{ error_count, warning_count, info_count });
    
    if (options.color) {
        try writer.print("\x1b[0m", .{}); // Reset
    }
    try writer.writeAll("\n\n");
    
    // Format individual issues
    for (result.issues[0..issues_to_show], 0..) |issue, i| {
        // Issue header with location and severity
        if (options.color) {
            const color_code = switch (issue.severity) {
                .err => "\x1b[31m",     // Red
                .warning => "\x1b[33m", // Yellow  
                .info => "\x1b[36m",    // Cyan
            };
            try writer.print("{s}{s}\x1b[0m: ", .{ color_code, issue.severity.toString() });
        } else {
            try writer.print("{s}: ", .{issue.severity.toString()});
        }
        
        try writer.print("{s}:{}:{} - {s}\n", .{
            issue.file_path,
            issue.line,
            issue.column,
            issue.message,
        });
        
        // Show issue type for verbose output
        if (options.verbose) {
            try writer.print("  Issue type: {s}\n", .{@tagName(issue.issue_type)});
        }
        
        // Show code snippet if available
        if (options.verbose) {
            if (issue.code_snippet) |snippet| {
            try writer.print("  Code:\n", .{});
            const lines = std.mem.splitScalar(u8, snippet, '\n');
            var line_iter = lines;
            while (line_iter.next()) |line| {
                try writer.print("    {s}\n", .{line});
            }
            }
        }
        
        // Show suggestion if available
        if (issue.suggestion) |suggestion| {
            if (options.color) {
                try writer.print("  \x1b[32mSuggestion:\x1b[0m {s}\n", .{suggestion});
            } else {
                try writer.print("  Suggestion: {s}\n", .{suggestion});
            }
        }
        
        // Add spacing between issues
        if (i < issues_to_show - 1) {
            try writer.writeAll("\n");
        }
    }
    
    // Show truncation message if needed
    if (options.max_issues != null and result.issues.len > issues_to_show) {
        try writer.print("\n... and {} more issues (use --max-issues to see more)\n", 
            .{result.issues.len - issues_to_show});
    }
    
    return output.toOwnedSlice();
}

/// Format analysis results as JSON
/// 
/// This formatter produces structured JSON output suitable for programmatic
/// consumption by other tools, APIs, or storage systems.
/// 
/// Memory: Caller owns returned string and must free it
pub fn formatAsJson(
    allocator: std.mem.Allocator,
    result: AnalysisResult,
    options: FormatOptions,
) ![]const u8 {
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();
    
    const writer = output.writer();
    
    // Apply max_issues limit if specified
    const issues_to_show = if (options.max_issues) |max| 
        @min(max, result.issues.len) 
    else 
        result.issues.len;
    
    // Start JSON object
    try writer.writeAll("{\n");
    
    // Metadata
    if (options.include_stats) {
        try writeJsonIndent(writer, options.json_indent);
        try writer.print("\"metadata\": {{\n", .{});
        
        try writeJsonIndent(writer, options.json_indent * 2);
        try writer.print("\"files_analyzed\": {},\n", .{result.files_analyzed});
        
        try writeJsonIndent(writer, options.json_indent * 2);
        try writer.print("\"total_issues_found\": {},\n", .{result.issues_found});
        
        try writeJsonIndent(writer, options.json_indent * 2);
        try writer.print("\"analysis_time_ms\": {},\n", .{result.analysis_time_ms});
        
        try writeJsonIndent(writer, options.json_indent * 2);
        try writer.print("\"issues_in_output\": {}\n", .{issues_to_show});
        
        try writeJsonIndent(writer, options.json_indent);
        try writer.writeAll("},\n");
    }
    
    // Issues array
    try writeJsonIndent(writer, options.json_indent);
    try writer.writeAll("\"issues\": [\n");
    
    for (result.issues[0..issues_to_show], 0..) |issue, i| {
        try writeJsonIndent(writer, options.json_indent * 2);
        try writer.writeAll("{\n");
        
        // Basic issue fields
        try writeJsonIndent(writer, options.json_indent * 3);
        try writeJsonString(writer, "file_path", issue.file_path);
        try writer.writeAll(",\n");
        
        try writeJsonIndent(writer, options.json_indent * 3);
        try writer.print("\"line\": {},\n", .{issue.line});
        
        try writeJsonIndent(writer, options.json_indent * 3);
        try writer.print("\"column\": {},\n", .{issue.column});
        
        try writeJsonIndent(writer, options.json_indent * 3);
        try writeJsonString(writer, "issue_type", @tagName(issue.issue_type));
        try writer.writeAll(",\n");
        
        try writeJsonIndent(writer, options.json_indent * 3);
        try writeJsonString(writer, "severity", issue.severity.toString());
        try writer.writeAll(",\n");
        
        try writeJsonIndent(writer, options.json_indent * 3);
        try writeJsonString(writer, "message", issue.message);
        
        // Optional fields
        if (issue.suggestion) |suggestion| {
            try writer.writeAll(",\n");
            try writeJsonIndent(writer, options.json_indent * 3);
            try writeJsonString(writer, "suggestion", suggestion);
        }
        
        if (options.verbose) {
            if (issue.code_snippet) |snippet| {
            try writer.writeAll(",\n");
            try writeJsonIndent(writer, options.json_indent * 3);
            try writeJsonString(writer, "code_snippet", snippet);
            }
        }
        
        try writer.writeAll("\n");
        try writeJsonIndent(writer, options.json_indent * 2);
        try writer.writeAll("}");
        
        if (i < issues_to_show - 1) {
            try writer.writeAll(",");
        }
        try writer.writeAll("\n");
    }
    
    try writeJsonIndent(writer, options.json_indent);
    try writer.writeAll("]\n");
    
    try writer.writeAll("}\n");
    
    return output.toOwnedSlice();
}

/// Format analysis results for GitHub Actions
/// 
/// This formatter produces output in GitHub Actions annotation format,
/// which allows CI/CD systems to display issues as inline code annotations.
/// 
/// Memory: Caller owns returned string and must free it
pub fn formatAsGitHubActions(
    allocator: std.mem.Allocator,
    result: AnalysisResult,
    options: FormatOptions,
) ![]const u8 {
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();
    
    const writer = output.writer();
    
    // Apply max_issues limit if specified
    const issues_to_show = if (options.max_issues) |max| 
        @min(max, result.issues.len) 
    else 
        result.issues.len;
    
    // GitHub Actions workflow commands for annotations
    for (result.issues[0..issues_to_show]) |issue| {
        const annotation_type = switch (issue.severity) {
            .err => "error",
            .warning => "warning", 
            .info => "notice",
        };
        
        // GitHub Actions annotation format:
        // ::error file=app.js,line=10,col=15::Something went wrong
        try writer.print("::{s} file=", .{annotation_type});
        try escapeGitHubActionsValue(writer, issue.file_path, true);
        try writer.print(",line={},col={}::", .{ issue.line, issue.column });
        try escapeGitHubActionsValue(writer, issue.message, false);
        
        // Add issue type and suggestion as additional context
        if (options.verbose) {
            try writer.print(" [type: {s}]", .{@tagName(issue.issue_type)});
        }
        
        if (issue.suggestion) |suggestion| {
            try writer.writeAll(" Suggestion: ");
            try escapeGitHubActionsValue(writer, suggestion, false);
        }
        
        try writer.writeAll("\n");
    }
    
    // Summary comment for GitHub Actions
    if (options.include_stats) {
        var error_count: u32 = 0;
        var warning_count: u32 = 0;
        
        for (result.issues[0..issues_to_show]) |issue| {
            switch (issue.severity) {
                .err => error_count += 1,
                .warning => warning_count += 1,
                .info => {},
            }
        }
        
        if (error_count > 0 or warning_count > 0) {
            try writer.print("::notice::Analysis completed: {} errors, {} warnings in {} files ({}ms)\n", .{
                error_count,
                warning_count,
                result.files_analyzed,
                result.analysis_time_ms,
            });
        }
        
        if (options.max_issues != null and result.issues.len > issues_to_show) {
            try writer.print("::warning::Output truncated: showing {} of {} total issues\n", .{
                issues_to_show,
                result.issues.len,
            });
        }
    }
    
    return output.toOwnedSlice();
}

/// Create a custom formatter from a function
/// 
/// This helper allows creating custom formatters from standalone functions:
/// 
/// ```zig
/// fn myFormat(allocator: std.mem.Allocator, result: AnalysisResult, options: FormatOptions) ![]const u8 {
///     return try std.fmt.allocPrint(allocator, "My format: {} issues", .{result.issues_found});
/// }
/// 
/// const formatter = formatters.customFormatter(myFormat);
/// const output = try formatter.format(allocator, result, .{});
/// ```
pub fn customFormatter(
    format_fn: *const fn (
        allocator: std.mem.Allocator,
        result: AnalysisResult,
        options: FormatOptions,
    ) anyerror![]const u8,
) CustomFormatter {
    return CustomFormatter{ .format_fn = format_fn };
}

// Helper functions for formatting

fn writeJsonIndent(writer: anytype, indent: u32) !void {
    var i: u32 = 0;
    while (i < indent) : (i += 1) {
        try writer.writeAll(" ");
    }
}

// Helper to escape strings for GitHub Actions annotations
fn escapeGitHubActionsValue(writer: anytype, value: []const u8, is_property: bool) !void {
    for (value) |char| {
        switch (char) {
            '%' => try writer.writeAll("%25"),
            '\r' => try writer.writeAll("%0D"),
            '\n' => try writer.writeAll("%0A"),
            ':' => if (is_property) try writer.writeAll("%3A") else try writer.writeByte(char),
            ',' => if (is_property) try writer.writeAll("%2C") else try writer.writeByte(char),
            else => try writer.writeByte(char),
        }
    }
}

fn writeJsonString(writer: anytype, key: []const u8, value: []const u8) !void {
    try writer.print("\"{s}\": \"", .{key});
    
    // Escape special characters in JSON string according to RFC 7159
    for (value) |char| {
        switch (char) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\x08' => try writer.writeAll("\\b"), // backspace
            '\x0C' => try writer.writeAll("\\f"), // form feed
            '\n' => try writer.writeAll("\\n"),   // line feed
            '\r' => try writer.writeAll("\\r"),   // carriage return
            '\t' => try writer.writeAll("\\t"),   // tab
            0x00...0x07, 0x0B, 0x0E...0x1F => {
                // Other control characters use \uXXXX format
                try writer.print("\\u{X:0>4}", .{char});
            },
            else => try writer.writeByte(char),
        }
    }
    
    try writer.writeAll("\"");
}

/// Utility function to detect appropriate formatter based on file extension
/// 
/// This is a convenience function for tools that want to automatically
/// choose formatters based on output file names.
pub fn detectFormat(file_path: []const u8) ?enum { text, json, github_actions } {
    if (std.mem.endsWith(u8, file_path, ".json")) {
        return .json;
    } else if (std.mem.endsWith(u8, file_path, ".txt") or std.mem.endsWith(u8, file_path, ".log")) {
        return .text;
    } else if (std.mem.indexOf(u8, file_path, "github") != null or std.mem.indexOf(u8, file_path, "actions") != null) {
        return .github_actions;
    }
    return null;
}

// Tests
test "formatAsText basic functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    // Create sample analysis result
    const issues = [_]Issue{
        Issue{
            .file_path = "test.zig",
            .line = 10,
            .column = 5,
            .issue_type = .missing_defer,
            .severity = .err,
            .message = "Missing defer statement",
            .suggestion = "Add defer allocator.free(ptr);",
        },
    };
    
    const result = AnalysisResult{
        .issues = &issues,
        .files_analyzed = 1,
        .issues_found = 1,
        .analysis_time_ms = 42,
    };
    
    const output = try formatAsText(allocator, result, .{ .color = false });
    defer allocator.free(output);
    
    try testing.expect(std.mem.indexOf(u8, output, "test.zig:10:5") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Missing defer statement") != null);
    try testing.expect(std.mem.indexOf(u8, output, "error:") != null);
}

test "formatAsJson basic functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const issues = [_]Issue{
        Issue{
            .file_path = "test.zig",
            .line = 10,
            .column = 5,
            .issue_type = .missing_defer,
            .severity = .warning,
            .message = "Test message",
        },
    };
    
    const result = AnalysisResult{
        .issues = &issues,
        .files_analyzed = 1,
        .issues_found = 1,
        .analysis_time_ms = 42,
    };
    
    const output = try formatAsJson(allocator, result, .{});
    defer allocator.free(output);
    
    try testing.expect(std.mem.indexOf(u8, output, "\"file_path\": \"test.zig\"") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\"line\": 10") != null);
    try testing.expect(std.mem.indexOf(u8, output, "\"severity\": \"warning\"") != null);
}

test "formatAsGitHubActions basic functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const issues = [_]Issue{
        Issue{
            .file_path = "test.zig",
            .line = 10,
            .column = 5,
            .issue_type = .missing_defer,
            .severity = .err,
            .message = "Test error",
        },
    };
    
    const result = AnalysisResult{
        .issues = &issues,
        .files_analyzed = 1,
        .issues_found = 1,
        .analysis_time_ms = 42,
    };
    
    const output = try formatAsGitHubActions(allocator, result, .{});
    defer allocator.free(output);
    
    try testing.expect(std.mem.indexOf(u8, output, "::error file=test.zig,line=10,col=5::Test error") != null);
}

test "max_issues option works correctly" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const issues = [_]Issue{
        Issue{
            .file_path = "test1.zig",
            .line = 1,
            .column = 1,
            .issue_type = .missing_defer,
            .severity = .err,
            .message = "Error 1",
        },
        Issue{
            .file_path = "test2.zig",
            .line = 2,
            .column = 2,
            .issue_type = .missing_defer,
            .severity = .err,
            .message = "Error 2",
        },
    };
    
    const result = AnalysisResult{
        .issues = &issues,
        .files_analyzed = 2,
        .issues_found = 2,
        .analysis_time_ms = 42,
    };
    
    // Test with max_issues = 1
    const output = try formatAsText(allocator, result, .{ .max_issues = 1, .color = false });
    defer allocator.free(output);
    
    try testing.expect(std.mem.indexOf(u8, output, "Error 1") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Error 2") == null);
    try testing.expect(std.mem.indexOf(u8, output, "and 1 more issues") != null);
}

test "custom formatter works" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const TestFormatter = struct {
        fn format(
            alloc: std.mem.Allocator,
            result: AnalysisResult,
            options: FormatOptions,
        ) ![]const u8 {
            _ = options;
            return try std.fmt.allocPrint(alloc, "Custom: {} issues", .{result.issues_found});
        }
    };
    
    const result = AnalysisResult{
        .issues = &[_]Issue{},
        .files_analyzed = 0,
        .issues_found = 42,
        .analysis_time_ms = 10,
    };
    
    const formatter = customFormatter(TestFormatter.format);
    const output = try formatter.format(allocator, result, .{});
    defer allocator.free(output);
    
    try testing.expectEqualStrings("Custom: 42 issues", output);
}
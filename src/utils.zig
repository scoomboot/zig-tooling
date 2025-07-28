//! Shared utilities for zig-tooling library
//!
//! This module provides utility functions shared across multiple analyzers and components.
//!
//! ## Features
//! - String escaping utilities for JSON, XML, and GitHub Actions
//! - Common helper functions
//! - String manipulation utilities

const std = @import("std");

/// Escape a string for JSON according to RFC 7159
/// 
/// This function properly escapes all required characters:
/// - Quotation marks (")
/// - Backslashes (\)
/// - Control characters (U+0000 through U+001F)
/// 
/// Memory: Caller owns returned string and must free it
pub fn escapeJson(allocator: std.mem.Allocator, str: []const u8) ![]const u8 {
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();
    
    for (str) |char| {
        switch (char) {
            '"' => try output.appendSlice("\\\""),
            '\\' => try output.appendSlice("\\\\"),
            '\x08' => try output.appendSlice("\\b"), // backspace
            '\x0C' => try output.appendSlice("\\f"), // form feed
            '\n' => try output.appendSlice("\\n"),   // line feed
            '\r' => try output.appendSlice("\\r"),   // carriage return
            '\t' => try output.appendSlice("\\t"),   // tab
            0x00...0x07, 0x0B, 0x0E...0x1F => {
                // Other control characters use \uXXXX format
                try output.writer().print("\\u{X:0>4}", .{char});
            },
            else => try output.append(char),
        }
    }
    
    return output.toOwnedSlice();
}

/// Escape a string for XML
/// 
/// This function escapes the five predefined XML entities:
/// - & becomes &amp;
/// - < becomes &lt;
/// - > becomes &gt;
/// - " becomes &quot;
/// - ' becomes &apos;
/// 
/// Memory: Caller owns returned string and must free it
pub fn escapeXml(allocator: std.mem.Allocator, str: []const u8) ![]const u8 {
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();
    
    for (str) |char| {
        switch (char) {
            '&' => try output.appendSlice("&amp;"),
            '<' => try output.appendSlice("&lt;"),
            '>' => try output.appendSlice("&gt;"),
            '"' => try output.appendSlice("&quot;"),
            '\'' => try output.appendSlice("&apos;"),
            else => try output.append(char),
        }
    }
    
    return output.toOwnedSlice();
}

/// Escape a string for GitHub Actions workflow commands
/// 
/// GitHub Actions uses URL encoding for special characters in annotations.
/// Set isProperty to true when escaping property values (file, line, col).
/// 
/// Memory: Caller owns returned string and must free it
pub fn escapeGitHubActions(allocator: std.mem.Allocator, str: []const u8, is_property: bool) ![]const u8 {
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();
    
    for (str) |char| {
        switch (char) {
            '%' => try output.appendSlice("%25"),
            '\r' => try output.appendSlice("%0D"),
            '\n' => try output.appendSlice("%0A"),
            ':' => if (is_property) try output.appendSlice("%3A") else try output.append(char),
            ',' => if (is_property) try output.appendSlice("%2C") else try output.append(char),
            else => try output.append(char),
        }
    }
    
    return output.toOwnedSlice();
}

// Tests
const testing = std.testing;

test "escapeJson handles basic special characters" {
    const allocator = testing.allocator;
    
    const input = "Hello \"world\"\nLine 2\tTabbed\r\nWindows line\\backslash";
    const result = try escapeJson(allocator, input);
    defer allocator.free(result);
    
    const expected = "Hello \\\"world\\\"\\nLine 2\\tTabbed\\r\\nWindows line\\\\backslash";
    try testing.expectEqualStrings(expected, result);
}

test "escapeJson handles control characters" {
    const allocator = testing.allocator;
    
    // Test all control characters
    const input = "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\x0C\x0D\x0E\x0F" ++
                  "\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F";
    const result = try escapeJson(allocator, input);
    defer allocator.free(result);
    
    const expected = "\\u0000\\u0001\\u0002\\u0003\\u0004\\u0005\\u0006\\u0007" ++
                     "\\b\\t\\n\\u000B\\f\\r\\u000E\\u000F" ++
                     "\\u0010\\u0011\\u0012\\u0013\\u0014\\u0015\\u0016\\u0017" ++
                     "\\u0018\\u0019\\u001A\\u001B\\u001C\\u001D\\u001E\\u001F";
    try testing.expectEqualStrings(expected, result);
}

test "escapeJson handles empty string" {
    const allocator = testing.allocator;
    
    const result = try escapeJson(allocator, "");
    defer allocator.free(result);
    
    try testing.expectEqualStrings("", result);
}

test "escapeJson handles Unicode characters" {
    const allocator = testing.allocator;
    
    const input = "Hello 世界 🌍 emoji";
    const result = try escapeJson(allocator, input);
    defer allocator.free(result);
    
    // Non-control Unicode characters should pass through unchanged
    try testing.expectEqualStrings(input, result);
}

test "escapeXml handles all required entities" {
    const allocator = testing.allocator;
    
    const input = "Test & <tag> \"quoted\" 'single' > text";
    const result = try escapeXml(allocator, input);
    defer allocator.free(result);
    
    const expected = "Test &amp; &lt;tag&gt; &quot;quoted&quot; &apos;single&apos; &gt; text";
    try testing.expectEqualStrings(expected, result);
}

test "escapeXml handles empty string" {
    const allocator = testing.allocator;
    
    const result = try escapeXml(allocator, "");
    defer allocator.free(result);
    
    try testing.expectEqualStrings("", result);
}

test "escapeXml preserves normal text" {
    const allocator = testing.allocator;
    
    const input = "Normal text with numbers 123 and symbols !@#$%^*()";
    const result = try escapeXml(allocator, input);
    defer allocator.free(result);
    
    try testing.expectEqualStrings(input, result);
}

test "escapeGitHubActions handles message escaping" {
    const allocator = testing.allocator;
    
    const input = "Error: 50% failed\r\nSecond line\nThird: line";
    const result = try escapeGitHubActions(allocator, input, false);
    defer allocator.free(result);
    
    const expected = "Error: 50%25 failed%0D%0ASecond line%0AThird: line";
    try testing.expectEqualStrings(expected, result);
}

test "escapeGitHubActions handles property escaping" {
    const allocator = testing.allocator;
    
    const input = "file:name,with%special.zig";
    const result = try escapeGitHubActions(allocator, input, true);
    defer allocator.free(result);
    
    const expected = "file%3Aname%2Cwith%25special.zig";
    try testing.expectEqualStrings(expected, result);
}

test "escapeGitHubActions handles empty string" {
    const allocator = testing.allocator;
    
    const result = try escapeGitHubActions(allocator, "", true);
    defer allocator.free(result);
    
    try testing.expectEqualStrings("", result);
}
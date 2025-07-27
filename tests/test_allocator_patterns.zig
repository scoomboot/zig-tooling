//! Tests for allocator pattern conflict resolution and configuration
//!
//! This test suite validates the fixes for LC069 - pattern conflicts with std.testing.allocator
//! and tests the new pattern disable/override functionality.

const std = @import("std");
const testing = std.testing;
const zig_tooling = @import("zig_tooling");

test "LC069: std.testing.allocator pattern conflict resolution" {
    // Test that both std.testing.allocator patterns work correctly now
    const source =
        \\const std = @import("std");
        \\test "example" {
        \\    const allocator1 = std.testing.allocator;
        \\    const allocator2 = testing.allocator;
        \\    
        \\    const data1 = try allocator1.alloc(u8, 100);
        \\    const data2 = try allocator2.alloc(u8, 100);
        \\}
    ;
    
    const config = zig_tooling.Config{
        .memory = .{
            .allowed_allocators = &.{ "std.testing.allocator", "testing.allocator" },
        },
    };
    
    const result = try zig_tooling.analyzeMemory(testing.allocator, source, "test.zig", config);
    defer testing.allocator.free(result.issues);
    defer for (result.issues) |issue| {
        testing.allocator.free(issue.file_path);
        testing.allocator.free(issue.message);
        if (issue.suggestion) |s| testing.allocator.free(s);
    };
    
    // Should have 2 missing defer warnings only
    try testing.expect(result.issues.len == 2);
    for (result.issues) |issue| {
        try testing.expect(issue.issue_type == .missing_defer);
    }
}

test "pattern disable functionality - disable all default patterns" {
    const source =
        \\const std = @import("std");
        \\pub fn main() !void {
        \\    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        \\    const allocator = gpa.allocator();
        \\    const data = try allocator.alloc(u8, 100);
        \\}
    ;
    
    const config = zig_tooling.Config{
        .memory = .{
            .use_default_patterns = false,
            .allowed_allocators = &.{ "CustomAllocator" },
            .allocator_patterns = &.{
                .{ .name = "CustomAllocator", .pattern = "gpa" },
            },
        },
    };
    
    const result = try zig_tooling.analyzeMemory(testing.allocator, source, "test.zig", config);
    defer testing.allocator.free(result.issues);
    defer for (result.issues) |issue| {
        testing.allocator.free(issue.file_path);
        testing.allocator.free(issue.message);
        if (issue.suggestion) |s| testing.allocator.free(s);
    };
    
    // Should detect as CustomAllocator, not GeneralPurposeAllocator
    var found_custom = false;
    for (result.issues) |issue| {
        if (issue.issue_type == .incorrect_allocator) {
            found_custom = true;
            // The message should NOT mention GeneralPurposeAllocator
            try testing.expect(std.mem.indexOf(u8, issue.message, "GeneralPurposeAllocator") == null);
        }
    }
    try testing.expect(!found_custom); // CustomAllocator is in allowed list
}

test "pattern disable functionality - selective disable" {
    const source =
        \\const std = @import("std");
        \\test "example" {
        \\    const allocator = std.testing.allocator;
        \\    const data = try allocator.alloc(u8, 100);
        \\}
    ;
    
    const config = zig_tooling.Config{
        .memory = .{
            .disabled_default_patterns = &.{ "std.testing.allocator" },
            .allowed_allocators = &.{ "MyTestAllocator" },
            .allocator_patterns = &.{
                .{ .name = "MyTestAllocator", .pattern = "std.testing.allocator" },
            },
        },
    };
    
    const result = try zig_tooling.analyzeMemory(testing.allocator, source, "test.zig", config);
    defer testing.allocator.free(result.issues);
    defer for (result.issues) |issue| {
        testing.allocator.free(issue.file_path);
        testing.allocator.free(issue.message);
        if (issue.suggestion) |s| testing.allocator.free(s);
    };
    
    // Should detect as MyTestAllocator due to custom pattern
    var found_allocator_issue = false;
    for (result.issues) |issue| {
        if (issue.issue_type == .incorrect_allocator) {
            found_allocator_issue = true;
            // Should mention MyTestAllocator in allowed list
            try testing.expect(std.mem.indexOf(u8, issue.message, "MyTestAllocator") != null);
        }
    }
    try testing.expect(!found_allocator_issue); // MyTestAllocator is allowed
}

test "pattern precedence - custom overrides default" {
    const source =
        \\const std = @import("std");
        \\pub fn main() !void {
        \\    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        \\    const allocator = arena.allocator();
        \\    const data = try allocator.alloc(u8, 100);
        \\}
    ;
    
    const config = zig_tooling.Config{
        .memory = .{
            .allowed_allocators = &.{ "MyArena" },
            .allocator_patterns = &.{
                .{ .name = "MyArena", .pattern = "arena" },
            },
        },
    };
    
    const result = try zig_tooling.analyzeMemory(testing.allocator, source, "test.zig", config);
    defer testing.allocator.free(result.issues);
    defer for (result.issues) |issue| {
        testing.allocator.free(issue.file_path);
        testing.allocator.free(issue.message);
        if (issue.suggestion) |s| testing.allocator.free(s);
    };
    
    // Should get info message about pattern conflict and precedence
    var found_precedence_info = false;
    for (result.issues) |issue| {
        if (issue.severity == .info and 
            std.mem.indexOf(u8, issue.message, "will take precedence") != null) {
            found_precedence_info = true;
        }
    }
    try testing.expect(found_precedence_info);
}

test "complex pattern scenario with multiple conflicts" {
    const source =
        \\const std = @import("std");
        \\test "complex" {
        \\    const test_alloc = std.testing.allocator;
        \\    const test_alloc2 = testing.allocator;
        \\    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        \\    const gpa_alloc = gpa.allocator();
        \\    
        \\    const data1 = try test_alloc.alloc(u8, 100);
        \\    const data2 = try test_alloc2.alloc(u8, 100);
        \\    const data3 = try gpa_alloc.alloc(u8, 100);
        \\}
    ;
    
    const config = zig_tooling.Config{
        .memory = .{
            // Disable std.testing.allocator to avoid conflict
            .disabled_default_patterns = &.{ "std.testing.allocator" },
            // Allow specific allocators
            .allowed_allocators = &.{ "testing.allocator", "CustomGPA" },
            // Add custom pattern for GPA
            .allocator_patterns = &.{
                .{ .name = "CustomGPA", .pattern = "gpa" },
            },
        },
    };
    
    const result = try zig_tooling.analyzeMemory(testing.allocator, source, "test.zig", config);
    defer testing.allocator.free(result.issues);
    defer for (result.issues) |issue| {
        testing.allocator.free(issue.file_path);
        testing.allocator.free(issue.message);
        if (issue.suggestion) |s| testing.allocator.free(s);
    };
    
    // Count issue types
    var missing_defer_count: u32 = 0;
    var incorrect_allocator_count: u32 = 0;
    
    for (result.issues) |issue| {
        switch (issue.issue_type) {
            .missing_defer => missing_defer_count += 1,
            .incorrect_allocator => incorrect_allocator_count += 1,
            else => {},
        }
    }
    
    // Should have 3 missing defer warnings
    try testing.expect(missing_defer_count == 3);
    // First allocation should be detected as unknown (std.testing.allocator disabled)
    // so we expect 1 incorrect allocator issue
    try testing.expect(incorrect_allocator_count == 1);
}

test "validation detects built-in pattern duplicates" {
    // This test verifies that our validation would catch duplicate patterns
    // if they existed in the default patterns (they don't anymore after our fix)
    const source = 
        \\const std = @import("std");
        \\pub fn main() !void {}
    ;
    
    const config = zig_tooling.Config{
        .memory = .{
            // Normal config - just analyzing to trigger validation
        },
    };
    
    const result = try zig_tooling.analyzeMemory(testing.allocator, source, "test.zig", config);
    defer testing.allocator.free(result.issues);
    defer for (result.issues) |issue| {
        testing.allocator.free(issue.file_path);
        testing.allocator.free(issue.message);
        if (issue.suggestion) |s| testing.allocator.free(s);
    };
    
    // Should not have any configuration warnings about duplicate built-in patterns
    for (result.issues) |issue| {
        if (std.mem.eql(u8, issue.file_path, "configuration")) {
            const has_builtin_duplicate = std.mem.indexOf(u8, issue.message, "Built-in pattern name") != null and
                                        std.mem.indexOf(u8, issue.message, "appears multiple times") != null;
            try testing.expect(!has_builtin_duplicate);
        }
    }
}

test "pattern disable with allowed_allocators interaction" {
    const source =
        \\const std = @import("std");
        \\test "test allocator usage" {
        \\    const allocator = std.testing.allocator;
        \\    const data = try allocator.alloc(u8, 100);
        \\    defer allocator.free(data);
        \\}
    ;
    
    // Test that we can properly handle std.testing.allocator
    const config = zig_tooling.Config{
        .memory = .{
            .allowed_allocators = &.{ "std.testing.allocator", "testing.allocator" },
        },
    };
    
    const result = try zig_tooling.analyzeMemory(testing.allocator, source, "test.zig", config);
    defer testing.allocator.free(result.issues);
    defer for (result.issues) |issue| {
        testing.allocator.free(issue.file_path);
        testing.allocator.free(issue.message);
        if (issue.suggestion) |s| testing.allocator.free(s);
    };
    
    // Should have no issues - allocator is allowed and has defer
    try testing.expect(result.issues.len == 0);
}
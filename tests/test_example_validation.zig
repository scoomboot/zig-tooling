//! Test Example Validation
//!
//! This test validates that all file references in the examples directory
//! actually exist. This prevents issues like LC059 where example files
//! reference non-existent sample files.

const std = @import("std");
const testing = std.testing;

/// Pattern to match file path string literals in Zig code
const FilePathPattern = struct {
    /// Check if a line contains a potential file path reference
    fn extractFilePath(line: []const u8) ?[]const u8 {
        // Find string literals enclosed in quotes
        var start_idx: usize = 0;
        while (std.mem.indexOfScalarPos(u8, line, start_idx, '"')) |quote_start| {
            const content_start = quote_start + 1;
            if (std.mem.indexOfScalarPos(u8, line, content_start, '"')) |quote_end| {
                const potential_path = line[content_start..quote_end];
                if (looksLikeFilePath(potential_path)) {
                    return potential_path;
                }
                start_idx = quote_end + 1;
            } else {
                break;
            }
        }
        return null;
    }
    
    /// Determine if a string looks like a file path
    fn looksLikeFilePath(s: []const u8) bool {
        // Empty or too short to be a path
        if (s.len < 3) return false;
        
        // Known placeholder filenames/paths that shouldn't be validated
        const placeholders = [_][]const u8{
            "inline_code.zig",
            "custom_patterns.zig", // Used in advanced/custom_patterns.zig example
            "file.zig",
            "test.zig",
            "main.zig", // When used without a path
            "src/main.zig", // Common example path
            "tools/quality_check.zig", // Common example path
            "tools/pre_commit_setup.zig", // Common example path
            ".git/hooks/pre-commit", // Git hook path
            "my_app", // Example app name
            "another.zig", // Generic example file
            "late.zig", // Generic example file
            "example.zig", // Generic example file
            "perf_test.zig", // Example test file
            "examples/sample_project", // Example project path
        };
        
        for (placeholders) |placeholder| {
            if (std.mem.eql(u8, s, placeholder)) {
                return false;
            }
        }
        
        // Must contain at least one of these to be considered a path
        if (!containsAny(s, &.{ "/", ".zig", ".yml", ".yaml", ".json", ".md" })) {
            return false;
        }
        
        // Filter out glob patterns
        if (std.mem.indexOf(u8, s, "*") != null or
            std.mem.indexOf(u8, s, "**") != null) {
            return false;
        }
        
        // Filter out import statements and other non-file references
        if (std.mem.startsWith(u8, s, "std.") or
            std.mem.startsWith(u8, s, "zig_tooling") or
            std.mem.startsWith(u8, s, "!") or
            std.mem.indexOf(u8, s, " ") != null or // Paths shouldn't have spaces
            std.mem.indexOf(u8, s, "\n") != null or
            std.mem.indexOf(u8, s, "\\n") != null or
            std.mem.indexOf(u8, s, "\\\\") != null or // Escaped characters
            std.mem.indexOf(u8, s, "{") != null or // Format strings
            std.mem.indexOf(u8, s, "}") != null or
            std.mem.indexOf(u8, s, "[") != null or // Array syntax
            std.mem.indexOf(u8, s, "]") != null or
            std.mem.indexOf(u8, s, "(") != null or // Function calls
            std.mem.indexOf(u8, s, ")") != null or
            std.mem.indexOf(u8, s, ":") != null and !isWindowsPath(s)) // Colons only in Windows paths
        {
            return false;
        }
        
        return true;
    }
    
    fn containsAny(haystack: []const u8, needles: []const []const u8) bool {
        for (needles) |needle| {
            if (std.mem.indexOf(u8, haystack, needle) != null) {
                return true;
            }
        }
        return false;
    }
    
    fn isWindowsPath(s: []const u8) bool {
        // Simple check for Windows drive letters
        return s.len >= 3 and 
               ((s[0] >= 'A' and s[0] <= 'Z') or (s[0] >= 'a' and s[0] <= 'z')) and
               s[1] == ':' and
               (s[2] == '/' or s[2] == '\\');
    }
};

/// Result of validating a single example file
const ValidationResult = struct {
    file_path: []const u8,
    missing_references: std.ArrayList(MissingReference),
    
    const MissingReference = struct {
        line_number: usize,
        referenced_path: []const u8,
        line_content: []const u8,
    };
    
    fn deinit(self: *ValidationResult, allocator: std.mem.Allocator) void {
        for (self.missing_references.items) |ref| {
            allocator.free(ref.referenced_path);
            allocator.free(ref.line_content);
        }
        self.missing_references.deinit();
    }
};

/// Validate all file references in a single example file
fn validateExampleFile(allocator: std.mem.Allocator, file_path: []const u8) !ValidationResult {
    var result = ValidationResult{
        .file_path = file_path,
        .missing_references = std.ArrayList(ValidationResult.MissingReference).init(allocator),
    };
    errdefer result.deinit(allocator);
    
    // Read the file
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();
    
    const content = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(content);
    
    // Process line by line
    var line_iter = std.mem.splitScalar(u8, content, '\n');
    var line_number: usize = 0;
    
    while (line_iter.next()) |line| {
        line_number += 1;
        
        // Skip comments that are obviously documentation
        if (std.mem.startsWith(u8, std.mem.trimLeft(u8, line, " \t"), "//!") or
            std.mem.startsWith(u8, std.mem.trimLeft(u8, line, " \t"), "///")) {
            continue;
        }
        
        // Extract potential file path
        if (FilePathPattern.extractFilePath(line)) |path| {
            // Check if the file exists
            if (!try fileExists(path)) {
                // Also check relative to the example file's directory
                const example_dir = std.fs.path.dirname(file_path) orelse ".";
                const relative_path = try std.fs.path.join(allocator, &.{ example_dir, path });
                defer allocator.free(relative_path);
                
                if (!try fileExists(relative_path)) {
                    // File doesn't exist in either location
                    // Store a copy of the path and line content
                    const path_copy = try allocator.dupe(u8, path);
                    errdefer allocator.free(path_copy);
                    const line_copy = try allocator.dupe(u8, line);
                    errdefer allocator.free(line_copy);
                    
                    try result.missing_references.append(.{
                        .line_number = line_number,
                        .referenced_path = path_copy,
                        .line_content = line_copy,
                    });
                }
            }
        }
    }
    
    return result;
}

/// Check if a file exists
fn fileExists(path: []const u8) !bool {
    std.fs.cwd().access(path, .{}) catch |err| {
        switch (err) {
            error.FileNotFound => return false,
            else => return err,
        }
    };
    return true;
}

/// Recursively find all .zig files in a directory
fn findZigFiles(allocator: std.mem.Allocator, dir_path: []const u8, files: *std.ArrayList([]const u8)) !void {
    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();
    
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const entry_path = try std.fs.path.join(allocator, &.{ dir_path, entry.name });
        defer allocator.free(entry_path);
        
        switch (entry.kind) {
            .file => {
                if (std.mem.endsWith(u8, entry.name, ".zig")) {
                    const owned_path = try allocator.dupe(u8, entry_path);
                    try files.append(owned_path);
                }
            },
            .directory => {
                // Skip hidden directories and zig-cache
                if (!std.mem.startsWith(u8, entry.name, ".") and
                    !std.mem.eql(u8, entry.name, "zig-cache") and
                    !std.mem.eql(u8, entry.name, "zig-out")) {
                    try findZigFiles(allocator, entry_path, files);
                }
            },
            else => {},
        }
    }
}

test "unit: validate all example file references" {
    const allocator = testing.allocator;
    
    // Find all .zig files in the examples directory
    var zig_files = std.ArrayList([]const u8).init(allocator);
    defer {
        for (zig_files.items) |file| {
            allocator.free(file);
        }
        zig_files.deinit();
    }
    
    try findZigFiles(allocator, "examples", &zig_files);
    
    // Track all validation failures
    var all_failures = std.ArrayList(ValidationResult).init(allocator);
    defer {
        for (all_failures.items) |*result| {
            result.deinit(allocator);
        }
        all_failures.deinit();
    }
    
    // Validate each file
    for (zig_files.items) |file_path| {
        const result = try validateExampleFile(allocator, file_path);
        
        if (result.missing_references.items.len > 0) {
            try all_failures.append(result);
        } else {
            var mut_result = result;
            mut_result.deinit(allocator);
        }
    }
    
    // Report failures
    if (all_failures.items.len > 0) {
        std.debug.print("\n=== Example File Reference Validation Failed ===\n", .{});
        std.debug.print("Found {} example files with missing references:\n\n", .{all_failures.items.len});
        
        for (all_failures.items) |result| {
            std.debug.print("File: {s}\n", .{result.file_path});
            for (result.missing_references.items) |ref| {
                std.debug.print("  Line {}: Referenced file not found: {s}\n", .{
                    ref.line_number,
                    ref.referenced_path,
                });
                std.debug.print("    > {s}\n", .{std.mem.trim(u8, ref.line_content, " \t")});
            }
            std.debug.print("\n", .{});
        }
        
        // Fail the test
        try testing.expect(false);
    }
}

test "unit: file path pattern detection" {
    // Test the pattern matching logic
    const test_cases = .{
        // Should match
        .{ .input = "\"tests/test_file.zig\"", .should_match = true },
        .{ .input = "\"src/main.zig\"", .should_match = true },
        .{ .input = "\"path/to/file.json\"", .should_match = true },
        .{ .input = "\"README.md\"", .should_match = true },
        .{ .input = "\".github/workflows/ci.yml\"", .should_match = true },
        
        // Should not match
        .{ .input = "\"std.testing.allocator\"", .should_match = false },
        .{ .input = "\"zig_tooling\"", .should_match = false },
        .{ .input = "\"Hello World\"", .should_match = false },
        .{ .input = "\"![]const u8\"", .should_match = false },
        .{ .input = "\"test string with spaces\"", .should_match = false },
    };
    
    inline for (test_cases) |tc| {
        const extracted = FilePathPattern.extractFilePath(tc.input);
        if (tc.should_match) {
            try testing.expect(extracted != null);
        } else {
            try testing.expect(extracted == null);
        }
    }
}

test "unit: validate specific example patterns" {
    // Test case from basic_usage.zig
    const line = "        \"tests/integration/sample_projects/simple_memory_issues/src/main.zig\",";
    const extracted = FilePathPattern.extractFilePath(line);
    try testing.expect(extracted != null);
    try testing.expectEqualStrings("tests/integration/sample_projects/simple_memory_issues/src/main.zig", extracted.?);
    
    // Verify this file actually exists
    const exists = try fileExists(extracted.?);
    try testing.expect(exists);
}
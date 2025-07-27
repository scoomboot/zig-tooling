//! Custom Analyzer Example
//!
//! This example demonstrates how to create custom analyzers using the
//! zig-tooling library's ScopeTracker and other components.

const std = @import("std");
const zig_tooling = @import("zig_tooling");

/// Custom analyzer that checks for specific code patterns
const CustomAnalyzer = struct {
    allocator: std.mem.Allocator,
    issues: std.ArrayList(zig_tooling.Issue),
    scope_tracker: ?*zig_tooling.ScopeTracker,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .issues = std.ArrayList(zig_tooling.Issue).init(allocator),
            .scope_tracker = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.issues.deinit();
        if (self.scope_tracker) |tracker| {
            tracker.deinit();
            self.allocator.destroy(tracker);
        }
    }

    /// Analyze source code for custom patterns
    pub fn analyzeSource(self: *Self, source: []const u8, file_path: []const u8) !zig_tooling.AnalysisResult {
        // Build scope tracker with custom configuration
        const builder = zig_tooling.ScopeTrackerBuilder.init(self.allocator);
        self.scope_tracker = try builder
            .withSource(source)
            .withFileName(file_path)
            .withConfig(.{
                .track_variables = true,
                .track_types = true,
                .track_imports = true,
                .max_depth = 10,
            })
            .build();

        // Run custom analysis
        try self.checkNamingConventions();
        try self.checkFunctionComplexity();
        try self.checkImportOrganization();
        try self.checkErrorHandling();

        return .{
            .issues = try self.allocator.dupe(zig_tooling.Issue, self.issues.items),
            .issues_found = @intCast(self.issues.items.len),
            .files_analyzed = 1,
            .analysis_time_ms = 0, // Would track actual time in production
        };
    }

    /// Check for naming convention violations
    fn checkNamingConventions(self: *Self) !void {
        const tracker = self.scope_tracker.?;
        
        // Check all functions
        const functions = tracker.findScopesByType(.function);
        for (functions) |func| {
            const info = tracker.getScopeInfo(func);
            
            // Check for snake_case in function names (should be camelCase)
            if (std.mem.indexOf(u8, info.name, "_")) |_| {
                // Exception for test functions
                if (!std.mem.startsWith(u8, info.name, "test")) {
                    try self.addIssue(.{
                        .file_path = try self.allocator.dupe(u8, tracker.file_name),
                        .line = info.start_line,
                        .column = info.start_column,
                        .severity = .warning,
                        .issue_type = .naming_convention,
                        .message = try std.fmt.allocPrint(
                            self.allocator,
                            "Function '{s}' uses snake_case, prefer camelCase",
                            .{info.name},
                        ),
                        .suggestion = try std.fmt.allocPrint(
                            self.allocator,
                            "Rename to '{s}'",
                            .{try toCamelCase(self.allocator, info.name)},
                        ),
                    });
                }
            }
            
            // Check for overly short function names
            if (info.name.len < 3 and !std.mem.eql(u8, info.name, "eq")) {
                try self.addIssue(.{
                    .file_path = try self.allocator.dupe(u8, tracker.file_name),
                    .line = info.start_line,
                    .column = info.start_column,
                    .severity = .info,
                    .issue_type = .naming_convention,
                    .message = try std.fmt.allocPrint(
                        self.allocator,
                        "Function name '{s}' is very short",
                        .{info.name},
                    ),
                    .suggestion = "Consider using a more descriptive name",
                });
            }
        }

        // Check struct naming (should be PascalCase)
        const structs = tracker.findScopesByType(.struct_type);
        for (structs) |struct_scope| {
            const info = tracker.getScopeInfo(struct_scope);
            
            if (info.name.len > 0 and !std.ascii.isUpper(info.name[0])) {
                try self.addIssue(.{
                    .file_path = try self.allocator.dupe(u8, tracker.file_name),
                    .line = info.start_line,
                    .column = info.start_column,
                    .severity = .warning,
                    .issue_type = .naming_convention,
                    .message = try std.fmt.allocPrint(
                        self.allocator,
                        "Struct '{s}' should use PascalCase",
                        .{info.name},
                    ),
                    .suggestion = null,
                });
            }
        }
    }

    /// Check function complexity
    fn checkFunctionComplexity(self: *Self) !void {
        const tracker = self.scope_tracker.?;
        const functions = tracker.findScopesByType(.function);

        for (functions) |func| {
            const info = tracker.getScopeInfo(func);
            const stats = tracker.getStats();
            
            // Get nested depth within function
            var max_depth: u32 = 0;
            var current = func;
            while (tracker.getParent(current)) |parent| {
                if (tracker.getScopeInfo(parent).scope_type == .function) break;
                max_depth += 1;
                current = parent;
            }

            // Check for excessive nesting
            if (max_depth > 4) {
                try self.addIssue(.{
                    .file_path = try self.allocator.dupe(u8, tracker.file_name),
                    .line = info.start_line,
                    .column = info.start_column,
                    .severity = .warning,
                    .issue_type = .complexity,
                    .message = try std.fmt.allocPrint(
                        self.allocator,
                        "Function '{s}' has excessive nesting depth: {}",
                        .{ info.name, max_depth },
                    ),
                    .suggestion = "Consider extracting nested logic into separate functions",
                });
            }

            // Check function length (lines)
            const func_lines = info.end_line - info.start_line;
            if (func_lines > 50) {
                try self.addIssue(.{
                    .file_path = try self.allocator.dupe(u8, tracker.file_name),
                    .line = info.start_line,
                    .column = info.start_column,
                    .severity = .info,
                    .issue_type = .complexity,
                    .message = try std.fmt.allocPrint(
                        self.allocator,
                        "Function '{s}' is {} lines long",
                        .{ info.name, func_lines },
                    ),
                    .suggestion = "Consider breaking this function into smaller functions",
                });
            }
        }
    }

    /// Check import organization
    fn checkImportOrganization(self: *Self) !void {
        const tracker = self.scope_tracker.?;
        const source_context = try zig_tooling.source_context.SourceContext.init(
            self.allocator,
            tracker.source,
            tracker.file_name,
        );
        defer source_context.deinit();

        var lines = std.mem.tokenize(u8, tracker.source, "\n");
        var line_num: u32 = 1;
        var last_import_line: u32 = 0;
        var found_non_import = false;

        while (lines.next()) |line| : (line_num += 1) {
            const trimmed = std.mem.trim(u8, line, " \t");
            
            // Skip empty lines and comments
            if (trimmed.len == 0 or std.mem.startsWith(u8, trimmed, "//")) continue;

            if (std.mem.startsWith(u8, trimmed, "const") and 
                std.mem.indexOf(u8, trimmed, "@import")) |_| {
                
                if (found_non_import and last_import_line > 0) {
                    try self.addIssue(.{
                        .file_path = try self.allocator.dupe(u8, tracker.file_name),
                        .line = line_num,
                        .column = 1,
                        .severity = .info,
                        .issue_type = .style,
                        .message = "Import statement found after non-import code",
                        .suggestion = "Group all imports at the beginning of the file",
                    });
                }
                last_import_line = line_num;
            } else if (!std.mem.startsWith(u8, trimmed, "pub") and 
                      !std.mem.startsWith(u8, trimmed, "test")) {
                found_non_import = true;
            }
        }
    }

    /// Check error handling patterns
    fn checkErrorHandling(self: *Self) !void {
        const tracker = self.scope_tracker.?;
        const functions = tracker.findScopesByType(.function);

        for (functions) |func| {
            const info = tracker.getScopeInfo(func);
            
            // Skip test functions
            if (std.mem.startsWith(u8, info.name, "test")) continue;

            // Check if function returns error union
            if (std.mem.indexOf(u8, tracker.source[info.start_pos..info.end_pos], "!")) |_| {
                // Look for try statements without corresponding error handling
                var func_source = tracker.source[info.start_pos..info.end_pos];
                var try_count: u32 = 0;
                var catch_count: u32 = 0;
                var errdefer_count: u32 = 0;

                // Count try statements
                var search_pos: usize = 0;
                while (std.mem.indexOfPos(u8, func_source, search_pos, "try ")) |pos| {
                    try_count += 1;
                    search_pos = pos + 4;
                }

                // Count catch blocks
                search_pos = 0;
                while (std.mem.indexOfPos(u8, func_source, search_pos, "catch")) |pos| {
                    catch_count += 1;
                    search_pos = pos + 5;
                }

                // Count errdefer
                search_pos = 0;
                while (std.mem.indexOfPos(u8, func_source, search_pos, "errdefer")) |pos| {
                    errdefer_count += 1;
                    search_pos = pos + 8;
                }

                // Check for resource allocation without errdefer
                if (std.mem.indexOf(u8, func_source, "allocator.alloc") != null or
                    std.mem.indexOf(u8, func_source, "allocator.create") != null) {
                    if (errdefer_count == 0) {
                        try self.addIssue(.{
                            .file_path = try self.allocator.dupe(u8, tracker.file_name),
                            .line = info.start_line,
                            .column = info.start_column,
                            .severity = .warning,
                            .issue_type = .error_handling,
                            .message = try std.fmt.allocPrint(
                                self.allocator,
                                "Function '{s}' allocates resources but has no errdefer cleanup",
                                .{info.name},
                            ),
                            .suggestion = "Add errdefer statements to clean up resources on error",
                        });
                    }
                }
            }
        }
    }

    fn addIssue(self: *Self, issue: zig_tooling.Issue) !void {
        try self.issues.append(issue);
    }
};

/// Convert snake_case to camelCase
fn toCamelCase(allocator: std.mem.Allocator, snake_case: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var capitalize_next = false;
    for (snake_case, 0..) |char, i| {
        if (char == '_') {
            capitalize_next = true;
        } else if (capitalize_next) {
            try result.append(std.ascii.toUpper(char));
            capitalize_next = false;
        } else {
            try result.append(char);
        }
    }

    return try result.toOwnedSlice();
}

/// Example: Combining custom analyzer with built-in analyzers
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source_code =
        \\const std = @import("std");
        \\
        \\// Bad: struct should be PascalCase
        \\const my_struct = struct {
        \\    value: u32,
        \\};
        \\
        \\// Bad: function uses snake_case
        \\pub fn do_something_complex(allocator: std.mem.Allocator) !void {
        \\    const data = try allocator.alloc(u8, 100);
        \\    // Missing errdefer!
        \\    
        \\    if (true) {
        \\        if (true) {
        \\            if (true) {
        \\                if (true) {
        \\                    if (true) {
        \\                        // Too deeply nested!
        \\                        return error.TooComplex;
        \\                    }
        \\                }
        \\            }
        \\        }
        \\    }
        \\}
        \\
        \\const another = @import("another.zig");
        \\
        \\// Bad: import after code
        \\const late_import = @import("late.zig");
    ;

    // Run custom analyzer
    var custom = CustomAnalyzer.init(allocator);
    defer custom.deinit();

    const custom_result = try custom.analyzeSource(source_code, "example.zig");
    defer allocator.free(custom_result.issues);
    defer for (custom_result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };

    // Also run built-in memory analyzer
    const memory_result = try zig_tooling.analyzeMemory(
        allocator,
        source_code,
        "example.zig",
        null,
    );
    defer allocator.free(memory_result.issues);
    defer for (memory_result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };

    // Combine results
    var all_issues = std.ArrayList(zig_tooling.Issue).init(allocator);
    defer all_issues.deinit();

    try all_issues.appendSlice(custom_result.issues);
    try all_issues.appendSlice(memory_result.issues);

    const combined_result = zig_tooling.AnalysisResult{
        .issues = try all_issues.toOwnedSlice(),
        .issues_found = @intCast(all_issues.items.len),
        .files_analyzed = 1,
        .analysis_time_ms = 0,
    };
    defer allocator.free(combined_result.issues);

    // Format and display results
    const output = try zig_tooling.formatters.formatAsText(allocator, combined_result, .{
        .color = true,
        .verbose = true,
    });
    defer allocator.free(output);

    std.debug.print("=== Combined Analysis Results ===\n{s}\n", .{output});
    
    // Demonstrate scope tracker features
    std.debug.print("\n=== Scope Tracker Stats ===\n", .{});
    if (custom.scope_tracker) |tracker| {
        const stats = tracker.getStats();
        std.debug.print("Total scopes: {}\n", .{stats.total_scopes});
        std.debug.print("Max depth: {}\n", .{stats.max_depth});
        std.debug.print("Functions: {}\n", .{tracker.findScopesByType(.function).len});
        std.debug.print("Structs: {}\n", .{tracker.findScopesByType(.struct_type).len});
    }
}
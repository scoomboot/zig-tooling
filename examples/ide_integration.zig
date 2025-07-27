//! IDE Integration Example
//!
//! This example demonstrates how to integrate zig-tooling into an IDE or editor
//! for real-time code analysis, diagnostics, and quick fixes.

const std = @import("std");
const zig_tooling = @import("zig_tooling");

/// IDE integration server that provides real-time analysis
const IdeServer = struct {
    allocator: std.mem.Allocator,
    /// Cache of analyzed files for incremental updates
    file_cache: std.StringHashMap(FileCache),
    /// Configuration for analysis
    config: zig_tooling.Config,
    /// Logger for debugging
    logger: ?zig_tooling.Logger,

    const Self = @This();

    const FileCache = struct {
        content: []const u8,
        last_analysis: zig_tooling.AnalysisResult,
        version: u32,
    };

    /// Diagnostic information for IDE consumption
    const Diagnostic = struct {
        file: []const u8,
        range: Range,
        severity: Severity,
        message: []const u8,
        code: []const u8,
        quick_fixes: []const QuickFix,
    };

    const Range = struct {
        start: Position,
        end: Position,
    };

    const Position = struct {
        line: u32,
        character: u32,
    };

    const Severity = enum {
        @"error",
        warning,
        information,
        hint,
    };

    const QuickFix = struct {
        title: []const u8,
        edit: TextEdit,
    };

    const TextEdit = struct {
        range: Range,
        new_text: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) !Self {
        return .{
            .allocator = allocator,
            .file_cache = std.StringHashMap(FileCache).init(allocator),
            .config = .{
                .memory = .{
                    .check_defer = true,
                    .check_arena_usage = true,
                    .check_allocator_usage = true,
                },
                .testing = .{
                    .enforce_categories = true,
                    .enforce_naming = true,
                    .allowed_categories = &.{ "unit", "integration", "e2e" },
                },
                .options = .{
                    .max_issues = 50, // Limit for performance
                    .verbose = false,
                    .continue_on_error = true,
                },
                .logging = .{
                    .enabled = true,
                    .callback = ideLogCallback,
                    .min_level = .debug,
                },
            },
            .logger = null,
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.file_cache.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.content);
            self.allocator.free(entry.value_ptr.last_analysis.issues);
            for (entry.value_ptr.last_analysis.issues) |issue| {
                self.allocator.free(issue.file_path);
                self.allocator.free(issue.message);
                if (issue.suggestion) |s| self.allocator.free(s);
            }
        }
        self.file_cache.deinit();
    }

    /// Handle file opened in editor
    pub fn onFileOpen(self: *Self, file_path: []const u8, content: []const u8) ![]Diagnostic {
        const file_key = try self.allocator.dupe(u8, file_path);
        const file_content = try self.allocator.dupe(u8, content);

        const result = try zig_tooling.analyzeSource(self.allocator, content, self.config);

        try self.file_cache.put(file_key, .{
            .content = file_content,
            .last_analysis = result,
            .version = 1,
        });

        return try self.convertToDiagnostics(result, file_path);
    }

    /// Handle file changed in editor (incremental update)
    pub fn onFileChange(
        self: *Self,
        file_path: []const u8,
        content: []const u8,
        changed_range: ?Range,
    ) ![]Diagnostic {
        var entry = self.file_cache.getPtr(file_path) orelse {
            // File not in cache, treat as new file
            return try self.onFileOpen(file_path, content);
        };

        // Update content
        self.allocator.free(entry.content);
        entry.content = try self.allocator.dupe(u8, content);
        entry.version += 1;

        // For now, re-analyze entire file
        // In production, could do incremental analysis based on changed_range
        self.allocator.free(entry.last_analysis.issues);
        for (entry.last_analysis.issues) |issue| {
            self.allocator.free(issue.file_path);
            self.allocator.free(issue.message);
            if (issue.suggestion) |s| self.allocator.free(s);
        }

        entry.last_analysis = try zig_tooling.analyzeSource(self.allocator, content, self.config);

        return try self.convertToDiagnostics(entry.last_analysis, file_path);
    }

    /// Handle file saved
    pub fn onFileSave(self: *Self, file_path: []const u8) ![]Diagnostic {
        const entry = self.file_cache.get(file_path) orelse {
            return &[_]Diagnostic{};
        };

        // Could trigger additional analysis or update persistent diagnostics
        return try self.convertToDiagnostics(entry.last_analysis, file_path);
    }

    /// Handle file closed
    pub fn onFileClose(self: *Self, file_path: []const u8) void {
        if (self.file_cache.fetchRemove(file_path)) |entry| {
            self.allocator.free(entry.key);
            self.allocator.free(entry.value.content);
            self.allocator.free(entry.value.last_analysis.issues);
            for (entry.value.last_analysis.issues) |issue| {
                self.allocator.free(issue.file_path);
                self.allocator.free(issue.message);
                if (issue.suggestion) |s| self.allocator.free(s);
            }
        }
    }

    /// Get code actions (quick fixes) for a position
    pub fn getCodeActions(
        self: *Self,
        file_path: []const u8,
        position: Position,
    ) ![]QuickFix {
        const entry = self.file_cache.get(file_path) orelse {
            return &[_]QuickFix{};
        };

        var quick_fixes = std.ArrayList(QuickFix).init(self.allocator);
        defer quick_fixes.deinit();

        for (entry.last_analysis.issues) |issue| {
            // Check if issue is at or near the requested position
            if (issue.line == position.line) {
                if (issue.suggestion) |suggestion| {
                    // Generate quick fix based on issue type
                    const fix = try self.generateQuickFix(issue, suggestion, entry.content);
                    if (fix) |f| {
                        try quick_fixes.append(f);
                    }
                }
            }
        }

        return try quick_fixes.toOwnedSlice();
    }

    /// Convert analysis results to IDE diagnostics
    fn convertToDiagnostics(
        self: *Self,
        result: zig_tooling.AnalysisResult,
        file_path: []const u8,
    ) ![]Diagnostic {
        var diagnostics = std.ArrayList(Diagnostic).init(self.allocator);
        defer diagnostics.deinit();

        for (result.issues) |issue| {
            const severity: Severity = switch (issue.severity) {
                .err => .@"error",
                .warning => .warning,
                .info => .information,
            };

            const code = switch (issue.issue_type) {
                .missing_defer => "ZT001",
                .missing_errdefer => "ZT002",
                .allocator_mismatch => "ZT003",
                .arena_in_library => "ZT004",
                .ownership_transfer => "ZT005",
                .missing_test_category => "ZT101",
                .invalid_test_name => "ZT102",
                .invalid_test_category => "ZT103",
                else => "ZT000",
            };

            // Calculate end position (approximate)
            const end_column = issue.column + 20; // Simple approximation

            var quick_fixes = std.ArrayList(QuickFix).init(self.allocator);
            defer quick_fixes.deinit();

            if (issue.suggestion) |suggestion| {
                const fix = try self.generateQuickFix(issue, suggestion, "");
                if (fix) |f| {
                    try quick_fixes.append(f);
                }
            }

            try diagnostics.append(.{
                .file = file_path,
                .range = .{
                    .start = .{ .line = issue.line - 1, .character = issue.column - 1 },
                    .end = .{ .line = issue.line - 1, .character = end_column },
                },
                .severity = severity,
                .message = issue.message,
                .code = code,
                .quick_fixes = try quick_fixes.toOwnedSlice(),
            });
        }

        return try diagnostics.toOwnedSlice();
    }

    /// Generate quick fix for an issue
    fn generateQuickFix(
        self: *Self,
        issue: zig_tooling.Issue,
        suggestion: []const u8,
        content: []const u8,
    ) !?QuickFix {
        _ = content; // Would use for context

        return switch (issue.issue_type) {
            .missing_defer => QuickFix{
                .title = suggestion,
                .edit = .{
                    .range = .{
                        .start = .{ .line = issue.line - 1, .character = issue.column - 1 },
                        .end = .{ .line = issue.line - 1, .character = issue.column - 1 },
                    },
                    .new_text = "\n    defer allocator.free(allocation);",
                },
            },
            .missing_test_category => QuickFix{
                .title = "Add test category",
                .edit = .{
                    .range = .{
                        .start = .{ .line = issue.line - 1, .character = 5 },
                        .end = .{ .line = issue.line - 1, .character = 5 },
                    },
                    .new_text = "\"unit: ",
                },
            },
            else => null,
        };
    }
};

/// Custom log callback for IDE integration
fn ideLogCallback(event: zig_tooling.LogEvent) void {
    // In real IDE integration, would send to IDE's output panel
    const level_str = switch (event.level) {
        .debug => "[DEBUG]",
        .info => "[INFO]",
        .warn => "[WARN]",
        .err => "[ERROR]",
    };

    std.debug.print("{s} {s}: {s}\n", .{ level_str, event.category, event.message });
}

/// Example IDE integration usage
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize IDE server
    var server = try IdeServer.init(allocator);
    defer server.deinit();

    // Simulate IDE operations
    std.debug.print("=== IDE Integration Example ===\n\n", .{});

    // 1. File opened in editor
    const file_path = "virtual://example.zig";
    const initial_content =
        \\const std = @import("std");
        \\
        \\pub fn processData(allocator: std.mem.Allocator) !void {
        \\    const buffer = try allocator.alloc(u8, 1024);
        \\    // Missing defer!
        \\    
        \\    try doWork(buffer);
        \\}
        \\
        \\test "missing category" {
        \\    try std.testing.expect(true);
        \\}
    ;

    std.debug.print("1. Opening file...\n", .{});
    const diagnostics = try server.onFileOpen(file_path, initial_content);
    defer allocator.free(diagnostics);
    defer for (diagnostics) |diag| {
        allocator.free(diag.quick_fixes);
    };

    std.debug.print("   Found {} diagnostics:\n", .{diagnostics.len});
    for (diagnostics) |diag| {
        std.debug.print("   - Line {}: {s} [{s}]\n", .{
            diag.range.start.line + 1,
            diag.message,
            diag.code,
        });
    }

    // 2. Get code actions at specific position
    std.debug.print("\n2. Getting code actions at line 4...\n", .{});
    const actions = try server.getCodeActions(file_path, .{ .line = 4, .character = 5 });
    defer allocator.free(actions);

    for (actions) |action| {
        std.debug.print("   Quick fix: {s}\n", .{action.title});
    }

    // 3. File changed (user adds defer)
    const updated_content =
        \\const std = @import("std");
        \\
        \\pub fn processData(allocator: std.mem.Allocator) !void {
        \\    const buffer = try allocator.alloc(u8, 1024);
        \\    defer allocator.free(buffer);
        \\    
        \\    try doWork(buffer);
        \\}
        \\
        \\test "unit: fixed test" {
        \\    try std.testing.expect(true);
        \\}
    ;

    std.debug.print("\n3. File changed (fixed issues)...\n", .{});
    const new_diagnostics = try server.onFileChange(file_path, updated_content, null);
    defer allocator.free(new_diagnostics);
    defer for (new_diagnostics) |diag| {
        allocator.free(diag.quick_fixes);
    };

    std.debug.print("   Now {} diagnostics remain\n", .{new_diagnostics.len});

    // 4. File saved
    std.debug.print("\n4. File saved...\n", .{});
    const save_diagnostics = try server.onFileSave(file_path);
    defer allocator.free(save_diagnostics);
    defer for (save_diagnostics) |diag| {
        allocator.free(diag.quick_fixes);
    };

    // 5. File closed
    std.debug.print("\n5. Closing file...\n", .{});
    server.onFileClose(file_path);
    std.debug.print("   File cache cleared\n", .{});

    // Demonstrate real-time analysis performance
    std.debug.print("\n=== Performance Test ===\n", .{});
    const large_file = try generateLargeFile(allocator);
    defer allocator.free(large_file);

    const start_time = std.time.milliTimestamp();
    const perf_diagnostics = try server.onFileOpen("perf_test.zig", large_file);
    defer allocator.free(perf_diagnostics);
    defer for (perf_diagnostics) |diag| {
        allocator.free(diag.quick_fixes);
    };
    const elapsed = std.time.milliTimestamp() - start_time;

    std.debug.print("Analyzed {} lines in {}ms\n", .{
        std.mem.count(u8, large_file, "\n"),
        elapsed,
    });
}

/// Generate a large file for performance testing
fn generateLargeFile(allocator: std.mem.Allocator) ![]const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try buffer.appendSlice("const std = @import(\"std\");\n\n");

    // Generate many functions with various patterns
    var i: u32 = 0;
    while (i < 50) : (i += 1) {
        try buffer.writer().print(
            \\pub fn function{d}(allocator: std.mem.Allocator) !void {{
            \\    const data = try allocator.alloc(u8, {d});
            \\    defer allocator.free(data);
            \\    // Some work...
            \\}}
            \\
            \\
        , .{ i, (i + 1) * 100 });
    }

    return try buffer.toOwnedSlice();
}
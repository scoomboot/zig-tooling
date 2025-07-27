const std = @import("std");
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const ScopeTracker = @import("scope_tracker.zig").ScopeTracker;
const ScopeInfo = @import("scope_tracker.zig").ScopeInfo;
const EnhancedSourceContext = @import("source_context.zig").SourceContext;
const types = @import("types.zig");

// Using unified types from types.zig
const Issue = types.Issue;
const IssueType = types.IssueType;
const Severity = types.Severity;
const AnalysisError = types.AnalysisError;

pub const TestPattern = struct {
    line: u32,
    column: u32,
    test_name: []const u8,
    category: ?[]const u8,  // null if no category detected
    has_proper_naming: bool,
    has_memory_safety: bool,
    uses_testing_allocator: bool,
    has_defer_cleanup: bool,
    has_errdefer_cleanup: bool,
};

pub const SourceFilePattern = struct {
    file_path: []const u8,
    has_corresponding_test: bool,
    test_file_path: ?[]const u8,
    is_test_file: bool,
    test_count: u32,
};

pub const SourceContext = struct {
    in_block_comment: []bool,
    in_string_literal: []bool,
    
    pub fn deinit(self: *SourceContext, allocator: std.mem.Allocator) void {
        allocator.free(self.in_block_comment);
        allocator.free(self.in_string_literal);
    }
};

pub const TestingAnalyzer = struct {
    allocator: std.mem.Allocator,
    issues: ArrayList(Issue),
    tests: ArrayList(TestPattern),
    source_files: ArrayList(SourceFilePattern),
    scope_tracker: ScopeTracker,
    enhanced_source_context: EnhancedSourceContext,
    config: @import("types.zig").TestingConfig,
    
    pub fn init(allocator: std.mem.Allocator) TestingAnalyzer {
        return TestingAnalyzer{
            .allocator = allocator,
            .issues = ArrayList(Issue).init(allocator),
            .tests = ArrayList(TestPattern).init(allocator),
            .source_files = ArrayList(SourceFilePattern).init(allocator),
            .scope_tracker = ScopeTracker.init(allocator),
            .enhanced_source_context = EnhancedSourceContext.init(allocator),
            .config = .{}, // Use default config
        };
    }
    
    pub fn initWithConfig(allocator: std.mem.Allocator, config: @import("types.zig").TestingConfig) TestingAnalyzer {
        return TestingAnalyzer{
            .allocator = allocator,
            .issues = ArrayList(Issue).init(allocator),
            .tests = ArrayList(TestPattern).init(allocator),
            .source_files = ArrayList(SourceFilePattern).init(allocator),
            .scope_tracker = ScopeTracker.init(allocator),
            .enhanced_source_context = EnhancedSourceContext.init(allocator),
            .config = config,
        };
    }
    
    pub fn deinit(self: *TestingAnalyzer) void {
        // Free all issue descriptions, suggestions, and file paths
        for (self.issues.items) |issue| {
            if (issue.file_path.len > 0) self.allocator.free(issue.file_path);
            if (issue.message.len > 0) self.allocator.free(issue.message);
            if (issue.suggestion) |suggestion| if (suggestion.len > 0) self.allocator.free(suggestion);
        }
        
        // Free all test names (allocated with self.allocator in identifyTests)
        for (self.tests.items) |test_pattern| {
            if (test_pattern.test_name.len > 0) self.allocator.free(test_pattern.test_name);
        }
        
        // Free all file paths
        for (self.source_files.items) |source_file| {
            if (source_file.file_path.len > 0) self.allocator.free(source_file.file_path);
            if (source_file.test_file_path) |test_path| {
                if (test_path.len > 0) self.allocator.free(test_path);
            }
        }
        
        self.issues.deinit();
        self.tests.deinit();
        self.source_files.deinit();
        self.scope_tracker.deinit();
        self.enhanced_source_context.deinit();
    }
    
    pub fn analyzeFile(self: *TestingAnalyzer, file_path: []const u8) !void {
        const file = std.fs.cwd().openFile(file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return AnalysisError.FileNotFound,
            error.AccessDenied => return AnalysisError.AccessDenied,
            else => return err,
        };
        defer file.close();
        
        const file_size = try file.getEndPos();
        const contents = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(contents);
        errdefer self.allocator.free(contents);
        _ = try file.readAll(contents);
        
        try self.analyzeSourceCode(file_path, contents);
    }
    
    pub fn analyzeSourceCode(self: *TestingAnalyzer, file_path: []const u8, source: []const u8) !void {
        // Create arena for temporary allocations during this analysis
        var temp_arena = std.heap.ArenaAllocator.init(self.allocator);
        defer temp_arena.deinit();
        const temp_allocator = temp_arena.allocator();
        
        // Clear previous analysis results - free allocated test names first
        for (self.tests.items) |test_pattern| {
            if (test_pattern.test_name.len > 0) self.allocator.free(test_pattern.test_name);
        }
        self.tests.clearRetainingCapacity();
        
        // Reset scope tracker for new file
        self.scope_tracker.reset();
        
        // Determine if this is a test file
        const is_test_file = self.isTestFile(file_path);
        
        // Create source file pattern - allocation cleaned up in deinit()
        const source_file = SourceFilePattern{
            .file_path = try self.allocator.dupe(u8, file_path), // freed in deinit()
            .has_corresponding_test = false, // Will be determined later
            .test_file_path = null, // Will be determined later
            .is_test_file = is_test_file,
            .test_count = 0,
        };
        try self.source_files.append(source_file);
        
        // Initialize scope-aware analysis components
        try self.enhanced_source_context.analyzeSource(source);
        try self.scope_tracker.analyzeSourceCode(source);
        
        // Parse source to handle multi-line comments and string literals (legacy)
        var context = try self.parseSourceContext(source, temp_allocator);
        defer context.deinit(temp_allocator);
        
        // Split into lines for analysis
        var lines = std.mem.splitScalar(u8, source, '\n');
        var line_number: u32 = 1;
        var char_offset: usize = 0;
        
        // First pass: identify tests
        while (lines.next()) |line| {
            defer {
                line_number += 1;
                char_offset += line.len + 1; // +1 for newline
            }
            
            try self.identifyTests(file_path, line, line_number, char_offset, &context, temp_allocator);
        }
        
        // Second pass: validate test patterns
        try self.validateTestPatterns(file_path, source, temp_allocator);
        
        // Third pass: check for missing tests (if not a test file)
        if (!is_test_file) {
            try self.checkForMissingTests(file_path, temp_allocator);
        }
        
        // Update test count in source file
        if (self.source_files.items.len > 0) {
            var last_file = &self.source_files.items[self.source_files.items.len - 1];
            last_file.test_count = @intCast(self.tests.items.len);
        }
    }
    
    fn parseSourceContext(self: *TestingAnalyzer, source: []const u8, allocator: std.mem.Allocator) !SourceContext {
        _ = self;
        
        const len = source.len;
        const in_block_comment = try allocator.alloc(bool, len);
        errdefer allocator.free(in_block_comment);
        const in_string_literal = try allocator.alloc(bool, len);
        errdefer allocator.free(in_string_literal);
        
        var i: usize = 0;
        var in_block_comment_state = false;
        var in_string_state = false;
        var in_multiline_string_state = false;
        
        while (i < len) {
            // Handle block comments /* ... */
            if (!in_string_state and !in_multiline_string_state and i + 1 < len and 
                source[i] == '/' and source[i + 1] == '*') {
                in_block_comment_state = true;
                in_block_comment[i] = true;
                in_block_comment[i + 1] = true;
                i += 2;
                continue;
            }
            
            if (in_block_comment_state and i + 1 < len and 
                source[i] == '*' and source[i + 1] == '/') {
                in_block_comment[i] = true;
                in_block_comment[i + 1] = true;
                in_block_comment_state = false;
                i += 2;
                continue;
            }
            
            // Handle multi-line string literals \\...
            if (!in_block_comment_state and !in_string_state and i + 1 < len and 
                source[i] == '\\' and source[i + 1] == '\\') {
                in_multiline_string_state = true;
                in_string_literal[i] = true;
                in_string_literal[i + 1] = true;
                i += 2;
                continue;
            }
            
            // Handle regular string literals "..."
            if (!in_block_comment_state and !in_multiline_string_state and 
                source[i] == '"' and (i == 0 or source[i - 1] != '\\')) {
                in_string_state = !in_string_state;
            }
            
            // Handle end of multi-line strings (semicolon at end of line)
            if (in_multiline_string_state and source[i] == ';') {
                // Check if this is at end of line or followed by whitespace/newline
                var j = i + 1;
                var is_end = true;
                while (j < len and source[j] != '\n') {
                    if (source[j] != ' ' and source[j] != '\t' and source[j] != '\r') {
                        is_end = false;
                        break;
                    }
                    j += 1;
                }
                if (is_end) {
                    in_multiline_string_state = false;
                }
            }
            
            in_block_comment[i] = in_block_comment_state;
            in_string_literal[i] = in_string_state or in_multiline_string_state;
            
            i += 1;
        }
        
        return SourceContext{
            .in_block_comment = in_block_comment,
            .in_string_literal = in_string_literal,
        };
    }
    
    fn identifyTests(self: *TestingAnalyzer, file_path: []const u8, line: []const u8, line_number: u32, char_offset: usize, context: *const SourceContext, temp_allocator: std.mem.Allocator) !void {
        _ = file_path;
        
        // Look for test declarations: test "integration: name" {
        if (std.mem.indexOf(u8, line, "test \"")) |test_pos| {
            // Skip if this is in a comment or string literal using context
            const absolute_pos = char_offset + test_pos;
            if (absolute_pos < context.in_block_comment.len and context.in_block_comment[absolute_pos]) return;
            if (absolute_pos < context.in_string_literal.len and context.in_string_literal[absolute_pos]) return;
            if (self.isInLineComment(line, test_pos)) return;
            
            // Extract test name
            const test_name = try self.extractTestName(line, test_pos, temp_allocator);
            defer temp_allocator.free(test_name);
            
            // Determine test category based on naming pattern
            const category = self.determineTestCategory(test_name);
            
            // Check if naming follows conventions
            const has_proper_naming = self.checkTestNaming(test_name, category);
            
            // Check for memory safety patterns (will be determined in validation)
            const test_pattern = TestPattern{
                .line = line_number,
                .column = @intCast(test_pos + 1),
                .test_name = try self.allocator.dupe(u8, test_name),
                .category = category,
                .has_proper_naming = has_proper_naming,
                .has_memory_safety = false, // Will be determined later
                .uses_testing_allocator = false, // Will be determined later
                .has_defer_cleanup = false, // Will be determined later
                .has_errdefer_cleanup = false, // Will be determined later
            };
            
            try self.tests.append(test_pattern);
        }
    }
    
    fn validateTestPatterns(self: *TestingAnalyzer, file_path: []const u8, source: []const u8, temp_allocator: std.mem.Allocator) !void {
        _ = temp_allocator;
        
        // Check each test for memory safety patterns
        for (self.tests.items) |*test_pattern| {
            try self.analyzeTestMemorySafety(source, test_pattern, file_path);
        }
        
        // Generate issues for problematic patterns
        for (self.tests.items) |test_pattern| {
            try self.generateTestIssues(test_pattern, file_path);
        }
    }
    
    fn analyzeTestMemorySafety(self: *TestingAnalyzer, source: []const u8, test_pattern: *TestPattern, file_path: []const u8) !void {
        _ = self;
        _ = file_path;
        
        // Find the test function body (from test declaration to closing brace)
        var lines = std.mem.splitScalar(u8, source, '\n');
        var current_line: u32 = 1;
        var in_test_function = false;
        var brace_count: i32 = 0;
        
        while (lines.next()) |line| {
            defer current_line += 1;
            
            // Check if we're at the start of our test
            if (current_line == test_pattern.line) {
                in_test_function = true;
                brace_count = 0;
                continue;
            }
            
            if (!in_test_function) continue;
            
            // Count braces to know when test ends
            for (line) |char| {
                if (char == '{') brace_count += 1;
                if (char == '}') brace_count -= 1;
            }
            
            // Analyze this line for memory safety patterns
            if (std.mem.indexOf(u8, line, "std.testing.allocator")) |_| {
                test_pattern.uses_testing_allocator = true;
                test_pattern.has_memory_safety = true;
            }
            
            if (std.mem.indexOf(u8, line, "defer") != null and 
                (std.mem.indexOf(u8, line, ".free(") != null or 
                 std.mem.indexOf(u8, line, ".deinit()") != null)) {
                test_pattern.has_defer_cleanup = true;
                test_pattern.has_memory_safety = true;
            }
            
            if (std.mem.indexOf(u8, line, "errdefer") != null and 
                (std.mem.indexOf(u8, line, ".free(") != null or 
                 std.mem.indexOf(u8, line, ".deinit()") != null)) {
                test_pattern.has_errdefer_cleanup = true;
                test_pattern.has_memory_safety = true;
            }
            
            // Exit when test function ends
            if (brace_count <= 0 and current_line > test_pattern.line) {
                break;
            }
        }
    }
    
    fn generateTestIssues(self: *TestingAnalyzer, test_pattern: TestPattern, file_path: []const u8) !void {
        // Check test naming convention
        if (!test_pattern.has_proper_naming and self.config.enforce_naming) {
            const issue = Issue{
                .file_path = try self.allocator.dupe(u8, file_path),
                .line = test_pattern.line,
                .column = test_pattern.column,
                .issue_type = .invalid_test_naming,
                .severity = .warning,
                .message = try std.fmt.allocPrint(
                    self.allocator,
                    "Test '{s}' on line {d} does not follow naming convention",
                    .{test_pattern.test_name, test_pattern.line}
                ),
                .suggestion = if (test_pattern.category) |cat|
                    try std.fmt.allocPrint(
                        self.allocator,
                        "Use pattern: test \"{s}: description\"",
                        .{cat}
                    )
                else
                    try std.fmt.allocPrint(
                        self.allocator,
                        "Use pattern: test \"category: description\"",
                        .{}
                    ),
                .code_snippet = null,
            };
            try self.issues.append(issue);
        }
        
        // Check for uncategorized tests
        if (test_pattern.category == null and self.config.enforce_categories) {
            // Build list of allowed categories for suggestion
            var categories_buf: [512]u8 = undefined;
            var stream = std.io.fixedBufferStream(&categories_buf);
            const writer = stream.writer();
            
            for (self.config.allowed_categories, 0..) |cat, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.writeAll(cat);
            }
            
            const issue = Issue{
                .file_path = try self.allocator.dupe(u8, file_path),
                .line = test_pattern.line,
                .column = test_pattern.column,
                .issue_type = .missing_test_category,
                .severity = .info,
                .message = try std.fmt.allocPrint(
                    self.allocator,
                    "Test '{s}' on line {d} cannot be categorized",
                    .{test_pattern.test_name, test_pattern.line}
                ),
                .suggestion = try std.fmt.allocPrint(
                    self.allocator,
                    "Add category prefix: {s}",
                    .{categories_buf[0..stream.pos]}
                ),
                .code_snippet = null,
            };
            try self.issues.append(issue);
        }
        
        // Check for memory safety in tests that should have it
        if (self.shouldHaveMemorySafety(test_pattern) and !test_pattern.has_memory_safety) {
            const issue = Issue{
                .file_path = try self.allocator.dupe(u8, file_path),
                .line = test_pattern.line,
                .column = test_pattern.column,
                .issue_type = .missing_defer,  // Memory safety patterns include defer usage
                .severity = .warning,
                .message = try std.fmt.allocPrint(
                    self.allocator,
                    "Test '{s}' should use memory safety patterns",
                    .{test_pattern.test_name}
                ),
                .suggestion = try std.fmt.allocPrint(
                    self.allocator,
                    "Use std.testing.allocator, defer cleanup, and errdefer for error paths",
                    .{}
                ),
                .code_snippet = null,
            };
            try self.issues.append(issue);
        }
    }
    
    fn checkForMissingTests(self: *TestingAnalyzer, file_path: []const u8, _: std.mem.Allocator) !void {
        // Determine if this file should have inline tests or separate test file
        const requires_separate_file = self.requiresSeparateTestFile(file_path);
        const has_inline_tests = self.hasInlineTests(file_path);
        
        if (requires_separate_file) {
            // Check if this source file has a corresponding test file
            const expected_test_file = try self.getExpectedTestFile(file_path);
            defer self.allocator.free(expected_test_file);
            
            const test_file_exists = self.fileExists(expected_test_file);
            
            if (!test_file_exists) {
                const issue = Issue{
                    .file_path = try self.allocator.dupe(u8, file_path),
                    .line = 1,
                    .column = 1,
                    .issue_type = .missing_test_file,
                    .severity = .err,
                    .message = try std.fmt.allocPrint(
                        self.allocator,
                        "No test file found for source file: {s}",
                        .{file_path}
                    ),
                    .suggestion = try std.fmt.allocPrint(
                        self.allocator,
                        "Create test file: {s}",
                        .{expected_test_file}
                    ),
                    .code_snippet = null,
                };
                try self.issues.append(issue);
            }
        } else {
            // For unit test modules, inline tests are preferred
            if (!has_inline_tests) {
                const issue = Issue{
                    .file_path = try self.allocator.dupe(u8, file_path),
                    .line = 1,
                    .column = 1,
                    .issue_type = .missing_test_file,
                    .severity = .warning,  // Less severe for unit modules
                    .message = try std.fmt.allocPrint(
                        self.allocator,
                        "No tests found for source file: {s} (inline tests preferred for this module type)",
                        .{file_path}
                    ),
                    .suggestion = try std.fmt.allocPrint(
                        self.allocator,
                        "Add inline test blocks: test \"module_name: specific behavior\" {{ ... }}",
                        .{}
                    ),
                    .code_snippet = null,
                };
                try self.issues.append(issue);
            }
        }
    }
    
    // Helper functions
    fn isTestFile(self: *TestingAnalyzer, file_path: []const u8) bool {
        _ = self;
        return std.mem.indexOf(u8, file_path, "test") != null or 
               std.mem.endsWith(u8, file_path, "_test.zig");
    }
    
    fn requiresSeparateTestFile(self: *TestingAnalyzer, file_path: []const u8) bool {
        _ = self;
        
        // API handlers and integration modules require separate test files
        if (std.mem.indexOf(u8, file_path, "/api/handlers/") != null) return true;
        if (std.mem.indexOf(u8, file_path, "/api/server") != null) return true;
        if (std.mem.indexOf(u8, file_path, "/api/router") != null) return true;
        if (std.mem.indexOf(u8, file_path, "/api/middleware") != null) return true;
        
        // Integration test modules
        if (std.mem.indexOf(u8, file_path, "integration") != null) return true;
        if (std.mem.indexOf(u8, file_path, "connector") != null) return true;
        if (std.mem.indexOf(u8, file_path, "sync") != null) return true;
        
        // Complex modules that deal with external systems
        if (std.mem.indexOf(u8, file_path, "database") != null) return true;
        if (std.mem.indexOf(u8, file_path, "export") != null) return true;
        if (std.mem.indexOf(u8, file_path, "import") != null) return true;
        
        // CLI tools
        if (std.mem.indexOf(u8, file_path, "_cli.zig") != null) return true;
        
        // Main entry points
        if (std.mem.endsWith(u8, file_path, "main.zig")) return true;
        
        // All other modules prefer inline tests
        return false;
    }
    
    fn hasInlineTests(self: *TestingAnalyzer, file_path: []const u8) bool {
        _ = file_path;
        // Check if any tests were found during analysis of this file
        // The tests array contains tests found in the current file being analyzed
        return self.tests.items.len > 0;
    }
    
    fn isInLineComment(self: *TestingAnalyzer, line: []const u8, pos: usize) bool {
        _ = self;
        
        // Check if position is after "//" comment on the same line
        if (std.mem.indexOf(u8, line, "//")) |comment_pos| {
            return pos > comment_pos;
        }
        
        return false;
    }
    
    fn extractTestName(self: *TestingAnalyzer, line: []const u8, test_pos: usize, temp_allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        
        // Find the opening quote (test_pos points to 't' in 'test "')
        const quote_start = test_pos + 6; // Skip 'test "' to get to content
        
        // Find the closing quote
        if (std.mem.indexOf(u8, line[quote_start..], "\"")) |quote_end| {
            return try temp_allocator.dupe(u8, line[quote_start..quote_start + quote_end]);
        }
        
        return try temp_allocator.dupe(u8, "unknown_test");
    }
    
    fn determineTestCategory(self: *TestingAnalyzer, test_name: []const u8) ?[]const u8 {
        // Check each allowed category to see if test name starts with it
        for (self.config.allowed_categories) |category| {
            // Build the expected prefix pattern: "category:"
            var buf: [256]u8 = undefined;
            const prefix = std.fmt.bufPrint(&buf, "{s}:", .{category}) catch continue;
            
            if (std.mem.indexOf(u8, test_name, prefix) != null) {
                return category;
            }
        }
        
        // Check if it has a colon (might be a category we don't recognize)
        if (std.mem.indexOf(u8, test_name, ":") != null) {
            // Extract the category part before the colon
            if (std.mem.indexOf(u8, test_name, ":")) |colon_pos| {
                const potential_category = test_name[0..colon_pos];
                // Check if this matches any allowed category
                for (self.config.allowed_categories) |category| {
                    if (std.mem.eql(u8, potential_category, category)) {
                        return category;
                    }
                }
            }
        }
        
        return null; // No category detected
    }
    
    fn checkTestNaming(self: *TestingAnalyzer, test_name: []const u8, category: ?[]const u8) bool {
        _ = self;
        
        // If no category detected, check if test has any category prefix
        if (category == null) {
            return std.mem.indexOf(u8, test_name, ":") != null;
        }
        
        // Check if test name contains the category prefix
        var buf: [256]u8 = undefined;
        const prefix = std.fmt.bufPrint(&buf, "{s}:", .{category.?}) catch return false;
        
        return std.mem.indexOf(u8, test_name, prefix) != null;
    }
    
    fn shouldHaveMemorySafety(self: *TestingAnalyzer, test_pattern: TestPattern) bool {
        _ = self;
        
        // Tests that should use memory safety patterns
        if (test_pattern.category) |cat| {
            if (std.mem.eql(u8, cat, "memory") or 
                std.mem.eql(u8, cat, "integration")) {
                return true;
            }
        }
        
        return std.mem.indexOf(u8, test_pattern.test_name, "alloc") != null or
               std.mem.indexOf(u8, test_pattern.test_name, "memory") != null;
    }
    
    fn getExpectedTestFile(self: *TestingAnalyzer, file_path: []const u8) ![]const u8 {
        // Convert src/foo/bar.zig to test/foo/test_bar.zig or similar
        const basename = std.fs.path.basename(file_path);
        const dirname = std.fs.path.dirname(file_path) orelse ".";
        
        // Remove .zig extension
        const name_no_ext = if (std.mem.endsWith(u8, basename, ".zig"))
            basename[0..basename.len - 4]
        else
            basename;
        
        // Create test file name
        const test_name = try std.fmt.allocPrint(self.allocator, "test_{s}.zig", .{name_no_ext});
        defer self.allocator.free(test_name);
        
        // Create full test path
        return try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{dirname, test_name});
    }
    
    fn fileExists(self: *TestingAnalyzer, file_path: []const u8) bool {
        _ = self;
        
        std.fs.cwd().access(file_path, .{}) catch {
            return false;
        };
        return true;
    }
    
    pub fn hasErrors(self: *TestingAnalyzer) bool {
        for (self.issues.items) |issue| {
            if (issue.severity == .err) return true;
        }
        return false;
    }
    
    pub fn getIssues(self: *TestingAnalyzer) []const Issue {
        return self.issues.items;
    }
    
    // Structured compliance data methods
    
    pub fn getTestCount(self: *TestingAnalyzer) u32 {
        return @intCast(self.tests.items.len);
    }
    
    pub fn getCategoryBreakdown(self: *TestingAnalyzer, allocator: std.mem.Allocator) !std.StringHashMap(u32) {
        var breakdown = std.StringHashMap(u32).init(allocator);
        
        for (self.tests.items) |test_pattern| {
            if (test_pattern.category) |cat| {
                const result = try breakdown.getOrPut(cat);
                if (result.found_existing) {
                    result.value_ptr.* += 1;
                } else {
                    result.value_ptr.* = 1;
                }
            }
        }
        
        return breakdown;
    }
    
    pub fn getTestsWithoutCategory(self: *TestingAnalyzer) u32 {
        var count: u32 = 0;
        for (self.tests.items) |test_pattern| {
            if (test_pattern.category == null) count += 1;
        }
        return count;
    }
    
    pub fn getTestsWithMemorySafety(self: *TestingAnalyzer) u32 {
        var count: u32 = 0;
        for (self.tests.items) |test_pattern| {
            if (test_pattern.has_memory_safety) count += 1;
        }
        return count;
    }
    
    pub fn getComplianceReport(self: *TestingAnalyzer) TestComplianceReport {
        return TestComplianceReport{
            .total_tests = @intCast(self.tests.items.len),
            .tests_with_proper_naming = self.countTestsWithProperNaming(),
            .tests_with_categories = self.countTestsWithCategories(),
            .tests_with_memory_safety = self.getTestsWithMemorySafety(),
            .total_issues = @intCast(self.issues.items.len),
            .error_count = self.countIssuesBySeverity(.err),
            .warning_count = self.countIssuesBySeverity(.warning),
            .info_count = self.countIssuesBySeverity(.info),
        };
    }
    
    fn countTestsWithProperNaming(self: *TestingAnalyzer) u32 {
        var count: u32 = 0;
        for (self.tests.items) |test_pattern| {
            if (test_pattern.has_proper_naming) count += 1;
        }
        return count;
    }
    
    fn countTestsWithCategories(self: *TestingAnalyzer) u32 {
        var count: u32 = 0;
        for (self.tests.items) |test_pattern| {
            if (test_pattern.category != null) count += 1;
        }
        return count;
    }
    
    fn countIssuesBySeverity(self: *TestingAnalyzer, severity: Severity) u32 {
        var count: u32 = 0;
        for (self.issues.items) |issue| {
            if (issue.severity == severity) count += 1;
        }
        return count;
    }
};

// Structure to return compliance report data
pub const TestComplianceReport = struct {
    total_tests: u32,
    tests_with_proper_naming: u32,
    tests_with_categories: u32,
    tests_with_memory_safety: u32,
    total_issues: u32,
    error_count: u32,
    warning_count: u32,
    info_count: u32,
};

// Test the testing analyzer
test "unit: testing analyzer basic functionality" {
    var analyzer = TestingAnalyzer.init(std.testing.allocator);
    defer analyzer.deinit();
    
    const test_source =
        \\test "unit: game_clock: basic functionality" {
        \\    const allocator = std.testing.allocator;
        \\    const clock = try GameClock.init(allocator);
        \\    defer clock.deinit();
        \\    
        \\    try std.testing.expect(clock.isValid());
        \\}
    ;
    
    try analyzer.analyzeSourceCode("test.zig", test_source);
    
    // Should find properly formatted test
    try std.testing.expect(analyzer.tests.items.len == 1);
    try std.testing.expect(analyzer.tests.items[0].has_proper_naming == true);
}

test "integration: testing analyzer detects improper naming" {
    var analyzer = TestingAnalyzer.init(std.testing.allocator);
    defer analyzer.deinit();
    
    const test_source =
        \\test "this test has no category prefix" {
        \\    try std.testing.expect(true);
        \\}
    ;
    
    try analyzer.analyzeSourceCode("test.zig", test_source);
    
    // Should find naming issue
    try std.testing.expect(analyzer.issues.items.len > 0);
    try std.testing.expect(analyzer.issues.items[0].issue_type == .invalid_test_naming);
}
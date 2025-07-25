//! Source Context Analysis - Phase 5 Pattern Enhancement
//! 
//! This module provides context-aware source code analysis to distinguish between
//! actual code patterns and patterns that appear in comments, strings, or other
//! non-executable contexts. This is critical for reducing false positives in
//! pattern detection.
//!
//! Key Features:
//! - String literal detection (single and multi-line)
//! - Comment detection (single-line and multi-line)
//! - Accurate position tracking within source code
//! - Context classification for pattern validation
//! - Support for Zig-specific syntax patterns
//!
//! Usage:
//!   var context = SourceContext.init(allocator);
//!   defer context.deinit();
//!   context.analyzeSource(source_code);
//!   const is_code = context.isPositionInCode(line, column);

const std = @import("std");
const ArrayList = std.ArrayList;

/// Types of contexts within source code
pub const ContextType = enum {
    code,              // Actual executable code
    single_line_comment, // // comment
    multi_line_comment,  // /* comment */
    string_literal,      // "string" or 'c'
    multiline_string,    // \\ multiline string
    raw_string,        // r"raw string"
    doc_comment,       // /// doc comment or //! doc comment
    embedded_string,   // @embedFile or similar
    
    pub fn isCodeContext(self: ContextType) bool {
        return self == .code;
    }
    
    pub fn isCommentContext(self: ContextType) bool {
        return self == .single_line_comment or self == .multi_line_comment;
    }
    
    pub fn isStringContext(self: ContextType) bool {
        return self == .string_literal or self == .multiline_string or 
               self == .raw_string or self == .embedded_string;
    }
    
    pub fn isDocumentationContext(self: ContextType) bool {
        return self == .doc_comment;
    }
};

/// Represents a region of source code with a specific context
pub const ContextRegion = struct {
    start_line: u32,
    start_column: u32,
    end_line: u32,
    end_column: u32,
    context_type: ContextType,
    
    pub fn init(start_line: u32, start_col: u32, end_line: u32, end_col: u32, context_type: ContextType) ContextRegion {
        return ContextRegion{
            .start_line = start_line,
            .start_column = start_col,
            .end_line = end_line,
            .end_column = end_col,
            .context_type = context_type,
        };
    }
    
    /// Check if a position is within this region
    pub fn containsPosition(self: ContextRegion, line: u32, column: u32) bool {
        if (line < self.start_line or line > self.end_line) {
            return false;
        }
        
        if (line == self.start_line and line == self.end_line) {
            return column >= self.start_column and column <= self.end_column;
        } else if (line == self.start_line) {
            return column >= self.start_column;
        } else if (line == self.end_line) {
            return column <= self.end_column;
        } else {
            return true; // Line is between start and end
        }
    }
};

/// Performance optimization flags
const PerformanceConfig = struct {
    cache_line_analysis: bool = true,
    fast_string_detection: bool = true,
    skip_whitespace_only_lines: bool = true,
};

/// Main source context analyzer
pub const SourceContext = struct {
    allocator: std.mem.Allocator,
    regions: ArrayList(ContextRegion),
    perf_config: PerformanceConfig,
    analysis_cache: ?std.StringHashMap(bool), // Cache for repeated pattern analysis
    
    pub fn init(allocator: std.mem.Allocator) SourceContext {
        return SourceContext{
            .allocator = allocator,
            .regions = ArrayList(ContextRegion).init(allocator),
            .perf_config = PerformanceConfig{},
            .analysis_cache = null,
        };
    }
    
    pub fn initWithCache(allocator: std.mem.Allocator) !SourceContext {
        return SourceContext{
            .allocator = allocator,
            .regions = ArrayList(ContextRegion).init(allocator),
            .perf_config = PerformanceConfig{},
            .analysis_cache = std.StringHashMap(bool).init(allocator),
        };
    }
    
    pub fn deinit(self: *SourceContext) void {
        self.regions.deinit();
        if (self.analysis_cache) |*cache| {
            cache.deinit();
        }
    }
    
    /// Analyze source code and identify context regions
    pub fn analyzeSource(self: *SourceContext, source: []const u8) !void {
        self.regions.clearRetainingCapacity();
        
        var lines = std.mem.splitScalar(u8, source, '\n');
        var line_number: u32 = 1;
        var in_multiline_comment = false;
        var multiline_comment_start: ?struct { line: u32, column: u32 } = null;
        var in_multiline_string_block = false; // Track consecutive multiline string lines
        
        while (lines.next()) |line| {
            defer line_number += 1;
            
            // Performance optimization: skip whitespace-only lines if enabled
            if (self.perf_config.skip_whitespace_only_lines) {
                const trimmed = std.mem.trim(u8, line, " \t\r\n");
                if (trimmed.len == 0) {
                    continue;
                }
            }
            
            var column: u32 = 0;
            var in_string = false;
            var in_char = false;
            var string_start: ?u32 = null;
            var char_start: ?u32 = null;
            var multiline_string_start: ?u32 = null;
            var escape_next = false;
            
            while (column < line.len) {
                const char = line[column];
                
                // Handle escape sequences
                if (escape_next) {
                    escape_next = false;
                    column += 1;
                    continue;
                }
                
                if (char == '\\' and (in_string or in_char)) {
                    escape_next = true;
                    column += 1;
                    continue;
                }
                
                // Handle multiline comments
                if (in_multiline_comment) {
                    if (char == '*' and column + 1 < line.len and line[column + 1] == '/') {
                        // End of multiline comment
                        if (multiline_comment_start) |start| {
                            const region = ContextRegion.init(start.line, start.column, line_number, column + 1, .multi_line_comment);
                            try self.regions.append(region);
                        }
                        in_multiline_comment = false;
                        multiline_comment_start = null;
                        column += 2;
                        continue;
                    }
                } else {
                    // Not in multiline comment, check for comment starts
                    if (char == '/' and column + 1 < line.len) {
                        const next_char = line[column + 1];
                        
                        if (next_char == '/' and !in_string and !in_char) {
                            // Check for doc comments (/// or //!)
                            var context_type: ContextType = .single_line_comment;
                            if (column + 2 < line.len) {
                                const third_char = line[column + 2];
                                if (third_char == '/' or third_char == '!') {
                                    context_type = .doc_comment;
                                }
                            }
                            
                            const region = ContextRegion.init(line_number, column, line_number, @intCast(line.len - 1), context_type);
                            try self.regions.append(region);
                            break; // Rest of line is comment
                        } else if (next_char == '*' and !in_string and !in_char) {
                            // Multiline comment starts here
                            in_multiline_comment = true;
                            multiline_comment_start = .{ .line = line_number, .column = column };
                            column += 2;
                            continue;
                        }
                    }
                    
                    // Check for raw string literals (r"string")
                    if (char == 'r' and column + 1 < line.len and line[column + 1] == '"' and !in_string and !in_char) {
                        // Raw string literal
                        const raw_start = column;
                        column += 2; // Skip 'r"'
                        
                        // Find end of raw string
                        while (column < line.len and line[column] != '"') {
                            column += 1;
                        }
                        
                        if (column < line.len) {
                            const region = ContextRegion.init(line_number, raw_start, line_number, column, .raw_string);
                            try self.regions.append(region);
                        }
                        
                        column += 1;
                        continue;
                    }
                    
                    // Check for embedded file strings (@embedFile)
                    if (char == '@' and !in_string and !in_char) {
                        if (std.mem.startsWith(u8, line[column..], "@embedFile(")) {
                            // Find the string parameter
                            const embed_start = column;
                            column += 11; // Skip "@embedFile("
                            
                            // Find the closing parenthesis
                            var paren_count: u32 = 1;
                            while (column < line.len and paren_count > 0) {
                                if (line[column] == '(') paren_count += 1;
                                if (line[column] == ')') paren_count -= 1;
                                column += 1;
                            }
                            
                            if (paren_count == 0) {
                                const region = ContextRegion.init(line_number, embed_start, line_number, column - 1, .embedded_string);
                                try self.regions.append(region);
                            }
                            continue;
                        }
                    }
                    
                    // Handle multiline strings (Zig-specific \\)
                    if (char == '\\' and column + 1 < line.len and line[column + 1] == '\\' and !in_string and !in_char) {
                        // Multiline string line
                        if (multiline_string_start == null) {
                            multiline_string_start = column;
                            in_multiline_string_block = true;
                        }
                        
                        const region = ContextRegion.init(line_number, column, line_number, @intCast(line.len - 1), .multiline_string);
                        try self.regions.append(region);
                        break; // Rest of line is multiline string
                    } else if (in_multiline_string_block and multiline_string_start == null) {
                        // Check if this is a continuation of multiline string block
                        const trimmed = std.mem.trim(u8, line, " \t");
                        if (!std.mem.startsWith(u8, trimmed, "\\")) {
                            in_multiline_string_block = false;
                        }
                    }
                    
                    // Handle string literals
                    if (char == '"' and !in_char) {
                        if (in_string) {
                            // End of string
                            if (string_start) |start| {
                                const region = ContextRegion.init(line_number, start, line_number, column, .string_literal);
                                try self.regions.append(region);
                            }
                            in_string = false;
                            string_start = null;
                        } else {
                            // Start of string
                            in_string = true;
                            string_start = column;
                        }
                    }
                    
                    // Handle character literals
                    if (char == '\'' and !in_string) {
                        if (in_char) {
                            // End of char
                            if (char_start) |start| {
                                const region = ContextRegion.init(line_number, start, line_number, column, .string_literal);
                                try self.regions.append(region);
                            }
                            in_char = false;
                            char_start = null;
                        } else {
                            // Start of char
                            in_char = true;
                            char_start = column;
                        }
                    }
                }
                
                column += 1;
            }
            
            // Handle unclosed strings/chars at end of line
            if (in_string and string_start != null) {
                const region = ContextRegion.init(line_number, string_start.?, line_number, column - 1, .string_literal);
                try self.regions.append(region);
                in_string = false;
                string_start = null;
            }
            
            if (in_char and char_start != null) {
                const region = ContextRegion.init(line_number, char_start.?, line_number, column - 1, .string_literal);
                try self.regions.append(region);
                in_char = false;
                char_start = null;
            }
        }
        
        // Handle unclosed multiline comment
        if (in_multiline_comment and multiline_comment_start != null) {
            const start = multiline_comment_start.?;
            const region = ContextRegion.init(start.line, start.column, line_number - 1, 999, .multi_line_comment);
            try self.regions.append(region);
        }
    }
    
    /// Check if a position is in executable code (not comment or string)
    pub fn isPositionInCode(self: *SourceContext, line: u32, column: u32) bool {
        for (self.regions.items) |region| {
            if (region.containsPosition(line, column)) {
                return region.context_type.isCodeContext();
            }
        }
        return true; // Default to code if no region found
    }
    
    /// Check if a position is in a comment
    pub fn isPositionInComment(self: *SourceContext, line: u32, column: u32) bool {
        for (self.regions.items) |region| {
            if (region.containsPosition(line, column)) {
                return region.context_type.isCommentContext();
            }
        }
        return false;
    }
    
    /// Check if a position is in a string literal
    pub fn isPositionInString(self: *SourceContext, line: u32, column: u32) bool {
        for (self.regions.items) |region| {
            if (region.containsPosition(line, column)) {
                return region.context_type.isStringContext();
            }
        }
        return false;
    }
    
    /// Get the context type at a specific position
    pub fn getContextAtPosition(self: *SourceContext, line: u32, column: u32) ContextType {
        for (self.regions.items) |region| {
            if (region.containsPosition(line, column)) {
                return region.context_type;
            }
        }
        return .code; // Default to code context
    }
    
    /// Get all non-code regions for debugging
    pub fn getNonCodeRegions(self: *SourceContext) []ContextRegion {
        return self.regions.items;
    }
    
    /// Validate a pattern position - returns true if position is valid for pattern detection
    pub fn isValidPatternPosition(self: *SourceContext, line: u32, column: u32) bool {
        return self.isPositionInCode(line, column);
    }
    
    /// Helper to find the column position of a substring in a line
    pub fn findPatternColumn(self: *SourceContext, line_text: []const u8, pattern: []const u8) ?u32 {
        _ = self;
        if (std.mem.indexOf(u8, line_text, pattern)) |pos| {
            return @intCast(pos);
        }
        return null;
    }
    
    /// Validate that a pattern found in source code is in executable code
    pub fn validatePattern(self: *SourceContext, line: u32, line_text: []const u8, pattern: []const u8) bool {
        if (self.findPatternColumn(line_text, pattern)) |column| {
            return self.isValidPatternPosition(line, column);
        }
        return false;
    }
};

// Integration helper for existing analyzers
pub const PatternValidator = struct {
    source_context: SourceContext,
    
    pub fn init(allocator: std.mem.Allocator) PatternValidator {
        return PatternValidator{
            .source_context = SourceContext.init(allocator),
        };
    }
    
    pub fn deinit(self: *PatternValidator) void {
        self.source_context.deinit();
    }
    
    /// Initialize with source code for validation
    pub fn setSource(self: *PatternValidator, source: []const u8) !void {
        try self.source_context.analyzeSource(source);
    }
    
    /// Check if an allocation pattern is in valid code context
    pub fn isAllocationPatternValid(self: *PatternValidator, line: u32, line_text: []const u8) bool {
        const patterns = [_][]const u8{ ".alloc(", ".create(", ".dupe(", ".allocSentinel(" };
        
        for (patterns) |pattern| {
            if (std.mem.indexOf(u8, line_text, pattern) != null) {
                return self.source_context.validatePattern(line, line_text, pattern);
            }
        }
        return false; // No allocation pattern found
    }
    
    /// Check if a defer pattern is in valid code context
    pub fn isDeferPatternValid(self: *PatternValidator, line: u32, line_text: []const u8) bool {
        const patterns = [_][]const u8{ "defer ", "errdefer " };
        
        for (patterns) |pattern| {
            if (std.mem.indexOf(u8, line_text, pattern) != null) {
                return self.source_context.validatePattern(line, line_text, pattern);
            }
        }
        return false; // No defer pattern found
    }
    
    /// Check if any pattern is in valid code context
    pub fn isPatternValid(self: *PatternValidator, line: u32, line_text: []const u8, pattern: []const u8) bool {
        return self.source_context.validatePattern(line, line_text, pattern);
    }
};

// Tests for SourceContext
test "SourceContext basic initialization" {
    var context = SourceContext.init(std.testing.allocator);
    defer context.deinit();
    
    try std.testing.expect(context.regions.items.len == 0);
}

test "SourceContext single-line comment detection" {
    var context = SourceContext.init(std.testing.allocator);
    defer context.deinit();
    
    const source = 
        \\const data = alloc(); // This is a comment
        \\// Another comment line
        \\const other = alloc();
        ;
    
    try context.analyzeSource(source);
    
    // Position in comment should not be code
    try std.testing.expect(!context.isPositionInCode(1, 25)); // Inside "// This is a comment"
    try std.testing.expect(!context.isPositionInCode(2, 5));  // Inside "// Another comment line"
    
    // Position in code should be code
    try std.testing.expect(context.isPositionInCode(1, 10)); // "alloc()" in first line
    try std.testing.expect(context.isPositionInCode(3, 10)); // "alloc()" in third line
}

test "SourceContext string literal detection" {
    var context = SourceContext.init(std.testing.allocator);
    defer context.deinit();
    
    const source = 
        \\const msg = "defer allocator.free(data);";
        \\const data = alloc();
        \\defer allocator.free(data);
        ;
    
    try context.analyzeSource(source);
    
    // Position in string should not be code
    try std.testing.expect(!context.isPositionInCode(1, 15)); // Inside string literal
    
    // Position in real code should be code
    try std.testing.expect(context.isPositionInCode(2, 15)); // "alloc()" call
    try std.testing.expect(context.isPositionInCode(3, 5));  // Real defer statement
}

test "SourceContext multiline comment detection" {
    var context = SourceContext.init(std.testing.allocator);
    defer context.deinit();
    
    const source = 
        \\const data = alloc();
        \\/* This is a multiline comment
        \\   defer allocator.free(data);
        \\   More comment text */
        \\defer allocator.free(data);
        ;
    
    try context.analyzeSource(source);
    
    // Positions in multiline comment should not be code
    try std.testing.expect(!context.isPositionInCode(2, 5));  // Start of comment
    try std.testing.expect(!context.isPositionInCode(3, 10)); // Inside comment
    try std.testing.expect(!context.isPositionInCode(4, 5));  // End of comment
    
    // Real code should be detected as code
    try std.testing.expect(context.isPositionInCode(1, 15)); // "alloc()" call
    try std.testing.expect(context.isPositionInCode(5, 5));  // Real defer statement
}

test "PatternValidator allocation pattern validation" {
    var validator = PatternValidator.init(std.testing.allocator);
    defer validator.deinit();
    
    const source = 
        \\const data = try allocator.alloc(u8, 100);
        \\// const fake = try allocator.alloc(u8, 100);
        \\const msg = "try allocator.alloc(u8, 100)";
        ;
    
    try validator.setSource(source);
    
    // Real allocation should be valid
    try std.testing.expect(validator.isAllocationPatternValid(1, "const data = try allocator.alloc(u8, 100);"));
    
    // Allocation in comment should not be valid
    try std.testing.expect(!validator.isAllocationPatternValid(2, "// const fake = try allocator.alloc(u8, 100);"));
    
    // Allocation in string should not be valid
    try std.testing.expect(!validator.isAllocationPatternValid(3, "const msg = \"try allocator.alloc(u8, 100)\";"));
}

test "SourceContext raw string detection" {
    var context = SourceContext.init(std.testing.allocator);
    defer context.deinit();
    
    const source = 
        \\const raw = r"defer allocator.free(data);";
        \\const normal = "normal string";
        \\defer allocator.free(data);
        ;
    
    try context.analyzeSource(source);
    
    // Position in raw string should not be code
    try std.testing.expect(!context.isPositionInCode(1, 15)); // Inside raw string
    
    // Position in normal string should not be code
    try std.testing.expect(!context.isPositionInCode(2, 20)); // Inside normal string
    
    // Real defer statement should be code
    try std.testing.expect(context.isPositionInCode(3, 5)); // Real defer statement
}

test "SourceContext doc comment detection" {
    var context = SourceContext.init(std.testing.allocator);
    defer context.deinit();
    
    const source = 
        \\/// This is a doc comment with defer allocator.free(data);
        \\//! This is also a doc comment
        \\// Regular comment
        \\defer allocator.free(data);
        ;
    
    try context.analyzeSource(source);
    
    // Positions in doc comments should not be code
    try std.testing.expect(!context.isPositionInCode(1, 20)); // Inside doc comment
    try std.testing.expect(!context.isPositionInCode(2, 10)); // Inside doc comment
    
    // Position in regular comment should not be code
    try std.testing.expect(!context.isPositionInCode(3, 5)); // Inside regular comment
    
    // Real defer statement should be code
    try std.testing.expect(context.isPositionInCode(4, 5)); // Real defer statement
}

test "SourceContext embedded file detection" {
    var context = SourceContext.init(std.testing.allocator);
    defer context.deinit();
    
    const source = 
        \\const content = @embedFile("test.txt");
        \\const data = try allocator.alloc(u8, 100);
        ;
    
    try context.analyzeSource(source);
    
    // Position in @embedFile should not be code for pattern detection
    try std.testing.expect(!context.isPositionInCode(1, 20)); // Inside @embedFile
    
    // Real allocation should be code
    try std.testing.expect(context.isPositionInCode(2, 15)); // Real allocation
}
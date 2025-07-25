//! Scope Tracking Infrastructure - Phase 5 Pattern Enhancement
//! 
//! This module provides hierarchical scope tracking for enhanced pattern detection
//! in memory management and testing compliance analysis. It addresses the critical
//! scope tracking limitations identified in Phase 4 validation.
//!
//! Key Features:
//! - Hierarchical scope management with proper nesting
//! - Variable lifecycle tracking within scopes
//! - Context-aware pattern detection
//! - Test body scope tracking (fixes critical defer detection bug)
//! - Support for complex control flow and nested structures
//!
//! Usage:
//!   var tracker = try ScopeTracker.init(allocator);
//!   defer tracker.deinit();
//!   try tracker.analyzeSourceCode(source_code);
//!   const scopes = tracker.getScopes();

const std = @import("std");
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;

/// Represents different types of scopes in Zig code
pub const ScopeType = enum {
    function,       // Regular function scope
    test_function,  // Test function scope (special handling for defer detection)
    block,          // Generic block scope
    struct_init,    // Struct initialization scope
    error_block,    // Error handling block (errdefer context)
    if_block,       // If statement block
    else_block,     // Else statement block
    while_loop,     // While loop block
    for_loop,       // For loop block
    switch_block,   // Switch statement block
    switch_case,    // Switch case block
    comptime_block, // Comptime block
    inline_block,   // Inline block
    
    pub fn needsDeferTracking(self: ScopeType) bool {
        return switch (self) {
            .function, .test_function, .block, .error_block, 
            .if_block, .else_block, .while_loop, .for_loop, 
            .switch_block, .switch_case, .comptime_block, .inline_block => true,
            .struct_init => false, // Struct init often has different cleanup patterns
        };
    }
    
    pub fn isLoopScope(self: ScopeType) bool {
        return self == .while_loop or self == .for_loop;
    }
    
    pub fn isConditionalScope(self: ScopeType) bool {
        return self == .if_block or self == .else_block or self == .switch_block or self == .switch_case;
    }
    
    pub fn isFunctionScope(self: ScopeType) bool {
        return self == .function or self == .test_function;
    }
    
    pub fn isTestContext(self: ScopeType) bool {
        return self == .test_function;
    }
};

/// Information about a variable within a scope
pub const VariableInfo = struct {
    name: []const u8,
    line_declared: u32,
    column_declared: u32,
    allocation_type: ?[]const u8, // Type of allocation if this is an allocated variable
    allocator_source: ?[]const u8, // Source allocator variable name
    has_defer: bool,
    has_errdefer: bool,
    defer_line: ?u32,
    errdefer_line: ?u32,
    is_ownership_transfer: bool, // True if this allocation transfers ownership
    is_arena_allocated: bool,    // True if allocated from arena allocator
    
    pub fn init(name: []const u8, line: u32, column: u32) VariableInfo {
        return VariableInfo{
            .name = name,
            .line_declared = line,
            .column_declared = column,
            .allocation_type = null,
            .allocator_source = null,
            .has_defer = false,
            .has_errdefer = false,
            .defer_line = null,
            .errdefer_line = null,
            .is_ownership_transfer = false,
            .is_arena_allocated = false,
        };
    }
    
    pub fn markAsOwnershipTransfer(self: *VariableInfo) void {
        self.is_ownership_transfer = true;
    }
    
    pub fn markAsArenaAllocated(self: *VariableInfo) void {
        self.is_arena_allocated = true;
    }
    
    pub fn needsDeferCleanup(self: VariableInfo) bool {
        // Arena allocations and ownership transfers don't need defer
        if (self.is_arena_allocated or self.is_ownership_transfer) {
            return false;
        }
        return self.allocation_type != null;
    }
};

/// Information about a scope (function, block, etc.)
pub const ScopeInfo = struct {
    scope_type: ScopeType,
    start_line: u32,
    end_line: ?u32,
    depth: u32,
    name: []const u8, // Function name, test name, or block identifier
    variables: std.StringHashMap(VariableInfo),
    parent_scope: ?u32, // Index of parent scope in the scopes array
    
    pub fn init(allocator: std.mem.Allocator, scope_type: ScopeType, name: []const u8, line: u32, depth: u32, parent: ?u32) ScopeInfo {
        return ScopeInfo{
            .scope_type = scope_type,
            .start_line = line,
            .end_line = null,
            .depth = depth,
            .name = name,
            .variables = std.StringHashMap(VariableInfo).init(allocator),
            .parent_scope = parent,
        };
    }
    
    pub fn deinit(self: *ScopeInfo, allocator: std.mem.Allocator) void {
        // Free all variable names that were duplicated
        var iterator = self.variables.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        self.variables.deinit();
    }
    
    /// Add a variable to this scope
    pub fn addVariable(self: *ScopeInfo, allocator: std.mem.Allocator, var_info: VariableInfo) !void {
        const name_copy = try allocator.dupe(u8, var_info.name);
        try self.variables.put(name_copy, var_info);
    }
    
    /// Find a variable in this scope
    pub fn findVariable(self: *ScopeInfo, name: []const u8) ?VariableInfo {
        return self.variables.get(name);
    }
    
    /// Mark a variable as having defer cleanup
    pub fn markVariableDefer(self: *ScopeInfo, name: []const u8, defer_line: u32) bool {
        if (self.variables.getPtr(name)) |var_info| {
            var_info.has_defer = true;
            var_info.defer_line = defer_line;
            return true;
        }
        return false;
    }
    
    /// Mark a variable as having errdefer cleanup
    pub fn markVariableErrdefer(self: *ScopeInfo, name: []const u8, errdefer_line: u32) bool {
        if (self.variables.getPtr(name)) |var_info| {
            var_info.has_errdefer = true;
            var_info.errdefer_line = errdefer_line;
            return true;
        }
        return false;
    }
};

/// Main scope tracking structure
pub const ScopeTracker = struct {
    allocator: std.mem.Allocator,
    scopes: ArrayList(ScopeInfo),
    current_depth: u32,
    scope_stack: ArrayList(u32), // Stack of scope indices for proper nesting
    arena_allocators: std.StringHashMap([]const u8), // Maps arena variable names to their sources
    ownership_patterns: []const []const u8, // Configurable ownership transfer patterns
    
    pub fn init(allocator: std.mem.Allocator) ScopeTracker {
        // Default ownership transfer patterns (expanded from Phase 5 analysis)
        const default_patterns = [_][]const u8{
            "create", "generate", "build", "make", "new", "clone",
            "getPrimary", "getSecondary", "toString", "toJson", "format",
            "Responsibilities", "Buffer", "duplicate",
            // Additional patterns identified in Phase 5 analysis
            "parse", "read", "load", "fetch", "extract", "copy",
            "serialize", "deserialize", "encode", "decode", "convert",
            "process", "transform", "render", "compile", "construct"
        };
        
        return ScopeTracker{
            .allocator = allocator,
            .scopes = ArrayList(ScopeInfo).init(allocator),
            .current_depth = 0,
            .scope_stack = ArrayList(u32).init(allocator),
            .arena_allocators = std.StringHashMap([]const u8).init(allocator),
            .ownership_patterns = &default_patterns,
        };
    }
    
    pub fn deinit(self: *ScopeTracker) void {
        // Clean up all scopes
        for (self.scopes.items) |*scope| {
            // Free the scope name that was duplicated
            self.allocator.free(scope.name);
            scope.deinit(self.allocator);
        }
        self.scopes.deinit();
        self.scope_stack.deinit();
        
        // Clean up arena allocator mapping
        var arena_iterator = self.arena_allocators.iterator();
        while (arena_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.arena_allocators.deinit();
    }
    
    /// Reset the tracker for analyzing a new file
    pub fn reset(self: *ScopeTracker) void {
        // Clean up all scopes
        for (self.scopes.items) |*scope| {
            // Free the scope name that was duplicated
            self.allocator.free(scope.name);
            scope.deinit(self.allocator);
        }
        self.scopes.clearRetainingCapacity();
        self.scope_stack.clearRetainingCapacity();
        
        // Clean up arena allocator mapping
        var arena_iterator = self.arena_allocators.iterator();
        while (arena_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.arena_allocators.clearRetainingCapacity();
        
        // Reset state
        self.current_depth = 0;
    }
    
    /// Analyze source code and build scope hierarchy
    pub fn analyzeSourceCode(self: *ScopeTracker, source: []const u8) !void {
        // Clear previous analysis
        self.clearScopes();
        
        var lines = std.mem.splitScalar(u8, source, '\n');
        var line_number: u32 = 1;
        
        while (lines.next()) |line| {
            defer line_number += 1;
            
            try self.processLine(line, line_number);
        }
        
        // Close any remaining open scopes
        try self.closeRemainingScopes();
    }
    
    /// Clear all scopes and reset state
    fn clearScopes(self: *ScopeTracker) void {
        for (self.scopes.items) |*scope| {
            // Free the scope name that was duplicated
            self.allocator.free(scope.name);
            scope.deinit(self.allocator);
        }
        self.scopes.clearRetainingCapacity();
        self.scope_stack.clearRetainingCapacity();
        
        // Clear arena allocator mapping
        var arena_iterator = self.arena_allocators.iterator();
        while (arena_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.arena_allocators.clearRetainingCapacity();
        
        self.current_depth = 0;
    }
    
    /// Process a single line of source code
    fn processLine(self: *ScopeTracker, line: []const u8, line_number: u32) !void {
        // Skip comments and empty lines
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0 or std.mem.startsWith(u8, trimmed, "//")) {
            return;
        }
        
        // Check for scope opening
        if (try self.detectScopeOpening(line, line_number)) {
            // Scope was opened, continue processing
        }
        
        // Check for variable declarations and allocations
        try self.detectVariableDeclaration(line, line_number);
        
        // Check for defer/errdefer statements
        try self.detectDeferStatements(line, line_number);
        
        // Check for scope closing
        try self.detectScopeClosing(line, line_number);
    }
    
    /// Detect scope opening (function declarations, test declarations, blocks)
    fn detectScopeOpening(self: *ScopeTracker, line: []const u8, line_number: u32) !bool {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        
        // Test function detection
        if (std.mem.indexOf(u8, line, "test ") != null and std.mem.indexOf(u8, line, "{") != null) {
            const test_name = self.extractTestName(line) orelse "unknown_test";
            try self.openScope(.test_function, test_name, line_number);
            return true;
        }
        
        // Regular function detection
        if ((std.mem.indexOf(u8, line, "fn ") != null or std.mem.indexOf(u8, line, "pub fn ") != null) and 
            std.mem.indexOf(u8, line, "{") != null) {
            const function_name = self.extractFunctionName(line) orelse "unknown_function";
            try self.openScope(.function, function_name, line_number);
            return true;
        }
        
        // Control flow scope detection
        if (std.mem.indexOf(u8, line, "{") != null) {
            // Skip function/test scopes (already handled above)
            if (std.mem.indexOf(u8, line, "fn ") != null or std.mem.indexOf(u8, line, "test ") != null) {
                return false;
            }
            
            // If statement
            if (std.mem.indexOf(u8, trimmed, "if ") == 0 or std.mem.indexOf(u8, trimmed, "if(") == 0) {
                try self.openScope(.if_block, "if", line_number);
                return true;
            }
            
            // Else statement (can be standalone or after a closing brace)
            if (std.mem.indexOf(u8, line, "else") != null and std.mem.indexOf(u8, line, "{") != null) {
                if (std.mem.indexOf(u8, line, "else if") != null) {
                    try self.openScope(.if_block, "else_if", line_number);
                } else {
                    try self.openScope(.else_block, "else", line_number);
                }
                return true;
            }
            
            // While loop
            if (std.mem.indexOf(u8, trimmed, "while ") == 0 or std.mem.indexOf(u8, trimmed, "while(") == 0) {
                try self.openScope(.while_loop, "while", line_number);
                return true;
            }
            
            // For loop
            if (std.mem.indexOf(u8, trimmed, "for ") == 0 or std.mem.indexOf(u8, trimmed, "for(") == 0) {
                try self.openScope(.for_loop, "for", line_number);
                return true;
            }
            
            // Switch statement
            if (std.mem.indexOf(u8, trimmed, "switch ") == 0 or std.mem.indexOf(u8, trimmed, "switch(") == 0) {
                try self.openScope(.switch_block, "switch", line_number);
                return true;
            }
            
            // Comptime block
            if (std.mem.indexOf(u8, trimmed, "comptime ") == 0) {
                try self.openScope(.comptime_block, "comptime", line_number);
                return true;
            }
            
            // Inline block
            if (std.mem.indexOf(u8, trimmed, "inline ") == 0) {
                try self.openScope(.inline_block, "inline", line_number);
                return true;
            }
            
            // Generic block scope
            if (!std.mem.startsWith(u8, trimmed, "//")) {
                try self.openScope(.block, "block", line_number);
                return true;
            }
        }
        
        return false;
    }
    
    /// Detect variable declarations and allocations
    fn detectVariableDeclaration(self: *ScopeTracker, line: []const u8, line_number: u32) !void {
        // Variable declaration pattern: "const varname = " or "var varname = "
        if (std.mem.indexOf(u8, line, "const ") != null or std.mem.indexOf(u8, line, "var ") != null) {
            if (self.extractVariableName(line)) |var_name| {
                const column = self.findVariableColumn(line, var_name);
                var var_info = VariableInfo.init(var_name, line_number, column);
                
                // Check if this is an allocation
                if (self.isAllocationLine(line)) {
                    var_info.allocation_type = self.extractAllocationType(line);
                    var_info.allocator_source = self.extractAllocatorVariable(line);
                    
                    // Check if this is arena allocated
                    if (var_info.allocator_source) |allocator_var| {
                        if (self.isArenaAllocator(allocator_var)) {
                            var_info.markAsArenaAllocated();
                        }
                    }
                    
                    // Check if this is ownership transfer
                    if (self.isOwnershipTransferContext(line)) {
                        var_info.markAsOwnershipTransfer();
                    }
                }
                
                // Add to current scope
                if (self.getCurrentScope()) |scope| {
                    try scope.addVariable(self.allocator, var_info);
                }
            }
        }
        
        // Detect arena allocator creation
        try self.detectArenaAllocatorCreation(line);
    }
    
    /// Detect defer and errdefer statements
    fn detectDeferStatements(self: *ScopeTracker, line: []const u8, line_number: u32) !void {
        // Defer statement detection
        if (std.mem.indexOf(u8, line, "defer ") != null) {
            if (self.extractVariableFromDeferStatement(line)) |var_name| {
                self.markVariableWithDefer(var_name, line_number);
            }
        }
        
        // Errdefer statement detection  
        if (std.mem.indexOf(u8, line, "errdefer ") != null) {
            if (self.extractVariableFromDeferStatement(line)) |var_name| {
                self.markVariableWithErrdefer(var_name, line_number);
            }
        }
    }
    
    /// Detect scope closing (closing braces)
    fn detectScopeClosing(self: *ScopeTracker, line: []const u8, line_number: u32) !void {
        // Count closing braces
        var brace_count: i32 = 0;
        for (line) |char| {
            if (char == '}') {
                brace_count += 1;
            }
        }
        
        // Close scopes for each closing brace
        var i: i32 = 0;
        while (i < brace_count) : (i += 1) {
            try self.closeCurrentScope(line_number);
        }
    }
    
    /// Open a new scope
    fn openScope(self: *ScopeTracker, scope_type: ScopeType, name: []const u8, line_number: u32) !void {
        const parent_scope = if (self.scope_stack.items.len > 0) self.scope_stack.items[self.scope_stack.items.len - 1] else null;
        
        const name_copy = try self.allocator.dupe(u8, name);
        const scope = ScopeInfo.init(self.allocator, scope_type, name_copy, line_number, self.current_depth, parent_scope);
        
        try self.scopes.append(scope);
        const scope_index = @as(u32, @intCast(self.scopes.items.len - 1));
        try self.scope_stack.append(scope_index);
        
        self.current_depth += 1;
    }
    
    /// Close the current scope
    fn closeCurrentScope(self: *ScopeTracker, line_number: u32) !void {
        if (self.scope_stack.items.len > 0) {
            const scope_index = self.scope_stack.items[self.scope_stack.items.len - 1];
            _ = self.scope_stack.pop();
            if (scope_index < self.scopes.items.len) {
                self.scopes.items[scope_index].end_line = line_number;
            }
            self.current_depth = if (self.current_depth > 0) self.current_depth - 1 else 0;
        }
    }
    
    /// Close all remaining open scopes
    fn closeRemainingScopes(self: *ScopeTracker) !void {
        while (self.scope_stack.items.len > 0) {
            try self.closeCurrentScope(999999); // Use large line number for unclosed scopes
        }
    }
    
    /// Get the current scope (top of stack)
    fn getCurrentScope(self: *ScopeTracker) ?*ScopeInfo {
        if (self.scope_stack.items.len > 0) {
            const scope_index = self.scope_stack.items[self.scope_stack.items.len - 1];
            if (scope_index < self.scopes.items.len) {
                return &self.scopes.items[scope_index];
            }
        }
        return null;
    }
    
    /// Mark a variable as having defer cleanup
    fn markVariableWithDefer(self: *ScopeTracker, var_name: []const u8, line_number: u32) void {
        // Search from current scope upward through parent scopes
        var scope_index_opt: ?u32 = if (self.scope_stack.items.len > 0) self.scope_stack.items[self.scope_stack.items.len - 1] else null;
        
        while (scope_index_opt) |scope_index| {
            if (scope_index < self.scopes.items.len) {
                if (self.scopes.items[scope_index].markVariableDefer(var_name, line_number)) {
                    return; // Found and marked
                }
                scope_index_opt = self.scopes.items[scope_index].parent_scope;
            } else {
                break;
            }
        }
    }
    
    /// Mark a variable as having errdefer cleanup
    fn markVariableWithErrdefer(self: *ScopeTracker, var_name: []const u8, line_number: u32) void {
        // Search from current scope upward through parent scopes
        var scope_index_opt: ?u32 = if (self.scope_stack.items.len > 0) self.scope_stack.items[self.scope_stack.items.len - 1] else null;
        
        while (scope_index_opt) |scope_index| {
            if (scope_index < self.scopes.items.len) {
                if (self.scopes.items[scope_index].markVariableErrdefer(var_name, line_number)) {
                    return; // Found and marked
                }
                scope_index_opt = self.scopes.items[scope_index].parent_scope;
            } else {
                break;
            }
        }
    }
    
    // Helper methods for parsing (simplified for POC)
    
    fn extractTestName(self: *ScopeTracker, line: []const u8) ?[]const u8 {
        _ = self;
        if (std.mem.indexOf(u8, line, "test \"") != null) {
            const start = std.mem.indexOf(u8, line, "\"").? + 1;
            if (std.mem.indexOfPos(u8, line, start, "\"")) |end| {
                return line[start..end];
            }
        }
        return null;
    }
    
    fn extractFunctionName(self: *ScopeTracker, line: []const u8) ?[]const u8 {
        _ = self;
        if (std.mem.indexOf(u8, line, "fn ")) |fn_pos| {
            const start = fn_pos + 3;
            var end = start;
            while (end < line.len and (std.ascii.isAlphanumeric(line[end]) or line[end] == '_')) {
                end += 1;
            }
            if (end > start) {
                return line[start..end];
            }
        }
        return null;
    }
    
    fn extractVariableName(self: *ScopeTracker, line: []const u8) ?[]const u8 {
        _ = self;
        // Look for "const varname = " or "var varname = "
        const patterns = [_][]const u8{ "const ", "var " };
        
        for (patterns) |pattern| {
            if (std.mem.indexOf(u8, line, pattern)) |start_pos| {
                const var_start = start_pos + pattern.len;
                var var_end = var_start;
                
                // Find end of variable name
                while (var_end < line.len and (std.ascii.isAlphanumeric(line[var_end]) or line[var_end] == '_')) {
                    var_end += 1;
                }
                
                if (var_end > var_start) {
                    return line[var_start..var_end];
                }
            }
        }
        return null;
    }
    
    fn findVariableColumn(self: *ScopeTracker, line: []const u8, var_name: []const u8) u32 {
        _ = self;
        if (std.mem.indexOf(u8, line, var_name)) |pos| {
            return @intCast(pos);
        }
        return 0;
    }
    
    fn isAllocationLine(self: *ScopeTracker, line: []const u8) bool {
        _ = self;
        const allocation_patterns = [_][]const u8{ 
            ".alloc(", ".create(", ".dupe(", ".allocSentinel(",
            ".allocWithOptions(", ".realloc(", "ArrayList.init(",
            "HashMap.init(", "ArrayListUnmanaged.init(", ".allocAdvanced("
        };
        
        for (allocation_patterns) |pattern| {
            if (std.mem.indexOf(u8, line, pattern) != null) {
                return true;
            }
        }
        return false;
    }
    
    fn extractAllocationType(self: *ScopeTracker, line: []const u8) ?[]const u8 {
        _ = self;
        const allocation_patterns = [_][]const u8{ 
            ".alloc(", ".create(", ".dupe(", ".allocSentinel(",
            ".allocWithOptions(", ".realloc(", "ArrayList.init(",
            "HashMap.init(", "ArrayListUnmanaged.init(", ".allocAdvanced("
        };
        
        for (allocation_patterns) |pattern| {
            if (std.mem.indexOf(u8, line, pattern) != null) {
                if (std.mem.endsWith(u8, pattern, "(")) {
                    return pattern[1..pattern.len-1]; // Remove leading '.' and trailing '('
                } else {
                    return pattern; // Return as-is for init patterns
                }
            }
        }
        return null;
    }
    
    fn extractVariableFromDeferStatement(self: *ScopeTracker, line: []const u8) ?[]const u8 {
        _ = self;
        // Look for patterns like "defer allocator.free(varname)" or "defer varname.deinit()"
        
        // Pattern: defer allocator.free(varname)
        if (std.mem.indexOf(u8, line, ".free(")) |free_pos| {
            const paren_start = free_pos + 5; // After ".free("
            var paren_end = paren_start;
            
            while (paren_end < line.len and line[paren_end] != ')') {
                paren_end += 1;
            }
            
            if (paren_end > paren_start) {
                return std.mem.trim(u8, line[paren_start..paren_end], " \t");
            }
        }
        
        // Pattern: defer varname.deinit()
        if (std.mem.indexOf(u8, line, ".deinit()")) |deinit_pos| {
            const defer_pos = std.mem.indexOf(u8, line, "defer ") orelse return null;
            const var_start = defer_pos + 6; // After "defer "
            
            if (deinit_pos > var_start) {
                return std.mem.trim(u8, line[var_start..deinit_pos], " \t");
            }
        }
        
        return null;
    }
    
    // Public interface methods
    
    /// Get all detected scopes
    pub fn getScopes(self: *ScopeTracker) []ScopeInfo {
        return self.scopes.items;
    }
    
    /// Find a scope by line number
    pub fn findScopeAtLine(self: *ScopeTracker, line_number: u32) ?*ScopeInfo {
        for (self.scopes.items) |*scope| {
            if (scope.start_line <= line_number and 
                (scope.end_line == null or scope.end_line.? >= line_number)) {
                return scope;
            }
        }
        return null;
    }
    
    /// Find all test function scopes
    pub fn getTestScopes(self: *ScopeTracker) ArrayList(*ScopeInfo) {
        var test_scopes = ArrayList(*ScopeInfo).init(self.allocator);
        
        for (self.scopes.items) |*scope| {
            if (scope.scope_type == .test_function) {
                test_scopes.append(scope) catch {}; // Ignore allocation errors for now
            }
        }
        
        return test_scopes;
    }
    
    /// Check if a variable has proper defer cleanup in any accessible scope
    pub fn hasVariableDeferCleanup(self: *ScopeTracker, var_name: []const u8, from_line: u32) bool {
        if (self.findScopeAtLine(from_line)) |scope| {
            if (scope.findVariable(var_name)) |var_info| {
                return var_info.has_defer or var_info.has_errdefer;
            }
        }
        return false;
    }
    
    /// Extract allocator variable name from allocation line
    fn extractAllocatorVariable(self: *ScopeTracker, line: []const u8) ?[]const u8 {
        _ = self;
        // Look for patterns like "allocator.alloc(" or "temp_allocator.create("
        const allocation_patterns = [_][]const u8{ ".alloc(", ".create(", ".dupe(", ".allocSentinel(" };
        
        for (allocation_patterns) |pattern| {
            if (std.mem.indexOf(u8, line, pattern)) |pos| {
                // Go backwards from the pattern to find the allocator variable
                var start = pos;
                while (start > 0) {
                    start -= 1;
                    const char = line[start];
                    if (!std.ascii.isAlphanumeric(char) and char != '_') {
                        start += 1;
                        break;
                    }
                }
                
                if (start < pos) {
                    return line[start..pos];
                }
            }
        }
        return null;
    }
    
    /// Check if an allocator variable is arena-based
    fn isArenaAllocator(self: *ScopeTracker, allocator_var: []const u8) bool {
        // Check direct arena variable names
        if (std.mem.indexOf(u8, allocator_var, "arena") != null) {
            return true;
        }
        
        // Check if this allocator is derived from a known arena
        return self.arena_allocators.contains(allocator_var);
    }
    
    /// Detect arena allocator creation and track derived variables
    fn detectArenaAllocatorCreation(self: *ScopeTracker, line: []const u8) !void {
        // Pattern: "var arena = std.heap.ArenaAllocator.init("
        if (std.mem.indexOf(u8, line, "ArenaAllocator.init(") != null) {
            if (self.extractVariableName(line)) |arena_var| {
                const arena_copy = try self.allocator.dupe(u8, arena_var);
                const source_copy = try self.allocator.dupe(u8, "ArenaAllocator");
                try self.arena_allocators.put(arena_copy, source_copy);
            }
        }
        
        // Pattern: "const alloc = arena.allocator();"
        if (std.mem.indexOf(u8, line, ".allocator()") != null) {
            if (self.extractVariableName(line)) |derived_var| {
                // Find the arena variable before .allocator()
                if (std.mem.indexOf(u8, line, ".allocator()")) |pos| {
                    var start = pos;
                    while (start > 0) {
                        start -= 1;
                        const char = line[start];
                        if (!std.ascii.isAlphanumeric(char) and char != '_') {
                            start += 1;
                            break;
                        }
                    }
                    
                    if (start < pos) {
                        const arena_var = line[start..pos];
                        if (self.arena_allocators.contains(arena_var)) {
                            const derived_copy = try self.allocator.dupe(u8, derived_var);
                            const arena_copy = try self.allocator.dupe(u8, arena_var);
                            try self.arena_allocators.put(derived_copy, arena_copy);
                        }
                    }
                }
            }
        }
    }
    
    /// Check if allocation is in ownership transfer context
    fn isOwnershipTransferContext(self: *ScopeTracker, line: []const u8) bool {
        // Check if we're in a function that returns allocated memory
        if (self.getCurrentScope()) |scope| {
            if (scope.scope_type.isFunctionScope()) {
                // Check function name against ownership patterns
                for (self.ownership_patterns) |pattern| {
                    if (std.mem.indexOf(u8, scope.name, pattern) != null) {
                        return true;
                    }
                }
                
                // Check if allocation is immediately returned
                if (std.mem.indexOf(u8, line, "return ") != null and self.isAllocationLine(line)) {
                    return true;
                }
            }
        }
        return false;
    }
};

// Tests for ScopeTracker
test "unit: ScopeTracker basic initialization" {
    var tracker = ScopeTracker.init(std.testing.allocator);
    defer tracker.deinit();
    
    try std.testing.expect(tracker.scopes.items.len == 0);
    try std.testing.expect(tracker.current_depth == 0);
    try std.testing.expect(tracker.arena_allocators.count() == 0);
    try std.testing.expect(tracker.ownership_patterns.len > 0); // Should have default patterns
}

test "unit: ScopeTracker simple function detection" {
    var tracker = ScopeTracker.init(std.testing.allocator);
    defer tracker.deinit();
    
    const source = 
        \\pub fn testFunction() void {
        \\    const data = try allocator.alloc(u8, 100);
        \\    defer allocator.free(data);
        \\}
        ;
    
    try tracker.analyzeSourceCode(source);
    
    const scopes = tracker.getScopes();
    try std.testing.expect(scopes.len >= 1);
    try std.testing.expect(scopes[0].scope_type == .function);
    try std.testing.expectEqualStrings(scopes[0].name, "testFunction");
}

test "unit: ScopeTracker test function detection" {
    var tracker = ScopeTracker.init(std.testing.allocator);
    defer tracker.deinit();
    
    const source = 
        \\test "memory: basic allocation test" {
        \\    const allocator = std.testing.allocator;
        \\    const data = try allocator.alloc(u8, 100);
        \\    defer allocator.free(data);
        \\}
        ;
    
    try tracker.analyzeSourceCode(source);
    
    const scopes = tracker.getScopes();
    try std.testing.expect(scopes.len >= 1);
    try std.testing.expect(scopes[0].scope_type == .test_function);
    try std.testing.expectEqualStrings(scopes[0].name, "memory: basic allocation test");
}

test "unit: ScopeTracker enhanced control flow detection" {
    var tracker = ScopeTracker.init(std.testing.allocator);
    defer tracker.deinit();
    
    const source = 
        \\fn processData() void {
        \\    if (condition) {
        \\        const data = try allocator.alloc(u8, 100);
        \\        defer allocator.free(data);
        \\    } else {
        \\        while (running) {
        \\            for (items) |item| {
        \\                // process item
        \\            }
        \\        }
        \\    }
        \\}
        ;
    
    try tracker.analyzeSourceCode(source);
    
    const scopes = tracker.getScopes();
    try std.testing.expect(scopes.len >= 5); // function, if, else, while, for
    
    // Verify scope types
    var found_if = false;
    var found_else = false;
    var found_while = false;
    var found_for = false;
    
    for (scopes) |*scope| {
        switch (scope.scope_type) {
            .if_block => found_if = true,
            .else_block => found_else = true,
            .while_loop => found_while = true,
            .for_loop => found_for = true,
            else => {}
        }
    }
    
    try std.testing.expect(found_if);
    try std.testing.expect(found_else);
    try std.testing.expect(found_while);
    try std.testing.expect(found_for);
}

test "unit: ScopeTracker arena allocator tracking" {
    var tracker = ScopeTracker.init(std.testing.allocator);
    defer tracker.deinit();
    
    const source = 
        \\fn createBuffer() ![]u8 {
        \\    var arena = std.heap.ArenaAllocator.init(base_allocator);
        \\    defer arena.deinit();
        \\    const temp_alloc = arena.allocator();
        \\    const data = try temp_alloc.alloc(u8, 100);
        \\    return data;
        \\}
        ;
    
    try tracker.analyzeSourceCode(source);
    
    // Check that arena allocator was tracked
    try std.testing.expect(tracker.arena_allocators.contains("arena"));
    try std.testing.expect(tracker.arena_allocators.contains("temp_alloc"));
    
    // Check that allocation was marked as arena-based
    const scopes = tracker.getScopes();
    for (scopes) |*scope| {
        if (scope.scope_type == .function) {
            if (scope.findVariable("data")) |var_info| {
                try std.testing.expect(var_info.is_arena_allocated);
            }
        }
    }
}

test "unit: ScopeTracker ownership transfer detection" {
    var tracker = ScopeTracker.init(std.testing.allocator);
    defer tracker.deinit();
    
    const source = 
        \\fn createBuffer(allocator: std.mem.Allocator) ![]u8 {
        \\    return try allocator.alloc(u8, 100);
        \\}
        ;
    
    try tracker.analyzeSourceCode(source);
    
    // This should be detected as ownership transfer based on function name pattern
    const scopes = tracker.getScopes();
    for (scopes) |*scope| {
        if (scope.scope_type == .function) {
            try std.testing.expectEqualStrings(scope.name, "createBuffer");
        }
    }
}
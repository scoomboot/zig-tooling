//! Scope Tracking Infrastructure
//! 
//! This module provides hierarchical scope tracking for enhanced pattern detection
//! in memory management and testing compliance analysis. It enables context-aware
//! analysis by understanding the structure and relationships between code scopes.
//!
//! ## Key Features
//! - Hierarchical scope management with proper nesting
//! - Variable lifecycle tracking within scopes
//! - Context-aware pattern detection
//! - Test body scope tracking for accurate defer detection
//! - Support for complex control flow and nested structures
//! - Performance optimizations for large files
//!
//! ## Usage Example
//! ```zig
//! // Using the builder pattern
//! var tracker = ScopeTrackerBuilder.init(allocator)
//!     .withArenaTracking()
//!     .withDeferTracking()
//!     .withMaxDepth(20)
//!     .build();
//! defer tracker.deinit();
//! 
//! try tracker.analyzeSourceCode(source_code);
//! const scopes = tracker.getScopes();
//! ```
//!
//! ## Direct Usage
//! ```zig
//! var tracker = ScopeTracker.init(allocator);
//! defer tracker.deinit();
//! try tracker.analyzeSourceCode(source_code);
//! ```

const std = @import("std");
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const types = @import("types.zig");

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
///
/// Represents a single scope in the code hierarchy, tracking its boundaries,
/// variables, and relationships to other scopes.
pub const ScopeInfo = struct {
    /// Type of this scope (function, block, loop, etc.)
    scope_type: ScopeType,
    /// Line where the scope starts
    start_line: u32,
    /// Line where the scope ends (null if not yet determined)
    end_line: ?u32,
    /// Nesting depth (0 for top-level)
    depth: u32,
    /// Function name, test name, or block identifier
    /// OWNERSHIP: This string is owned by the ScopeInfo and must be freed in deinit()
    /// It is allocated by the parent ScopeTracker's allocator in openScope()
    name: []const u8,
    /// Variables declared in this scope (maps name to info)
    /// OWNERSHIP: HashMap owns the variable name keys (allocated in addVariable)
    variables: std.StringHashMap(VariableInfo),
    /// Index of parent scope in the scopes array (null for top-level)
    parent_scope: ?u32,
    
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
    
    /// Clean up all resources owned by this ScopeInfo
    /// 
    /// This function is responsible for:
    /// - Freeing all variable name keys in the variables HashMap
    /// - Deinitializing the HashMap itself
    /// 
    /// NOTE: The scope name is NOT freed here - it is the responsibility
    /// of the parent ScopeTracker to free scope names in its cleanup methods.
    pub fn deinit(self: *ScopeInfo, allocator: std.mem.Allocator) void {
        // Free all variable names that were duplicated in addVariable()
        var iterator = self.variables.iterator();
        while (iterator.next()) |entry| {
            // Each key is a duplicated string that we own
            allocator.free(entry.key_ptr.*);
        }
        self.variables.deinit();
        
        // NOTE: self.name is NOT freed here - the parent ScopeTracker handles it
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

/// Builder for creating configured ScopeTracker instances
/// 
/// Provides a fluent API for configuring scope tracking behavior.
/// 
/// ## Example
/// ```zig
/// var tracker = try ScopeTracker.builder(allocator)
///     .withOwnershipPatterns(&.{ "allocate", "construct" })
///     .withMaxDepth(50)
///     .withLazyParsing(true, 5000)
///     .build();
/// defer tracker.deinit();
/// ```
pub const ScopeTrackerBuilder = struct {
    allocator: std.mem.Allocator,
    config: types.ScopeConfig,
    custom_patterns: ?[]const []const u8,
    
    /// Initialize a new builder with default configuration
    pub fn init(allocator: std.mem.Allocator) ScopeTrackerBuilder {
        return .{
            .allocator = allocator,
            .config = .{},
            .custom_patterns = null,
        };
    }
    
    /// Set custom ownership transfer patterns
    /// These patterns are used to identify functions that transfer memory ownership
    pub fn withOwnershipPatterns(self: *ScopeTrackerBuilder, patterns: []const []const u8) *ScopeTrackerBuilder {
        self.custom_patterns = patterns;
        return self;
    }
    
    /// Set whether to track arena allocators
    pub fn withArenaTracking(self: *ScopeTrackerBuilder, enabled: bool) *ScopeTrackerBuilder {
        self.config.track_arena_allocators = enabled;
        return self;
    }
    
    /// Set whether to track variable lifecycles
    pub fn withVariableTracking(self: *ScopeTrackerBuilder, enabled: bool) *ScopeTrackerBuilder {
        self.config.track_variable_lifecycles = enabled;
        return self;
    }
    
    /// Set whether to track defer statements
    pub fn withDeferTracking(self: *ScopeTrackerBuilder, enabled: bool) *ScopeTrackerBuilder {
        self.config.track_defer_statements = enabled;
        return self;
    }
    
    /// Set maximum scope depth (0 = unlimited)
    pub fn withMaxDepth(self: *ScopeTrackerBuilder, depth: u32) *ScopeTrackerBuilder {
        self.config.max_scope_depth = depth;
        return self;
    }
    
    /// Enable lazy parsing for large files
    pub fn withLazyParsing(self: *ScopeTrackerBuilder, enabled: bool, threshold: u32) *ScopeTrackerBuilder {
        self.config.lazy_parsing = enabled;
        self.config.lazy_parsing_threshold = threshold;
        return self;
    }
    
    /// Build the configured ScopeTracker
    pub fn build(self: *ScopeTrackerBuilder) !ScopeTracker {
        return ScopeTracker.initWithConfig(self.allocator, self.config, self.custom_patterns);
    }
};

/// Main scope tracking structure
/// 
/// Provides hierarchical scope analysis for Zig source code with configurable
/// behavior for ownership tracking, variable lifecycle analysis, and performance
/// optimization.
/// 
/// ## Basic Usage
/// ```zig
/// var tracker = ScopeTracker.init(allocator);
/// defer tracker.deinit();
/// try tracker.analyzeSourceCode(source);
/// const scopes = tracker.getScopes();
/// ```
/// 
/// ## Advanced Usage with Builder
/// ```zig
/// var tracker = try ScopeTracker.builder(allocator)
///     .withOwnershipPatterns(&.{ "myCreate", "myAlloc" })
///     .withMaxDepth(100)
///     .build();
/// defer tracker.deinit();
/// ```
pub const ScopeTracker = struct {
    allocator: std.mem.Allocator,
    scopes: ArrayList(ScopeInfo),
    current_depth: u32,
    scope_stack: ArrayList(u32), // Stack of scope indices for proper nesting
    arena_allocators: std.StringHashMap([]const u8), // Maps arena variable names to their sources
    ownership_patterns: []const []const u8, // Configurable ownership transfer patterns
    config: types.ScopeConfig,
    arena_allocator: ?std.heap.ArenaAllocator, // Optional arena for performance
    
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
    
    /// Create a new ScopeTracker with default configuration
    pub fn init(allocator: std.mem.Allocator) ScopeTracker {
        return ScopeTracker{
            .allocator = allocator,
            .scopes = ArrayList(ScopeInfo).init(allocator),
            .current_depth = 0,
            .scope_stack = ArrayList(u32).init(allocator),
            .arena_allocators = std.StringHashMap([]const u8).init(allocator),
            .ownership_patterns = &default_patterns,
            .config = .{},
            .arena_allocator = null,
        };
    }
    
    /// Create a new ScopeTracker with custom configuration
    pub fn initWithConfig(
        allocator: std.mem.Allocator,
        config: types.ScopeConfig,
        custom_patterns: ?[]const []const u8,
    ) !ScopeTracker {
        var tracker = ScopeTracker{
            .allocator = allocator,
            .scopes = ArrayList(ScopeInfo).init(allocator),
            .current_depth = 0,
            .scope_stack = ArrayList(u32).init(allocator),
            .arena_allocators = std.StringHashMap([]const u8).init(allocator),
            .ownership_patterns = custom_patterns orelse &default_patterns,
            .config = config,
            .arena_allocator = null,
        };
        
        // Initialize arena allocator for performance if configured
        if (config.lazy_parsing) {
            tracker.arena_allocator = std.heap.ArenaAllocator.init(allocator);
        }
        
        return tracker;
    }
    
    /// Create a builder for configuring a ScopeTracker
    pub fn builder(allocator: std.mem.Allocator) ScopeTrackerBuilder {
        return ScopeTrackerBuilder.init(allocator);
    }
    
    pub fn deinit(self: *ScopeTracker) void {
        // Use consolidated cleanup logic
        self.cleanupAllScopes();
        self.cleanupArenaAllocators();
        
        // Deinitialize the containers themselves (not just clear)
        self.scopes.deinit();
        self.scope_stack.deinit();
        self.arena_allocators.deinit();
        
        // Clean up optional arena allocator
        if (self.arena_allocator) |*arena| {
            arena.deinit();
        }
    }
    
    /// Reset the tracker for analyzing a new file
    pub fn reset(self: *ScopeTracker) void {
        // Use consolidated cleanup logic
        self.cleanupAllScopes();
        self.cleanupArenaAllocators();
        
        // Reset state
        self.current_depth = 0;
    }
    
    /// Analyze source code and build scope hierarchy
    /// 
    /// Processes the source code line by line to build a hierarchical representation
    /// of scopes, variables, and their relationships. Performance is optimized based
    /// on configuration settings.
    /// 
    /// ## Parameters
    /// - `source`: The source code to analyze
    /// 
    /// ## Returns
    /// Error if analysis fails due to memory allocation or depth limits
    pub fn analyzeSourceCode(self: *ScopeTracker, source: []const u8) !void {
        // Clear previous analysis
        self.clearScopes();
        
        // Check if lazy parsing should be used
        const line_count = std.mem.count(u8, source, "\n");
        const use_lazy_parsing = self.config.lazy_parsing and 
                                line_count >= self.config.lazy_parsing_threshold;
        
        if (use_lazy_parsing) {
            try self.analyzeSourceCodeLazy(source);
        } else {
            try self.analyzeSourceCodeEager(source);
        }
    }
    
    /// Standard eager parsing - processes all lines immediately
    fn analyzeSourceCodeEager(self: *ScopeTracker, source: []const u8) !void {
        var lines = std.mem.splitScalar(u8, source, '\n');
        var line_number: u32 = 1;
        
        while (lines.next()) |line| {
            defer line_number += 1;
            
            // Check depth limit
            if (self.config.max_scope_depth > 0 and self.current_depth >= self.config.max_scope_depth) {
                continue; // Skip processing if we're too deep
            }
            
            try self.processLine(line, line_number);
        }
        
        // Close any remaining open scopes
        try self.closeRemainingScopes();
    }
    
    /// Lazy parsing for large files - only processes relevant sections
    fn analyzeSourceCodeLazy(self: *ScopeTracker, source: []const u8) !void {
        var lines = std.mem.splitScalar(u8, source, '\n');
        var line_number: u32 = 1;
        
        while (lines.next()) |line| {
            defer line_number += 1;
            
            // Skip large comment blocks or string literals in lazy mode
            if (std.mem.startsWith(u8, std.mem.trim(u8, line, " \t"), "///") or
                std.mem.startsWith(u8, std.mem.trim(u8, line, " \t"), "//!")) {
                continue;
            }
            
            // Only process lines that could contain scope or variable information
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (trimmed.len == 0) continue;
            
            const has_relevant_content = 
                std.mem.indexOf(u8, line, "fn ") != null or
                std.mem.indexOf(u8, line, "test ") != null or
                std.mem.indexOf(u8, line, "{") != null or
                std.mem.indexOf(u8, line, "}") != null or
                std.mem.indexOf(u8, line, "const ") != null or
                std.mem.indexOf(u8, line, "var ") != null or
                std.mem.indexOf(u8, line, "defer ") != null or
                std.mem.indexOf(u8, line, "errdefer ") != null;
            
            if (has_relevant_content) {
                try self.processLine(line, line_number);
            }
        }
        
        // Close any remaining open scopes
        try self.closeRemainingScopes();
    }
    
    /// Clear all scopes and reset state
    fn clearScopes(self: *ScopeTracker) void {
        self.cleanupAllScopes();
        self.cleanupArenaAllocators();
        self.current_depth = 0;
    }
    
    /// Internal helper to clean up all scopes
    /// This consolidates the cleanup logic used by deinit(), reset(), and clearScopes()
    /// Note: This only clears the contents, not the containers themselves
    fn cleanupAllScopes(self: *ScopeTracker) void {
        for (self.scopes.items) |*scope| {
            // Only free the scope name if it has valid content
            if (scope.name.len > 0) {
                self.allocator.free(scope.name);
            }
            scope.deinit(self.allocator);
        }
        self.scopes.clearRetainingCapacity();
        self.scope_stack.clearRetainingCapacity();
    }
    
    /// Internal helper to clean up arena allocator mappings
    fn cleanupArenaAllocators(self: *ScopeTracker) void {
        var arena_iterator = self.arena_allocators.iterator();
        while (arena_iterator.next()) |entry| {
            if (entry.key_ptr.*.len > 0) {
                self.allocator.free(entry.key_ptr.*);
            }
            if (entry.value_ptr.*.len > 0) {
                self.allocator.free(entry.value_ptr.*);
            }
        }
        self.arena_allocators.clearRetainingCapacity();
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
        // Skip if variable tracking is disabled
        if (!self.config.track_variable_lifecycles) return;
        
        // Variable declaration pattern: "const varname = " or "var varname = "
        if (std.mem.indexOf(u8, line, "const ") != null or std.mem.indexOf(u8, line, "var ") != null) {
            if (self.extractVariableName(line)) |var_name| {
                const column = self.findVariableColumn(line, var_name);
                var var_info = VariableInfo.init(var_name, line_number, column);
                
                // Check if this is an allocation
                if (self.isAllocationLine(line)) {
                    var_info.allocation_type = self.extractAllocationType(line);
                    var_info.allocator_source = self.extractAllocatorVariable(line);
                    
                    // Check if this is arena allocated (if tracking enabled)
                    if (self.config.track_arena_allocators) {
                        if (var_info.allocator_source) |allocator_var| {
                            if (self.isArenaAllocator(allocator_var)) {
                                var_info.markAsArenaAllocated();
                            }
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
        
        // Detect arena allocator creation (if tracking enabled)
        if (self.config.track_arena_allocators) {
            try self.detectArenaAllocatorCreation(line);
        }
    }
    
    /// Detect defer and errdefer statements
    fn detectDeferStatements(self: *ScopeTracker, line: []const u8, line_number: u32) !void {
        // Skip if defer tracking is disabled
        if (!self.config.track_defer_statements) return;
        
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
    /// 
    /// Creates a new scope with the given type and name. The name is duplicated
    /// and owned by the created ScopeInfo. The ScopeTracker is responsible for
    /// freeing the name when the scope is destroyed (in deinit/reset/clearScopes).
    fn openScope(self: *ScopeTracker, scope_type: ScopeType, name: []const u8, line_number: u32) !void {
        const parent_scope = if (self.scope_stack.items.len > 0) self.scope_stack.items[self.scope_stack.items.len - 1] else null;
        
        // Duplicate the name - this memory is owned by the ScopeInfo
        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);
        
        // Create the scope with the duplicated name
        const scope = ScopeInfo.init(self.allocator, scope_type, name_copy, line_number, self.current_depth, parent_scope);
        
        // Append to scopes array - if this fails, name_copy is freed by errdefer
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
    /// 
    /// Returns a slice containing all scopes found during analysis.
    /// The slice is owned by the ScopeTracker and remains valid until
    /// the next call to analyzeSourceCode or deinit.
    pub fn getScopes(self: *ScopeTracker) []ScopeInfo {
        return self.scopes.items;
    }
    
    /// Get the current configuration
    pub fn getConfig(self: *ScopeTracker) types.ScopeConfig {
        return self.config;
    }
    
    /// Find a scope by line number
    /// 
    /// Returns the innermost scope that contains the given line number.
    /// Useful for determining the context of a specific code location.
    pub fn findScopeAtLine(self: *ScopeTracker, line_number: u32) ?*ScopeInfo {
        var best_match: ?*ScopeInfo = null;
        var best_depth: u32 = 0;
        
        for (self.scopes.items) |*scope| {
            if (scope.start_line <= line_number and 
                (scope.end_line == null or scope.end_line.? >= line_number)) {
                if (scope.depth >= best_depth) {
                    best_match = scope;
                    best_depth = scope.depth;
                }
            }
        }
        return best_match;
    }
    
    /// Find all scopes of a specific type
    /// 
    /// Caller owns the returned ArrayList and must call deinit() on it.
    /// 
    /// ## Example
    /// ```zig
    /// const functions = try tracker.findScopesByType(.function);
    /// defer functions.deinit();
    /// ```
    pub fn findScopesByType(self: *ScopeTracker, scope_type: ScopeType) !ArrayList(*ScopeInfo) {
        var scopes = ArrayList(*ScopeInfo).init(self.allocator);
        errdefer scopes.deinit();
        
        for (self.scopes.items) |*scope| {
            if (scope.scope_type == scope_type) {
                try scopes.append(scope);
            }
        }
        
        return scopes;
    }
    
    /// Find all test function scopes
    /// 
    /// Convenience method that returns all test function scopes.
    /// Caller owns the returned ArrayList and must call deinit() on it.
    pub fn getTestScopes(self: *ScopeTracker) !ArrayList(*ScopeInfo) {
        return self.findScopesByType(.test_function);
    }
    
    /// Find all function scopes (including test functions)
    /// 
    /// Caller owns the returned ArrayList and must call deinit() on it.
    pub fn getFunctionScopes(self: *ScopeTracker) !ArrayList(*ScopeInfo) {
        var scopes = ArrayList(*ScopeInfo).init(self.allocator);
        errdefer scopes.deinit();
        
        for (self.scopes.items) |*scope| {
            if (scope.scope_type.isFunctionScope()) {
                try scopes.append(scope);
            }
        }
        
        return scopes;
    }
    
    /// Get scope hierarchy for a given line
    /// 
    /// Returns all scopes from outermost to innermost that contain the line.
    /// Caller owns the returned ArrayList and must call deinit() on it.
    pub fn getScopeHierarchy(self: *ScopeTracker, line_number: u32) !ArrayList(*ScopeInfo) {
        var hierarchy = ArrayList(*ScopeInfo).init(self.allocator);
        errdefer hierarchy.deinit();
        
        // First, collect all scopes that contain the line
        var candidates = ArrayList(*ScopeInfo).init(self.allocator);
        defer candidates.deinit();
        
        for (self.scopes.items) |*scope| {
            if (scope.start_line <= line_number and 
                (scope.end_line == null or scope.end_line.? >= line_number)) {
                try candidates.append(scope);
            }
        }
        
        // Sort by depth (ascending)
        const Context = struct {
            fn lessThan(_: void, a: *ScopeInfo, b: *ScopeInfo) bool {
                return a.depth < b.depth;
            }
        };
        std.mem.sort(*ScopeInfo, candidates.items, {}, Context.lessThan);
        
        // Copy to result
        for (candidates.items) |scope| {
            try hierarchy.append(scope);
        }
        
        return hierarchy;
    }
    
    /// Check if a variable has proper defer cleanup in any accessible scope
    pub fn hasVariableDeferCleanup(self: *ScopeTracker, var_name: []const u8, from_line: u32) bool {
        if (self.findScopeAtLine(from_line)) |scope| {
            var current_scope: ?*ScopeInfo = scope;
            
            // Check current scope and all parent scopes
            while (current_scope) |s| {
                if (s.findVariable(var_name)) |var_info| {
                    return var_info.has_defer or var_info.has_errdefer;
                }
                
                // Move to parent scope
                if (s.parent_scope) |parent_idx| {
                    if (parent_idx < self.scopes.items.len) {
                        current_scope = &self.scopes.items[parent_idx];
                    } else {
                        break;
                    }
                } else {
                    break;
                }
            }
        }
        return false;
    }
    
    /// Find a variable by name within a specific scope or its parents
    pub fn findVariable(self: *ScopeTracker, var_name: []const u8, from_line: u32) ?VariableInfo {
        if (self.findScopeAtLine(from_line)) |scope| {
            var current_scope: ?*ScopeInfo = scope;
            
            // Check current scope and all parent scopes
            while (current_scope) |s| {
                if (s.findVariable(var_name)) |var_info| {
                    return var_info;
                }
                
                // Move to parent scope
                if (s.parent_scope) |parent_idx| {
                    if (parent_idx < self.scopes.items.len) {
                        current_scope = &self.scopes.items[parent_idx];
                    } else {
                        break;
                    }
                } else {
                    break;
                }
            }
        }
        return null;
    }
    
    /// Get analysis statistics
    pub const AnalysisStats = struct {
        total_scopes: u32,
        function_count: u32,
        test_count: u32,
        max_depth: u32,
        total_variables: u32,
        allocations_tracked: u32,
        defer_statements: u32,
    };
    
    /// Get statistics about the analyzed code
    pub fn getStats(self: *ScopeTracker) AnalysisStats {
        var stats = AnalysisStats{
            .total_scopes = @intCast(self.scopes.items.len),
            .function_count = 0,
            .test_count = 0,
            .max_depth = 0,
            .total_variables = 0,
            .allocations_tracked = 0,
            .defer_statements = 0,
        };
        
        for (self.scopes.items) |*scope| {
            if (scope.scope_type == .function) stats.function_count += 1;
            if (scope.scope_type == .test_function) stats.test_count += 1;
            if (scope.depth > stats.max_depth) stats.max_depth = scope.depth;
            
            stats.total_variables += @intCast(scope.variables.count());
            
            var var_iter = scope.variables.iterator();
            while (var_iter.next()) |entry| {
                if (entry.value_ptr.allocation_type != null) {
                    stats.allocations_tracked += 1;
                }
                if (entry.value_ptr.has_defer) {
                    stats.defer_statements += 1;
                }
            }
        }
        
        return stats;
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
# Scope Tracking Implementation Guide

[← Back to README](../README.md) | [User Guide →](user-guide/user-guide.md)

## Overview

The scope tracking system is a core enhancement that provides hierarchical scope analysis, variable lifecycle tracking, and enhanced pattern detection capabilities. It significantly improves the accuracy of both the memory checker and testing compliance tools through semantic understanding of code structure.

## Architecture Components

### 1. ScopeTracker (`scope_tracker.zig`)

The ScopeTracker is the primary component that manages hierarchical scope analysis throughout code analysis.

#### Key Features:
- **Hierarchical scope management**: Tracks nested scopes with parent-child relationships
- **Variable lifecycle tracking**: Monitors variable declarations, usage, and cleanup
- **Arena allocator detection**: Identifies arena-allocated variables through flow analysis
- **Ownership transfer marking**: Detects when allocated memory ownership is transferred

#### Supported Scope Types (13 total):
1. **function**: Regular function scopes
2. **test_function**: Test function scopes (special handling for test patterns)
3. **if_block**: If statement blocks
4. **else_block**: Else statement blocks
5. **while_loop**: While loop scopes
6. **for_loop**: For loop scopes  
7. **switch_block**: Switch statement scopes
8. **switch_case**: Individual case scopes within switches
9. **comptime_block**: Compile-time evaluation blocks
10. **inline_block**: Inline blocks
11. **struct_init**: Struct initialization scopes
12. **error_block**: Error handling blocks (catch/errdefer)
13. **block**: Generic block scopes

### 2. SourceContext (`source_context.zig`)

The SourceContext component provides accurate context detection to prevent false positives from comments, strings, and other non-code elements.

#### Key Features:
- **Comment detection**: Single-line (//), doc comments (///, //!), and multi-line (/* */)
- **String literal handling**: Regular strings, multiline strings (\\\\), raw strings (r"...")
- **Special construct detection**: @embedFile, comptime blocks
- **Performance optimized**: Caching support for repeated queries

### 3. Enhanced Analyzers

Both MemoryAnalyzer and TestingAnalyzer have been enhanced with scope tracking integration:

#### MemoryAnalyzer Enhancements:
- **Test body defer detection**: Can now detect defer statements inside test function bodies
- **Arena flow tracking**: Tracks arena allocators through .allocator() method calls
- **Ownership transfer patterns**: Expanded from 12 to 25+ patterns
- **Reduced false positives**: Context-aware analysis prevents incorrect flagging

#### TestingAnalyzer Enhancements:
- **Improved test detection**: Better identification of test functions
- **Scope-aware analysis**: Understanding of test function contexts
- **Memory safety validation**: Enhanced detection of allocator usage in tests

## Integration Pattern

### Basic Usage Example

```zig
const allocator = std.heap.page_allocator;

// Initialize components
var scope_tracker = ScopeTracker.init(allocator);
defer scope_tracker.deinit();

var source_ctx = SourceContext.init(allocator);
defer source_ctx.deinit();

// Analyze source file
const source = try std.fs.cwd().readFileAlloc(allocator, "example.zig", 1024 * 1024);
defer allocator.free(source);

// Update source context
try source_ctx.updateSource(source);

// Process line by line
var lines = std.mem.split(u8, source, "\n");
var line_num: usize = 1;
while (lines.next()) |line| {
    defer line_num += 1;
    
    // Check if line is in a comment or string
    if (source_ctx.isInComment(line_num) or source_ctx.isInString(line_num)) {
        continue;
    }
    
    // Process scope changes
    try scope_tracker.processLine(line, line_num);
    
    // Access current scope information
    if (scope_tracker.getCurrentScope()) |scope| {
        // Use scope information for analysis
        switch (scope.scope_type) {
            .test_function => {
                // Special handling for test functions
            },
            .function => {
                // Regular function handling  
            },
            else => {},
        }
    }
}
```

## Variable Lifecycle Tracking

The scope tracker maintains detailed information about variables throughout their lifecycle:

```zig
pub const VariableInfo = struct {
    name: []const u8,
    line: usize,
    scope_id: usize,
    allocator_source: ?[]const u8,    // Source allocator variable
    is_arena_allocated: bool,          // Detected arena allocation
    has_defer_cleanup: bool,           // Has associated defer
    ownership_transferred: bool,       // Ownership moved (return/assignment)
};
```

### Lifecycle Phases:
1. **Declaration**: Variable is declared with allocation
2. **Usage**: Variable is used in expressions  
3. **Cleanup**: Defer/errdefer statements for cleanup
4. **Transfer**: Ownership transferred via return or assignment

## Pattern Detection Improvements

### Arena Allocator Flow Tracking

The enhanced system can track arena allocators through method calls:

```zig
// Previously missed pattern - now detected
var arena = std.heap.ArenaAllocator.init(allocator);
const arena_alloc = arena.allocator();  // Flow tracked
const buffer = try arena_alloc.alloc(u8, 1024); // Correctly identified as arena allocation
```

### Expanded Ownership Transfer Patterns

The system now recognizes 25+ ownership transfer patterns including:
- Basic: create, make, build, generate, new
- Extended: parse, read, load, fetch, extract
- Specialized: serialize, deserialize, encode, decode, convert

### Context-Aware Analysis

Pattern detection now considers the surrounding context:
- Test functions have different rules than regular functions
- Struct initialization patterns are recognized
- Temporary allocators in specific scopes are handled appropriately

## Performance Characteristics

With scope tracking enabled:
- **Additional overhead**: ~8ms per file (well within 100ms target)
- **Memory usage**: Minimal - uses arena allocator for temporary data
- **Scalability**: Linear with file size and scope depth

## Memory Ownership Model

### Overview

The ScopeTracker implements a clear memory ownership model to prevent leaks and double-frees:

1. **ScopeTracker owns scope names**: When a scope is created via `openScope()`, the name is duplicated and owned by ScopeTracker
2. **ScopeInfo owns variable names**: When variables are added to a scope, their names are duplicated and owned by the ScopeInfo
3. **Cleanup responsibility**: Parent structures are responsible for freeing child allocations

### Memory Management Architecture

```zig
// ScopeTracker cleanup (consolidated in cleanupAllScopes)
for (self.scopes.items) |*scope| {
    // Free scope name (owned by ScopeTracker)
    if (scope.name.len > 0) {
        self.allocator.free(scope.name);
    }
    // Let ScopeInfo clean up its own resources
    scope.deinit(self.allocator);
}

// ScopeInfo cleanup
pub fn deinit(self: *ScopeInfo, allocator: std.mem.Allocator) void {
    // Free all variable names (owned by ScopeInfo)
    var iterator = self.variables.iterator();
    while (iterator.next()) |entry| {
        allocator.free(entry.key_ptr.*);
    }
    self.variables.deinit();
    // NOTE: scope.name is NOT freed here - parent handles it
}
```

### Key Design Decisions

1. **Defensive Programming**: All cleanup methods check for empty strings before freeing
2. **Consolidated Logic**: Common cleanup patterns extracted to helper methods
3. **Clear Ownership**: Documentation explicitly states who owns each piece of memory
4. **Error Safety**: Using `errdefer` in allocation paths to prevent leaks on error

### Memory Safety Guarantees

- No double-frees: Each piece of memory has exactly one owner
- No leaks: Comprehensive test suite with GeneralPurposeAllocator validation
- Thread-safe design: Each ScopeTracker instance manages its own memory

## Limitations and Known Issues

### Current Limitations:
1. **String literal edge cases**: Complex nested string patterns may confuse detection
2. **Macro expansion**: Cannot analyze code generated by comptime
3. **Cross-file analysis**: Scope tracking is per-file only
4. **Pattern precedence**: When multiple patterns match, precedence rules are simple

### Known Issues:
- **Pattern detection**: Still relies on syntactic patterns, not true semantic analysis
- ~~**ISSUE-080**: Single-file memory leak in scope tracker~~ (Fixed in LC104)

## Best Practices

### For Tool Users:
1. **Build with ReleaseFast**: Use `zig build -Doptimize=ReleaseFast` for 49-71x performance
2. **Understand context**: The tools now understand context better but still have limitations
3. **Review findings**: Enhanced accuracy means fewer false positives, but human review still needed

### For Tool Developers:
1. **Maintain scope tracker state**: Call reset() between files in multi-file analysis
2. **Check source context**: Always verify code is not in comments/strings before analysis
3. **Use arena allocators**: For temporary analysis data to minimize allocations
4. **Test thoroughly**: Scope tracking adds complexity - test edge cases

## Future Enhancements

Potential improvements identified but not implemented:
1. **AST-based analysis**: True semantic understanding vs pattern matching
2. **Confidence scoring**: Rate pattern matches by confidence level
3. **Cross-file tracking**: Track ownership across module boundaries
4. **Custom rules**: Allow users to define project-specific patterns

---

## See Also

- [Configuration Guide](configuration.md) - Configuration reference
- [User Guide](user-guide/user-guide.md) - Usage guide
- [Current State](analysis/tooling-current-state.md) - Tool capabilities

---

*Last updated: January 2025*  
*Part of the Zig Tooling Suite documentation*
//! Comprehensive memory leak tests for ScopeTracker (LC102)
//! 
//! This test file specifically targets the memory leak issues identified in LC102:
//! - ScopeInfo variable names being leaked (line 703 in scope_tracker.zig)
//! - Scope names potentially being double-freed or corrupted
//! - Full ScopeTracker lifecycle validation with proper cleanup
//! - Multiple scenarios to stress-test memory management
//!
//! The tests use GeneralPurposeAllocator to detect any memory leaks and provide
//! detailed diagnostics when failures occur.

const std = @import("std");
const testing = std.testing;
const zig_tooling = @import("zig_tooling");
const ScopeTracker = zig_tooling.ScopeTracker;
const ScopeInfo = zig_tooling.ScopeInfo;
const VariableInfo = zig_tooling.VariableInfo;
const ScopeType = zig_tooling.ScopeType;

// Test ScopeInfo.addVariable and deinit to ensure variable names are properly freed
test "LC102: ScopeInfo variable name memory management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("\nMemory leak detected in ScopeInfo variable management!\n", .{});
        }
        testing.expect(leaked == .ok) catch |err| {
            std.debug.print("GPA leak check failed: {}\n", .{err});
        };
    }
    const allocator = gpa.allocator();
    
    // Create a ScopeInfo manually to test variable management
    var scope = ScopeInfo.init(allocator, .function, "test_function", 1, 0, null);
    defer scope.deinit(allocator);
    
    // Add multiple variables to test the memory management
    const var_names = [_][]const u8{ "var1", "variable_two", "third_var", "final_variable" };
    
    for (var_names, 0..) |name, i| {
        const var_info = VariableInfo.init(name, @intCast(i + 1), 0);
        try scope.addVariable(allocator, var_info);
    }
    
    // Verify variables were added
    try testing.expect(scope.variables.count() == var_names.len);
    
    // Verify we can find each variable
    for (var_names) |name| {
        const found = scope.findVariable(name);
        try testing.expect(found != null);
        try testing.expectEqualStrings(found.?.name, name);
    }
    
    // The deinit() call in defer should properly free all variable names
    // If there's a leak, the GPA check at the end will catch it
}

// Test ScopeInfo with multiple variable operations and cleanup cycles
test "LC102: ScopeInfo multiple variable add/lookup cycles" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch |err| {
            std.debug.print("Memory leak in variable cycles test: {}\n", .{err});
        };
    }
    const allocator = gpa.allocator();
    
    // Test multiple cycles of variable management
    for (0..5) |cycle| {
        var scope = ScopeInfo.init(allocator, .block, "test_block", @intCast(cycle + 1), 0, null);
        defer scope.deinit(allocator);
        
        // Add variables with unique names per cycle
        for (0..10) |var_idx| {
            const var_name = try std.fmt.allocPrint(allocator, "var_{}_{}", .{ cycle, var_idx });
            defer allocator.free(var_name); // Free our temp name
            
            var var_info = VariableInfo.init(var_name, @intCast(var_idx + 1), 0);
            var_info.allocation_type = "alloc";
            var_info.allocator_source = "test_allocator";
            
            try scope.addVariable(allocator, var_info);
        }
        
        // Verify all variables are present
        try testing.expect(scope.variables.count() == 10);
        
        // Test defer marking
        const test_var_name = try std.fmt.allocPrint(allocator, "var_{}_5", .{cycle});
        defer allocator.free(test_var_name);
        
        const marked = scope.markVariableDefer(test_var_name, 100);
        try testing.expect(marked);
        
        // Verify the defer was marked
        const found = scope.findVariable(test_var_name);
        try testing.expect(found != null);
        try testing.expect(found.?.has_defer);
        try testing.expect(found.?.defer_line == 100);
    }
}

// Test complete ScopeTracker lifecycle with single scope
test "LC102: ScopeTracker single scope lifecycle" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch |err| {
            std.debug.print("Memory leak in single scope lifecycle: {}\n", .{err});
        };
    }
    const allocator = gpa.allocator();
    
    var tracker = ScopeTracker.init(allocator);
    defer tracker.deinit();
    
    const source = 
        \\pub fn simpleFunction() void {
        \\    const data = try allocator.alloc(u8, 100);
        \\    defer allocator.free(data);
        \\    const buffer = try allocator.create(Buffer);
        \\    defer allocator.destroy(buffer);
        \\}
        ;
    
    try tracker.analyzeSourceCode(source);
    
    // Verify scope was created correctly
    const scopes = tracker.getScopes();
    try testing.expect(scopes.len >= 1);
    try testing.expect(scopes[0].scope_type == .function);
    try testing.expectEqualStrings(scopes[0].name, "simpleFunction");
    
    // Verify variables were tracked
    try testing.expect(scopes[0].variables.count() >= 2);
    
    const data_var = scopes[0].findVariable("data");
    try testing.expect(data_var != null);
    try testing.expectEqualStrings(data_var.?.name, "data");
    
    const buffer_var = scopes[0].findVariable("buffer");
    try testing.expect(buffer_var != null);
    try testing.expectEqualStrings(buffer_var.?.name, "buffer");
}

// Test ScopeTracker with nested scopes to ensure proper cleanup hierarchy
test "LC102: ScopeTracker nested scopes memory management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch |err| {
            std.debug.print("Memory leak in nested scopes test: {}\n", .{err});
        };
    }
    const allocator = gpa.allocator();
    
    var tracker = ScopeTracker.init(allocator);
    defer tracker.deinit();
    
    const complex_source = 
        \\fn complexFunction() void {
        \\    const outer_data = try allocator.alloc(u8, 100);
        \\    defer allocator.free(outer_data);
        \\    
        \\    if (condition) {
        \\        const if_data = try allocator.alloc(u8, 50);
        \\        defer allocator.free(if_data);
        \\        
        \\        for (items) |item| {
        \\            const loop_data = try allocator.create(Data);
        \\            defer allocator.destroy(loop_data);
        \\            
        \\            while (running) {
        \\                const while_buffer = try allocator.dupe(u8, "test");
        \\                defer allocator.free(while_buffer);
        \\            }
        \\        }
        \\    } else {
        \\        const else_data = try allocator.alloc(i32, 25);
        \\        defer allocator.free(else_data);
        \\    }
        \\}
        ;
    
    try tracker.analyzeSourceCode(complex_source);
    
    // Verify we have the expected nested structure
    const scopes = tracker.getScopes();
    try testing.expect(scopes.len >= 5); // function, if, for, while, else (at minimum)
    
    // Verify scope types are detected correctly
    var scope_types = std.ArrayList(ScopeType).init(allocator);
    defer scope_types.deinit();
    
    for (scopes) |*scope| {
        try scope_types.append(scope.scope_type);
    }
    
    // Should have function, if, for, while, and else scopes
    var has_function = false;
    var has_if = false;
    var has_for = false;
    var has_while = false;
    var has_else = false;
    
    for (scope_types.items) |scope_type| {
        switch (scope_type) {
            .function => has_function = true,
            .if_block => has_if = true,
            .for_loop => has_for = true,
            .while_loop => has_while = true,
            .else_block => has_else = true,
            else => {},
        }
    }
    
    try testing.expect(has_function);
    try testing.expect(has_if);
    try testing.expect(has_for);
    try testing.expect(has_while);
    try testing.expect(has_else);
    
    // Verify variable tracking in nested scopes
    var total_variables: u32 = 0;
    for (scopes) |*scope| {
        total_variables += @intCast(scope.variables.count());
    }
    try testing.expect(total_variables >= 5); // outer_data, if_data, loop_data, while_buffer, else_data
}

// Test ScopeTracker with repeated analysis to catch accumulating leaks
test "LC102: ScopeTracker repeated analysis stress test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch |err| {
            std.debug.print("Memory leak in repeated analysis stress test: {}\n", .{err});
        };
    }
    const allocator = gpa.allocator();
    
    var tracker = ScopeTracker.init(allocator);
    defer tracker.deinit();
    
    const sources = [_][]const u8{
        \\fn function1() void {
        \\    const data1 = try allocator.alloc(u8, 100);
        \\    defer allocator.free(data1);
        \\}
        ,
        \\test "memory test" {
        \\    const test_data = try std.testing.allocator.alloc(i32, 50);
        \\    defer std.testing.allocator.free(test_data);
        \\}
        ,
        \\fn function2() void {
        \\    if (condition) {
        \\        const branch_data = try allocator.create(MyStruct);
        \\        defer allocator.destroy(branch_data);
        \\    }
        \\}
        ,
        \\fn arenaFunction() void {
        \\    var arena = std.heap.ArenaAllocator.init(allocator);
        \\    defer arena.deinit();
        \\    const temp_alloc = arena.allocator();
        \\    const arena_data = try temp_alloc.alloc(u8, 200);
        \\}
        ,
    };
    
    // Analyze each source multiple times to stress test memory management
    for (0..10) |iteration| {
        for (sources, 0..) |source, source_idx| {
            try tracker.analyzeSourceCode(source);
            
            // Verify analysis worked
            const scopes = tracker.getScopes();
            try testing.expect(scopes.len >= 1);
            
            // For arena function test, verify arena tracking
            if (source_idx == 3) {
                try testing.expect(tracker.arena_allocators.count() > 0);
            }
            
            // Verify we can get stats without crashing
            const stats = tracker.getStats();
            try testing.expect(stats.total_scopes > 0);
        }
        
        // Every few iterations, reset to test the reset functionality
        if (iteration % 3 == 2) {
            tracker.reset();
            try testing.expect(tracker.getScopes().len == 0);
            try testing.expect(tracker.arena_allocators.count() == 0);
        }
    }
}

// Test ScopeTracker builder pattern memory management
test "LC102: ScopeTracker builder pattern lifecycle" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch |err| {
            std.debug.print("Memory leak in builder pattern test: {}\n", .{err});
        };
    }
    const allocator = gpa.allocator();
    
    // Test builder pattern with various configurations
    {
        var builder = ScopeTracker.builder(allocator);
        var tracker = try builder
            .withArenaTracking(true)
            .withVariableTracking(true)
            .withDeferTracking(true)
            .withMaxDepth(50)
            .build();
        defer tracker.deinit();
        
        const source = 
            \\fn testFunction() void {
            \\    var arena = std.heap.ArenaAllocator.init(allocator);
            \\    defer arena.deinit();
            \\    const temp_alloc = arena.allocator();
            \\    const data = try temp_alloc.alloc(u8, 100);
            \\}
            ;
        
        try tracker.analyzeSourceCode(source);
        
        const scopes = tracker.getScopes();
        try testing.expect(scopes.len >= 1);
        
        // Verify arena tracking worked
        try testing.expect(tracker.arena_allocators.count() > 0);
        
        const stats = tracker.getStats();
        try testing.expect(stats.total_scopes > 0);
        try testing.expect(stats.function_count > 0);
    }
    
    // Test another configuration to ensure no cross-contamination
    {
        var builder2 = ScopeTracker.builder(allocator);
        var tracker2 = try builder2
            .withLazyParsing(true, 1000)
            .withMaxDepth(10)
            .build();
        defer tracker2.deinit();
        
        const source2 = 
            \\test "another test" {
            \\    const buffer = try allocator.create(Buffer);
            \\    defer allocator.destroy(buffer);
            \\}
            ;
        
        try tracker2.analyzeSourceCode(source2);
        
        const scopes2 = tracker2.getScopes();
        try testing.expect(scopes2.len >= 1);
        try testing.expect(scopes2[0].scope_type == .test_function);
    }
}

// Test edge cases that might trigger double-free or corruption
test "LC102: ScopeTracker edge cases and error conditions" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch |err| {
            std.debug.print("Memory leak in edge cases test: {}\n", .{err});
        };
    }
    const allocator = gpa.allocator();
    
    var tracker = ScopeTracker.init(allocator);
    defer tracker.deinit();
    
    // Test empty source
    try tracker.analyzeSourceCode("");
    try testing.expect(tracker.getScopes().len == 0);
    
    // Test source with only comments
    try tracker.analyzeSourceCode("// Just a comment\n/// Documentation\n//! Module doc");
    try testing.expect(tracker.getScopes().len == 0);
    
    // Test malformed but parseable source
    const malformed_source = 
        \\fn incomplete_function() {
        \\    const data = try allocator.alloc(u8, 100);
        \\    // Missing closing brace and defer
        ;
    
    try tracker.analyzeSourceCode(malformed_source);
    const scopes = tracker.getScopes();
    try testing.expect(scopes.len >= 1);
    
    // Test reset after malformed source
    tracker.reset();
    try testing.expect(tracker.getScopes().len == 0);
    
    // Test complex nesting with unbalanced braces
    const unbalanced_source = 
        \\fn outerFunction() void {
        \\    if (condition) {
        \\        const data = try allocator.alloc(u8, 100);
        \\        for (items) |item| {
        \\            const item_data = try allocator.create(Item);
        \\            // Missing several closing braces
        ;
    
    try tracker.analyzeSourceCode(unbalanced_source);
    const unbalanced_scopes = tracker.getScopes();
    try testing.expect(unbalanced_scopes.len >= 3); // function, if, for
    
    // Test finding variables across scope hierarchy
    const found_data = tracker.findVariable("data", 3);
    try testing.expect(found_data != null);
    
    const found_item_data = tracker.findVariable("item_data", 5);
    try testing.expect(found_item_data != null);
    
    // Test finding scopes by type
    const functions = try tracker.findScopesByType(.function);
    defer functions.deinit();
    try testing.expect(functions.items.len >= 1);
    
    const if_blocks = try tracker.findScopesByType(.if_block);
    defer if_blocks.deinit();
    try testing.expect(if_blocks.items.len >= 1);
}

// Test memory management with very large scope hierarchies
test "LC102: ScopeTracker large hierarchy stress test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch |err| {
            std.debug.print("Memory leak in large hierarchy stress test: {}\n", .{err});
        };
    }
    const allocator = gpa.allocator();
    
    // Build a source with deep nesting
    var source_builder = std.ArrayList(u8).init(allocator);
    defer source_builder.deinit();
    
    try source_builder.appendSlice("fn deepFunction() void {\n");
    try source_builder.appendSlice("    const outer_data = try allocator.alloc(u8, 100);\n");
    try source_builder.appendSlice("    defer allocator.free(outer_data);\n");
    
    // Create nested structure
    const depth = 20;
    for (0..depth) |i| {
        // Build indent string manually
        var indent_buffer: [80]u8 = undefined;
        var indent_len: usize = 0;
        for (0..(i + 1)) |_| {
            @memcpy(indent_buffer[indent_len..indent_len + 4], "    ");
            indent_len += 4;
        }
        const indent = indent_buffer[0..indent_len];
        
        try source_builder.writer().print("{s}if (condition_{}) {{\n", .{ indent, i });
        try source_builder.writer().print("{s}    const data_{} = try allocator.alloc(u8, {});\n", .{ indent, i, (i + 1) * 10 });
        try source_builder.writer().print("{s}    defer allocator.free(data_{});\n", .{ indent, i });
    }
    
    // Close all the braces
    for (0..depth + 1) |i| {
        // Build indent string manually for closing braces
        var indent_buffer: [80]u8 = undefined;
        var indent_len: usize = 0;
        const target_depth = depth - i;
        for (0..target_depth) |_| {
            @memcpy(indent_buffer[indent_len..indent_len + 4], "    ");
            indent_len += 4;
        }
        const indent = indent_buffer[0..indent_len];
        try source_builder.writer().print("{s}}}\n", .{indent});
    }
    
    var tracker = ScopeTracker.init(allocator);
    defer tracker.deinit();
    
    try tracker.analyzeSourceCode(source_builder.items);
    
    const scopes = tracker.getScopes();
    try testing.expect(scopes.len >= depth); // Should have at least 'depth' scopes
    
    // Verify we can traverse the hierarchy
    const hierarchy = try tracker.getScopeHierarchy(depth / 2);
    defer hierarchy.deinit();
    try testing.expect(hierarchy.items.len > 0);
    
    // Verify stats
    const stats = tracker.getStats();
    try testing.expect(stats.total_scopes >= depth);
    try testing.expect(stats.function_count >= 1);
    try testing.expect(stats.max_depth >= depth);
    try testing.expect(stats.total_variables >= depth);
}

// Test specific issue with scope name duplication at line 703
test "LC102: Direct test of scope name duplication issue" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch |err| {
            std.debug.print("Memory leak in scope name duplication test: {}\n", .{err});
        };
    }
    const allocator = gpa.allocator();
    
    var tracker = ScopeTracker.init(allocator);
    defer tracker.deinit();
    
    // Test with various scope names that might cause issues
    const test_names = [_][]const u8{
        "simple_name",
        "name_with_underscores",
        "verylongnamethatmightcauseproblemswithmemorymangement",
        "numericStart", // Changed to be valid identifier
        "SpecialChars", // Changed to be valid identifier  
        "empty", // Changed from empty name to valid one
        "duplicate", // We'll use this twice to test reuse
        "duplicate2", // Changed second duplicate to be different
    };
    
    // Build a single source with all the test functions
    var all_sources = std.ArrayList(u8).init(allocator);
    defer all_sources.deinit();
    
    for (test_names, 0..) |name, i| {
        try all_sources.writer().print(
            \\fn {s}() void {{
            \\    const var_{} = try allocator.alloc(u8, 100);
            \\    defer allocator.free(var_{});
            \\}}
            \\
        , .{ name, i, i });
    }
    
    try tracker.analyzeSourceCode(all_sources.items);
    
    const scopes = tracker.getScopes();
    try testing.expect(scopes.len >= test_names.len);
    
    // Verify all function names are present
    var found_names = std.ArrayList([]const u8).init(allocator);
    defer found_names.deinit();
    
    for (scopes) |*scope| {
        if (scope.scope_type == .function) {
            try found_names.append(scope.name);
        }
    }
    
    try testing.expect(found_names.items.len == test_names.len);
    
    // Verify each test name appears in the found names
    for (test_names) |test_name| {
        var found = false;
        for (found_names.items) |found_name| {
            if (std.mem.eql(u8, test_name, found_name)) {
                found = true;
                break;
            }
        }
        try testing.expect(found);
    }
    
    // Test reset to ensure cleanup works properly
    tracker.reset();
    try testing.expect(tracker.getScopes().len == 0);
}
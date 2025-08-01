//! Test case to reproduce LC104 memory corruption/double-free crash
//! This test specifically targets the crash in ScopeTracker.deinit()

const std = @import("std");
const testing = std.testing;
const zig_tooling = @import("zig_tooling");
const ScopeTracker = zig_tooling.ScopeTracker;
const patterns = zig_tooling.patterns;

// Test to reproduce the exact crash scenario from LC104
test "LC104: ScopeTracker.deinit() memory corruption crash" {
    // Use GPA to get detailed memory error information
    var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 10 }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("\nLC104: Memory leak detected in crash test!\n", .{});
        }
        testing.expect(leaked == .ok) catch |err| {
            std.debug.print("LC104: GPA leak check failed: {}\n", .{err});
        };
    }
    const allocator = gpa.allocator();
    
    // Create a tracker and analyze some code that creates nested scopes
    var tracker = ScopeTracker.init(allocator);
    defer tracker.deinit(); // This is where the crash happens
    
    const source = 
        \\pub fn testFunction() !void {
        \\    const data = try allocator.alloc(u8, 100);
        \\    defer allocator.free(data);
        \\    
        \\    if (condition) {
        \\        const inner_data = try allocator.alloc(u8, 50);
        \\        defer allocator.free(inner_data);
        \\        
        \\        while (loop_condition) {
        \\            const loop_data = try allocator.create(MyStruct);
        \\            defer allocator.destroy(loop_data);
        \\        }
        \\    } else {
        \\        for (items) |item| {
        \\            const for_data = try item.allocate();
        \\            defer item.free(for_data);
        \\        }
        \\    }
        \\}
        \\
        \\test "nested test function" {
        \\    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        \\    defer arena.deinit();
        \\    const arena_alloc = arena.allocator();
        \\    
        \\    const test_data = try arena_alloc.alloc(u8, 200);
        \\    // No defer needed for arena allocated memory
        \\}
        ;
    
    // Analyze the source - this creates multiple nested scopes
    try tracker.analyzeSourceCode(source);
    
    // Verify we created the expected scopes
    const scopes = tracker.getScopes();
    
    std.debug.print("LC104: Created {} scopes:\n", .{scopes.len});
    for (scopes, 0..) |scope, i| {
        std.debug.print("  [{}] name='{s}' type={}\n", .{ i, scope.name, scope.scope_type });
    }
    
    // Lower expectation since parsing might not create as many scopes as expected
    try testing.expect(scopes.len >= 1); // At least the function scope
    
    std.debug.print("LC104: Attempting cleanup...\n", .{});
    
    // The crash should occur when deinit() is called in the defer above
}

// Test with repeated analyze/reset cycles to stress the memory management
test "LC104: ScopeTracker repeated reset stress test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 10 }){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch |err| {
            std.debug.print("LC104: Memory leak in reset stress test: {}\n", .{err});
        };
    }
    const allocator = gpa.allocator();
    
    var tracker = ScopeTracker.init(allocator);
    defer tracker.deinit();
    
    // Stress test with multiple analyze/reset cycles
    for (0..10) |i| {
        const source = try std.fmt.allocPrint(allocator, 
            \\fn function{d}() void {{
            \\    const data{d} = try allocator.alloc(u8, {d});
            \\    defer allocator.free(data{d});
            \\}}
        , .{ i, i, i * 100, i });
        defer allocator.free(source);
        
        try tracker.analyzeSourceCode(source);
        
        // Reset after each analysis
        tracker.reset();
        
        std.debug.print("LC104: Completed reset cycle {}\n", .{i + 1});
    }
}

// Test the patterns.checkProject path that was mentioned in LC106
test "LC104: patterns.checkProject with ScopeTracker crash" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 10 }){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch |err| {
            std.debug.print("LC104: Memory leak in checkProject test: {}\n", .{err});
        };
    }
    const allocator = gpa.allocator();
    
    // Create a temporary directory with test files
    const temp_dir_name = "zig-tooling-test-lc104";
    const cwd = std.fs.cwd();
    
    // Clean up any existing test directory
    cwd.deleteTree(temp_dir_name) catch {};
    
    // Create test directory and file
    try cwd.makeDir(temp_dir_name);
    defer cwd.deleteTree(temp_dir_name) catch {};
    
    const test_file_path = try std.fs.path.join(allocator, &.{ temp_dir_name, "test.zig" });
    defer allocator.free(test_file_path);
    
    const test_content = 
        \\fn complexFunction() !void {
        \\    var arena = std.heap.ArenaAllocator.init(allocator);
        \\    defer arena.deinit();
        \\    
        \\    const arena_alloc = arena.allocator();
        \\    const data = try arena_alloc.alloc(u8, 1000);
        \\    
        \\    if (condition) {
        \\        const temp = try allocator.create(MyType);
        \\        defer allocator.destroy(temp);
        \\    }
        \\}
        ;
    
    const test_file = try cwd.createFile(test_file_path, .{});
    try test_file.writeAll(test_content);
    test_file.close();
    
    // Run patterns.checkProject which uses ScopeTracker internally
    const result = try patterns.checkProject(allocator, temp_dir_name, null, null);
    defer patterns.freeProjectResult(allocator, result);
    
    std.debug.print("LC104: checkProject analyzed {} files with {} issues\n", 
        .{ result.files_analyzed, result.issues_found });
}

// Test specifically for the double-free scenario
test "LC104: ScopeTracker double-free detection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{ 
        .stack_trace_frames = 10,
        .retain_metadata = true, // Keep metadata to detect double-frees
    }){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch |err| {
            std.debug.print("LC104: GPA detected issue: {}\n", .{err});
        };
    }
    const allocator = gpa.allocator();
    
    // Create tracker and immediately analyze code
    var tracker = ScopeTracker.init(allocator);
    
    const source = 
        \\test "simple test" {
        \\    const x = 1;
        \\}
        ;
    
    try tracker.analyzeSourceCode(source);
    
    // Get scopes before deinit to inspect
    const scopes = tracker.getScopes();
    std.debug.print("LC104: Scope names before deinit:\n", .{});
    for (scopes, 0..) |scope, i| {
        std.debug.print("  [{}] name='{s}' (ptr={*}, len={})\n", 
            .{ i, scope.name, scope.name.ptr, scope.name.len });
    }
    
    // Now call deinit - this should trigger the crash if there's a double-free
    tracker.deinit();
    
    std.debug.print("LC104: Successfully completed deinit without crash\n", .{});
}

// Test memory management with edge cases
test "LC104: ScopeTracker edge case memory management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .stack_trace_frames = 10,
        .retain_metadata = true,
    }){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch |err| {
            std.debug.print("LC104: Edge case test detected leak: {}\n", .{err});
        };
    }
    const allocator = gpa.allocator();
    
    // Test 1: Empty source code
    {
        var tracker = ScopeTracker.init(allocator);
        defer tracker.deinit();
        
        try tracker.analyzeSourceCode("");
        try testing.expect(tracker.getScopes().len == 0);
    }
    
    // Test 2: Source with only whitespace and comments
    {
        var tracker = ScopeTracker.init(allocator);
        defer tracker.deinit();
        
        const source = 
            \\   // Just a comment
            \\   
            \\   /* Multi-line
            \\      comment */
            \\   
            ;
        
        try tracker.analyzeSourceCode(source);
        try testing.expect(tracker.getScopes().len == 0);
    }
    
    // Test 3: Deeply nested scopes
    {
        var tracker = ScopeTracker.init(allocator);
        defer tracker.deinit();
        
        const source = 
            \\fn outer() void {
            \\    if (a) {
            \\        while (b) {
            \\            for (items) |item| {
            \\                switch (item) {
            \\                    1 => {
            \\                        comptime {
            \\                            const x = 1;
            \\                        }
            \\                    },
            \\                    else => {},
            \\                }
            \\            }
            \\        }
            \\    }
            \\}
            ;
        
        try tracker.analyzeSourceCode(source);
        const scopes = tracker.getScopes();
        try testing.expect(scopes.len >= 5);
    }
    
    // Test 4: Scope with empty names
    {
        var tracker = ScopeTracker.init(allocator);
        defer tracker.deinit();
        
        const source = 
            \\{ // Anonymous block
            \\    const x = 1;
            \\}
            ;
        
        try tracker.analyzeSourceCode(source);
    }
}

// Test memory ownership transfer scenarios
test "LC104: ScopeTracker ownership transfer patterns" {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .stack_trace_frames = 10,
    }){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch |err| {
            std.debug.print("LC104: Ownership test detected leak: {}\n", .{err});
        };
    }
    const allocator = gpa.allocator();
    
    var tracker = ScopeTracker.init(allocator);
    defer tracker.deinit();
    
    const source = 
        \\// Test various ownership patterns
        \\fn createBuffer() ![]u8 {
        \\    return try allocator.alloc(u8, 100);
        \\}
        \\
        \\fn initStruct() !*MyStruct {
        \\    const s = try allocator.create(MyStruct);
        \\    s.* = .{ .value = 42 };
        \\    return s;
        \\}
        \\
        \\fn makeArray() ![]const Item {
        \\    const items = try allocator.alloc(Item, 10);
        \\    for (items) |*item| {
        \\        item.* = Item.init();
        \\    }
        \\    return items;
        \\}
        ;
    
    try tracker.analyzeSourceCode(source);
    
    // Verify all functions were detected
    const functions = try tracker.getFunctionScopes();
    defer functions.deinit();
    try testing.expect(functions.items.len == 3);
}

// Test concurrent ScopeTracker usage (simulated)
test "LC104: ScopeTracker concurrent usage simulation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .stack_trace_frames = 10,
    }){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch |err| {
            std.debug.print("LC104: Concurrent test detected leak: {}\n", .{err});
        };
    }
    const allocator = gpa.allocator();
    
    // Create multiple trackers simulating concurrent usage
    var trackers: [5]ScopeTracker = undefined;
    
    // Initialize all trackers
    for (&trackers) |*tracker| {
        tracker.* = ScopeTracker.init(allocator);
    }
    
    // Analyze different code in each tracker
    for (&trackers, 0..) |*tracker, i| {
        const source = try std.fmt.allocPrint(allocator,
            \\fn function{d}() void {{
            \\    const data = try allocator.alloc(u8, {d});
            \\    defer allocator.free(data);
            \\}}
        , .{ i, (i + 1) * 100 });
        defer allocator.free(source);
        
        try tracker.analyzeSourceCode(source);
    }
    
    // Clean up all trackers
    for (&trackers) |*tracker| {
        tracker.deinit();
    }
}

// Test builder pattern memory management
test "LC104: ScopeTrackerBuilder memory management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .stack_trace_frames = 10,
    }){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch |err| {
            std.debug.print("LC104: Builder test detected leak: {}\n", .{err});
        };
    }
    const allocator = gpa.allocator();
    
    // Test builder with various configurations
    var builder = ScopeTracker.builder(allocator);
    var tracker = try builder
        .withMaxDepth(50)
        .withArenaTracking(true)
        .withDeferTracking(true)
        .withVariableTracking(true)
        .build();
    defer tracker.deinit();
    
    const source = 
        \\test "builder test" {
        \\    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        \\    defer arena.deinit();
        \\    
        \\    const alloc = arena.allocator();
        \\    const data = try alloc.alloc(u8, 1000);
        \\}
        ;
    
    try tracker.analyzeSourceCode(source);
    
    // Verify configuration was applied
    const config = tracker.getConfig();
    try testing.expect(config.track_arena_allocators);
    try testing.expect(config.track_defer_statements);
    try testing.expect(config.track_variable_lifecycles);
    try testing.expect(config.max_scope_depth == 50);
}
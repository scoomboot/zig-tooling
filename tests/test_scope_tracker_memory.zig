//! Memory leak tests for ScopeTracker and patterns
//! 
//! This test file specifically tests for memory leaks using GeneralPurposeAllocator
//! to detect any leaked allocations. This addresses GitHub Issue #4.

const std = @import("std");
const testing = std.testing;
const zig_tooling = @import("zig_tooling");
const ScopeTracker = zig_tooling.ScopeTracker;
const patterns = zig_tooling.patterns;

test "LC073: ScopeTracker memory leak with GeneralPurposeAllocator" {
    // Use GPA to detect memory leaks
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    // Create and use a ScopeTracker
    var tracker = ScopeTracker.init(allocator);
    
    const source = 
        \\pub fn testFunction() void {
        \\    const data = try allocator.alloc(u8, 100);
        \\    defer allocator.free(data);
        \\    
        \\    var arena = std.heap.ArenaAllocator.init(allocator);
        \\    defer arena.deinit();
        \\    const temp_alloc = arena.allocator();
        \\    const temp_data = try temp_alloc.alloc(u8, 50);
        \\}
        \\
        \\test "sample test" {
        \\    const allocator = std.testing.allocator;
        \\    const buffer = try allocator.alloc(u8, 200);
        \\    defer allocator.free(buffer);
        \\}
        ;
    
    // Analyze the source code
    try tracker.analyzeSourceCode(source);
    
    // Verify we found the expected scopes
    const scopes = tracker.getScopes();
    try testing.expect(scopes.len >= 2);
    
    // Clean up and check for leaks
    tracker.deinit();
    const leaked = gpa.deinit();
    if (leaked == .leak) {
        std.debug.print("\nMemory leak detected in ScopeTracker! Leaked allocations exist.\n", .{});
    }
    try testing.expect(leaked == .ok);
}

test "LC073: ScopeTracker repeated analysis memory leak" {
    // Test that repeated analyses don't leak memory
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    var tracker = ScopeTracker.init(allocator);
    
    const source1 = 
        \\fn func1() void {
        \\    const x = try allocator.alloc(u8, 100);
        \\    defer allocator.free(x);
        \\}
        ;
    
    const source2 = 
        \\fn func2() void {
        \\    var arena = std.heap.ArenaAllocator.init(allocator);
        \\    defer arena.deinit();
        \\}
        ;
    
    // Analyze multiple times (simulating multiple file analyses)
    for (0..5) |_| {
        try tracker.analyzeSourceCode(source1);
        try tracker.analyzeSourceCode(source2);
    }
    
    // Clean up and check for leaks
    tracker.deinit();
    const leaked = gpa.deinit();
    if (leaked == .leak) {
        std.debug.print("\nMemory leak detected in repeated analysis!\n", .{});
    }
    try testing.expect(leaked == .ok);
}

test "LC073: patterns.checkProject memory leak" {
    // Test the full usage chain through patterns.checkProject
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    // Create a temporary directory with test files
    const temp_dir_name = "zig-tooling-test-lc073";
    const cwd = std.fs.cwd();
    
    // Clean up any existing test directory
    cwd.deleteTree(temp_dir_name) catch {};
    
    // Create test directory
    try cwd.makePath(temp_dir_name);
    defer cwd.deleteTree(temp_dir_name) catch {};
    
    // Create a test file
    const test_file_path = try std.fmt.allocPrint(allocator, "{s}/test.zig", .{temp_dir_name});
    defer allocator.free(test_file_path);
    
    const test_source = 
        \\pub fn main() void {
        \\    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        \\    defer _ = gpa.deinit();
        \\    const allocator = gpa.allocator();
        \\    
        \\    const data = allocator.alloc(u8, 100) catch return;
        \\    defer allocator.free(data);
        \\}
        ;
    
    try cwd.writeFile(.{
        .sub_path = test_file_path,
        .data = test_source,
    });
    
    // Analyze the project
    const result = try patterns.checkProject(allocator, temp_dir_name, null, null);
    defer patterns.freeProjectResult(allocator, result);
    
    // Verify analysis completed
    try testing.expect(result.files_analyzed > 0);
    
    // Clean up and check for leaks
    const leaked = gpa.deinit();
    if (leaked == .leak) {
        std.debug.print("\nMemory leak detected in patterns.checkProject!\n", .{});
    }
    try testing.expect(leaked == .ok);
}

test "LC073: ScopeTracker with complex nested scopes" {
    // Test complex nesting to ensure all allocations are freed
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    var tracker = ScopeTracker.init(allocator);
    
    const complex_source = 
        \\fn outerFunction() void {
        \\    const outer_var = try allocator.alloc(u8, 100);
        \\    defer allocator.free(outer_var);
        \\    
        \\    if (condition) {
        \\        const if_var = try allocator.alloc(u8, 50);
        \\        defer allocator.free(if_var);
        \\        
        \\        while (loop_condition) {
        \\            const loop_var = try allocator.alloc(u8, 25);
        \\            defer allocator.free(loop_var);
        \\            
        \\            for (items) |item| {
        \\                const for_var = try allocator.alloc(u8, 10);
        \\                defer allocator.free(for_var);
        \\            }
        \\        }
        \\    } else {
        \\        const else_var = try allocator.alloc(u8, 75);
        \\        defer allocator.free(else_var);
        \\    }
        \\}
        ;
    
    try tracker.analyzeSourceCode(complex_source);
    
    // Verify scopes were created
    const scopes = tracker.getScopes();
    try testing.expect(scopes.len >= 5); // function, if, while, for, else
    
    // Clean up and check for leaks
    tracker.deinit();
    const leaked = gpa.deinit();
    if (leaked == .leak) {
        std.debug.print("\nMemory leak detected with complex scopes!\n", .{});
    }
    try testing.expect(leaked == .ok);
}

test "LC073: MemoryAnalyzer validateAllocatorChoice use-after-free fix" {
    // Test the specific bug that was causing a segfault
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    
    const config = zig_tooling.Config{
        .memory = .{
            .check_defer = true,
            .check_allocator_usage = true,
            .allowed_allocators = &.{
                "std.heap.GeneralPurposeAllocator",
                "std.testing.allocator",
            },
        },
    };
    
    const source = 
        \\pub fn main() void {
        \\    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        \\    defer _ = gpa.deinit();
        \\    const allocator = gpa.allocator();
        \\    
        \\    const data1 = allocator.alloc(u8, 100) catch return;
        \\    defer allocator.free(data1);
        \\    
        \\    // This should trigger allocator validation
        \\    var page_alloc = std.heap.page_allocator;
        \\    const data2 = page_alloc.alloc(u8, 200) catch return;
        \\    defer page_alloc.free(data2);
        \\}
        ;
    
    // This used to cause a segfault due to use-after-free
    const result = try zig_tooling.analyzeMemory(allocator, source, "test.zig", config);
    defer {
        for (result.issues) |issue| {
            allocator.free(issue.file_path);
            allocator.free(issue.message);
            if (issue.suggestion) |s| allocator.free(s);
        }
        allocator.free(result.issues);
    }
    
    // Should have found the disallowed allocator
    try testing.expect(result.issues_found > 0);
    
    // Check for memory leaks
    const leaked = gpa.deinit();
    try testing.expect(leaked == .ok);
}
const std = @import("std");

// Example 1: Missing defer for allocation
pub fn leakyFunction(allocator: std.mem.Allocator) ![]u8 {
    const buffer = try allocator.alloc(u8, 1024);
    // Missing: defer allocator.free(buffer);
    
    // Do some work...
    @memset(buffer, 0);
    
    return buffer;
}

// Example 2: Missing errdefer
pub fn riskyOperation(allocator: std.mem.Allocator) !void {
    const data = try allocator.alloc(u32, 100);
    defer allocator.free(data);
    // Missing: errdefer allocator.free(data);
    
    // This could fail after allocation
    try doSomethingThatMightFail();
}

// Example 3: Proper memory management
pub fn goodExample(allocator: std.mem.Allocator) ![]const u8 {
    const result = try allocator.alloc(u8, 256);
    errdefer allocator.free(result);
    
    try fillBuffer(result);
    
    return result; // Ownership transferred to caller
}

// Helper functions
fn doSomethingThatMightFail() !void {
    // Simulate potential failure
    if (std.crypto.random.int(u32) % 2 == 0) {
        return error.RandomFailure;
    }
}

fn fillBuffer(buffer: []u8) !void {
    @memset(buffer, 'A');
}
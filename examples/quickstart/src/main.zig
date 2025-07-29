const std = @import("std");

// Example application demonstrating code that zig-tooling will analyze
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Quickstart Example Application\n", .{});
    
    // Example 1: Correct memory usage
    try correctMemoryUsage(allocator);
    
    // Example 2: Function with memory issues (for demonstration)
    // Uncomment to see zig-tooling catch the issue:
    // try problematicFunction(allocator);
    
    // Example 3: Using custom allocators
    try customAllocatorExample();
}

// Correct memory management
fn correctMemoryUsage(allocator: std.mem.Allocator) !void {
    const buffer = try allocator.alloc(u8, 1024);
    defer allocator.free(buffer); // Proper cleanup
    
    @memset(buffer, 0);
    std.debug.print("Allocated and cleaned up {} bytes correctly\n", .{buffer.len});
}

// Example with intentional issues for zig-tooling to catch
fn problematicFunction(allocator: std.mem.Allocator) !void {
    // Issue 1: Missing defer
    const leaked_memory = try allocator.alloc(u8, 512);
    // Missing: defer allocator.free(leaked_memory);
    
    // Issue 2: Not using allowed allocator
    var bad_allocator = std.heap.page_allocator;
    const more_memory = try bad_allocator.alloc(u8, 256);
    defer bad_allocator.free(more_memory);
    
    _ = leaked_memory;
}

// Example with arena allocator (common pattern)
fn customAllocatorExample() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    
    const allocator = arena.allocator();
    
    // No individual frees needed with arena
    const data1 = try allocator.alloc(u8, 100);
    const data2 = try allocator.alloc(u8, 200);
    
    _ = data1;
    _ = data2;
    
    std.debug.print("Arena allocator example completed\n", .{});
}

// Factory function that transfers ownership
pub fn createBuffer(allocator: std.mem.Allocator, size: usize) ![]u8 {
    const buffer = try allocator.alloc(u8, size);
    errdefer allocator.free(buffer);
    
    // Initialize buffer
    @memset(buffer, 0);
    
    // Ownership transferred to caller
    return buffer;
}

// Tests demonstrating proper categorization
test "unit: memory: correct allocation" {
    const allocator = std.testing.allocator;
    
    const buffer = try allocator.alloc(u8, 100);
    defer allocator.free(buffer);
    
    try std.testing.expect(buffer.len == 100);
}

test "unit: memory: factory function" {
    const allocator = std.testing.allocator;
    
    const buffer = try createBuffer(allocator, 256);
    defer allocator.free(buffer); // Caller responsible for cleanup
    
    try std.testing.expect(buffer.len == 256);
    try std.testing.expect(buffer[0] == 0);
}

test "integration: allocator: arena usage" {
    // This test uses arena allocator correctly
    try customAllocatorExample();
}
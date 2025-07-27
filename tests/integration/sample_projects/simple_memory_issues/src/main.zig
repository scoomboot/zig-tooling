//! Simple Memory Issues Sample Project
//! 
//! This project intentionally contains various memory safety issues
//! to test the library's ability to detect them correctly.

const std = @import("std");

pub fn main() !void {
    std.debug.print("Memory Issues Demo\n", .{});
    
    try demonstrateMemoryLeaks();
    try demonstrateArenaUsage();
    try demonstrateProperCleanup();
}

/// Function with memory leak - missing defer
pub fn demonstrateMemoryLeaks() !void {
    const allocator = std.heap.page_allocator;
    
    // Memory leak: allocation without corresponding free
    const buffer = try allocator.alloc(u8, 1024);
    // Missing: defer allocator.free(buffer);
    
    std.mem.set(u8, buffer, 0x42);
    std.debug.print("Buffer allocated but not freed\n", .{});
}

/// Function using arena allocator correctly
pub fn demonstrateArenaUsage() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit(); // This is correct for arena
    
    const arena_allocator = arena.allocator();
    
    const data1 = try arena_allocator.alloc(u8, 256);
    const data2 = try arena_allocator.alloc(u8, 512);
    // No individual defer needed - arena.deinit() handles all
    
    std.mem.set(u8, data1, 0x11);
    std.mem.set(u8, data2, 0x22);
    std.debug.print("Arena allocations will be cleaned up automatically\n", .{});
}

/// Function with proper memory management
pub fn demonstrateProperCleanup() !void {
    const allocator = std.heap.page_allocator;
    
    const buffer = try allocator.alloc(u8, 512);
    defer allocator.free(buffer); // Proper cleanup
    
    std.mem.set(u8, buffer, 0xFF);
    std.debug.print("Buffer properly cleaned up\n", .{});
}

/// Function with double allocation issue
pub fn demonstrateDoubleAllocation() !void {
    const allocator = std.heap.page_allocator;
    
    var buffer = try allocator.alloc(u8, 100);
    defer allocator.free(buffer);
    
    // Potential issue: reassigning without freeing first allocation
    buffer = try allocator.alloc(u8, 200);
    // Original 100-byte allocation is now leaked
}

/// Function with conditional allocation paths
pub fn demonstrateConditionalPaths(condition: bool) !void {
    const allocator = std.heap.page_allocator;
    
    if (condition) {
        const buffer = try allocator.alloc(u8, 64);
        // Missing defer in this branch
        std.mem.set(u8, buffer, 0xAA);
    } else {
        const buffer = try allocator.alloc(u8, 128);
        defer allocator.free(buffer); // Proper cleanup in this branch
        std.mem.set(u8, buffer, 0xBB);
    }
}
//! Custom Allocators Sample Project
//! 
//! This project demonstrates various custom allocator patterns that
//! should be properly detected and validated by the library.

const std = @import("std");
const custom_allocators = @import("custom_allocators.zig");

pub fn main() !void {
    std.debug.print("Custom Allocators Demo\n", .{});
    
    try demonstrateCustomPatterns();
    try demonstrateNamingPatterns();
    try demonstrateComplexAllocators();
}

fn demonstrateCustomPatterns() !void {
    std.debug.print("Testing custom allocator patterns...\n", .{});
    
    // Pattern: my_pool_* should be detected as PoolAllocator
    var my_pool_allocator = custom_allocators.PoolAllocator.init();
    defer my_pool_allocator.deinit();
    
    const pool_alloc = my_pool_allocator.allocator();
    const buffer1 = try pool_alloc.alloc(u8, 256);
    defer pool_alloc.free(buffer1);
    
    // Pattern: custom_arena_* should be detected as ArenaAllocator
    var custom_arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer custom_arena_allocator.deinit();
    
    const arena_alloc = custom_arena_allocator.allocator();
    const buffer2 = try arena_alloc.alloc(u8, 512);
    // No need for individual defer with arena
    
    std.debug.print("Custom patterns demonstrated\n", .{});
}

fn demonstrateNamingPatterns() !void {
    std.debug.print("Testing naming pattern detection...\n", .{});
    
    // Various naming patterns that should be detected
    var my_custom_allocator = custom_allocators.CustomAllocator.init();
    defer my_custom_allocator.deinit();
    
    var project_allocator = custom_allocators.ProjectAllocator.init();
    defer project_allocator.deinit();
    
    var temp_arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer temp_arena_allocator.deinit();
    
    // Test allocations
    const custom_alloc = my_custom_allocator.allocator();
    const buffer1 = try custom_alloc.alloc(u8, 128);
    defer custom_alloc.free(buffer1);
    
    const project_alloc = project_allocator.allocator();
    const buffer2 = try project_alloc.alloc(u8, 256);
    defer project_alloc.free(buffer2);
    
    const temp_alloc = temp_arena_allocator.allocator();
    const buffer3 = try temp_alloc.alloc(u8, 64);
    // Arena cleanup handles this
    
    std.debug.print("Naming patterns demonstrated\n", .{});
}

fn demonstrateComplexAllocators() !void {
    std.debug.print("Testing complex allocator scenarios...\n", .{});
    
    // Nested allocator usage
    var primary_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer primary_arena.deinit();
    
    const primary_allocator = primary_arena.allocator();
    
    // Create a secondary allocator using the primary
    var secondary_pool = custom_allocators.PoolAllocator.initWithAllocator(primary_allocator);
    defer secondary_pool.deinit();
    
    const secondary_allocator = secondary_pool.allocator();
    
    // Allocations using nested pattern
    const data = try secondary_allocator.alloc(u8, 1024);
    defer secondary_allocator.free(data);
    
    std.mem.set(u8, data, 0xEE);
    
    std.debug.print("Complex allocator scenarios demonstrated\n", .{});
}
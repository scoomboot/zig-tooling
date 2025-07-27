//! Allocator Manager - demonstrates custom allocator patterns
//! 
//! This module shows how the library should handle custom allocator
//! detection and tracking across different allocation strategies.

const std = @import("std");

/// Custom allocator manager that wraps different allocator types
pub const AllocatorManager = struct {
    base_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    pool_allocator: ?std.heap.MemoryPool(u8),
    allocation_count: u32,
    
    pub fn init(base_allocator: std.mem.Allocator) !AllocatorManager {
        return AllocatorManager{
            .base_allocator = base_allocator,
            .arena = std.heap.ArenaAllocator.init(base_allocator),
            .pool_allocator = null, // Initialize as needed
            .allocation_count = 0,
        };
    }
    
    pub fn deinit(self: *AllocatorManager) void {
        self.arena.deinit();
        if (self.pool_allocator) |*pool| {
            pool.deinit();
        }
    }
    
    /// Allocate using the base allocator
    pub fn allocate(self: *AllocatorManager, size: usize) ![]u8 {
        self.allocation_count += 1;
        return try self.base_allocator.alloc(u8, size);
    }
    
    /// Deallocate using the base allocator
    pub fn deallocate(self: *AllocatorManager, buffer: []u8) void {
        self.base_allocator.free(buffer);
    }
    
    /// Allocate using arena - no individual free needed
    pub fn allocateArena(self: *AllocatorManager, size: usize) ![]u8 {
        const arena_allocator = self.arena.allocator();
        return try arena_allocator.alloc(u8, size);
    }
    
    /// Initialize pool allocator if needed
    pub fn initPool(self: *AllocatorManager) !void {
        if (self.pool_allocator == null) {
            self.pool_allocator = std.heap.MemoryPool(u8).init(self.base_allocator);
        }
    }
    
    /// Allocate from pool
    pub fn allocateFromPool(self: *AllocatorManager) !*u8 {
        if (self.pool_allocator == null) {
            try self.initPool();
        }
        
        if (self.pool_allocator) |*pool| {
            return try pool.create();
        } else {
            return error.PoolNotInitialized;
        }
    }
    
    /// Return item to pool
    pub fn returnToPool(self: *AllocatorManager, item: *u8) void {
        if (self.pool_allocator) |*pool| {
            pool.destroy(item);
        }
    }
    
    /// Function with potential memory leak
    pub fn leakyFunction(self: *AllocatorManager) ![]u8 {
        const buffer = try self.allocate(1024);
        // Missing corresponding deallocate call
        
        std.mem.set(u8, buffer, 0xCC);
        return buffer; // Caller must remember to free
    }
    
    /// Function with proper cleanup
    pub fn properFunction(self: *AllocatorManager, size: usize) ![]u8 {
        const temp_buffer = try self.allocate(size * 2);
        defer self.deallocate(temp_buffer);
        
        // Process in temporary buffer
        std.mem.set(u8, temp_buffer, 0xDD);
        
        // Return properly allocated result
        const result = try self.allocate(size);
        std.mem.copy(u8, result, temp_buffer[0..size]);
        return result;
    }
};

/// Global allocator pattern that should be detected
var global_arena: std.heap.ArenaAllocator = undefined;
var global_arena_initialized: bool = false;

pub fn getGlobalArenaAllocator() std.mem.Allocator {
    if (!global_arena_initialized) {
        global_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        global_arena_initialized = true;
    }
    return global_arena.allocator();
}

pub fn deinitGlobalArena() void {
    if (global_arena_initialized) {
        global_arena.deinit();
        global_arena_initialized = false;
    }
}

/// Custom allocator pattern with specific naming
var my_custom_pool_allocator: ?std.heap.MemoryPool(u8) = null;

pub fn getCustomPoolAllocator() !std.mem.Allocator {
    if (my_custom_pool_allocator == null) {
        my_custom_pool_allocator = std.heap.MemoryPool(u8).init(std.heap.page_allocator);
    }
    
    // This should be detected as a custom allocator pattern
    return my_custom_pool_allocator.?.allocator();
}
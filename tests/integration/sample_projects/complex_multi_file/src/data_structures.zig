//! Data Structures - demonstrates complex memory patterns
//! 
//! This module contains data structures with various memory management
//! patterns that should be properly analyzed by the library.

const std = @import("std");

/// Dynamic list implementation with potential memory issues
pub const DynamicList = struct {
    items: []u32,
    capacity: usize,
    len_used: usize,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) !DynamicList {
        const initial_capacity = 8;
        const items = try allocator.alloc(u32, initial_capacity);
        
        return DynamicList{
            .items = items,
            .capacity = initial_capacity,
            .len_used = 0,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *DynamicList) void {
        self.allocator.free(self.items);
    }
    
    pub fn append(self: *DynamicList, item: u32) !void {
        if (self.len_used >= self.capacity) {
            try self.grow();
        }
        
        self.items[self.len_used] = item;
        self.len_used += 1;
    }
    
    pub fn len(self: *DynamicList) usize {
        return self.len_used;
    }
    
    fn grow(self: *DynamicList) !void {
        const new_capacity = self.capacity * 2;
        const new_items = try self.allocator.alloc(u32, new_capacity);
        
        std.mem.copy(u32, new_items, self.items[0..self.len_used]);
        self.allocator.free(self.items);
        
        self.items = new_items;
        self.capacity = new_capacity;
    }
    
    /// Function with potential memory leak
    pub fn cloneWithoutFree(self: *DynamicList) !DynamicList {
        const new_items = try self.allocator.alloc(u32, self.capacity);
        // This creates a copy but doesn't set up proper cleanup
        
        std.mem.copy(u32, new_items, self.items[0..self.len_used]);
        
        return DynamicList{
            .items = new_items,
            .capacity = self.capacity,
            .len_used = self.len_used,
            .allocator = self.allocator,
        };
    }
};

/// String buffer with arena-based allocation
pub const StringBuffer = struct {
    arena: std.heap.ArenaAllocator,
    strings: std.ArrayList([]const u8),
    
    pub fn init(base_allocator: std.mem.Allocator) StringBuffer {
        const arena = std.heap.ArenaAllocator.init(base_allocator);
        const arena_allocator = arena.allocator();
        
        return StringBuffer{
            .arena = arena,
            .strings = std.ArrayList([]const u8).init(arena_allocator),
        };
    }
    
    pub fn deinit(self: *StringBuffer) void {
        // Arena deinit handles all string allocations
        self.arena.deinit();
    }
    
    pub fn addString(self: *StringBuffer, str: []const u8) !void {
        const arena_allocator = self.arena.allocator();
        const owned_str = try arena_allocator.dupe(u8, str);
        try self.strings.append(owned_str);
    }
    
    pub fn getString(self: *StringBuffer, index: usize) ?[]const u8 {
        if (index >= self.strings.items.len) return null;
        return self.strings.items[index];
    }
    
    pub fn count(self: *StringBuffer) usize {
        return self.strings.items.len;
    }
};

/// Memory pool for fixed-size allocations
pub const FixedSizePool = struct {
    pool: std.heap.MemoryPool(Block),
    block_size: usize,
    
    const Block = struct {
        data: [256]u8,
    };
    
    pub fn init(allocator: std.mem.Allocator) FixedSizePool {
        return FixedSizePool{
            .pool = std.heap.MemoryPool(Block).init(allocator),
            .block_size = 256,
        };
    }
    
    pub fn deinit(self: *FixedSizePool) void {
        self.pool.deinit();
    }
    
    pub fn allocateBlock(self: *FixedSizePool) !*Block {
        return try self.pool.create();
    }
    
    pub fn deallocateBlock(self: *FixedSizePool, block: *Block) void {
        self.pool.destroy(block);
    }
    
    /// Function that might forget to deallocate
    pub fn processData(self: *FixedSizePool, data: []const u8) ![]u8 {
        const block = try self.allocateBlock();
        // Should deallocate block when done, but this might be forgotten
        
        const copy_len = std.math.min(data.len, self.block_size);
        std.mem.copy(u8, block.data[0..copy_len], data[0..copy_len]);
        
        // Return a copy - block should be deallocated
        const result = try std.heap.page_allocator.alloc(u8, copy_len);
        std.mem.copy(u8, result, block.data[0..copy_len]);
        
        // Missing: self.deallocateBlock(block);
        
        return result;
    }
};
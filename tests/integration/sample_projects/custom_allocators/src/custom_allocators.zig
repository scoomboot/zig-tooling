//! Custom Allocator Implementations
//! 
//! This module defines various custom allocators with different naming patterns
//! that should be detected and properly categorized by the memory analyzer.

const std = @import("std");

/// Pool allocator implementation - should be detected by "pool" pattern
pub const PoolAllocator = struct {
    pool: std.heap.MemoryPool(Block),
    base_allocator: std.mem.Allocator,
    
    const Block = struct {
        data: [512]u8,
        
        fn asSlice(self: *Block) []u8 {
            return &self.data;
        }
    };
    
    pub fn init() PoolAllocator {
        return PoolAllocator{
            .pool = std.heap.MemoryPool(Block).init(std.heap.page_allocator),
            .base_allocator = std.heap.page_allocator,
        };
    }
    
    pub fn initWithAllocator(base_allocator: std.mem.Allocator) PoolAllocator {
        return PoolAllocator{
            .pool = std.heap.MemoryPool(Block).init(base_allocator),
            .base_allocator = base_allocator,
        };
    }
    
    pub fn deinit(self: *PoolAllocator) void {
        self.pool.deinit();
    }
    
    pub fn allocator(self: *PoolAllocator) std.mem.Allocator {
        return std.mem.Allocator{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }
    
    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        _ = ptr_align;
        _ = ret_addr;
        
        const self: *PoolAllocator = @ptrCast(@alignCast(ctx));
        
        if (len > 512) {
            // Fall back to base allocator for large allocations
            const ptr = self.base_allocator.rawAlloc(len, ptr_align, ret_addr);
            return ptr;
        }
        
        const block = self.pool.create() catch return null;
        return block.data[0..len].ptr;
    }
    
    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return false; // Not supported
    }
    
    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        _ = buf_align;
        _ = ret_addr;
        
        const self: *PoolAllocator = @ptrCast(@alignCast(ctx));
        
        if (buf.len > 512) {
            // This was allocated by base allocator
            self.base_allocator.rawFree(buf, buf_align, ret_addr);
            return;
        }
        
        // Find the block containing this buffer
        const block_ptr = @as(*Block, @ptrFromInt(@intFromPtr(buf.ptr) & ~@as(usize, 511)));
        self.pool.destroy(block_ptr);
    }
};

/// Custom allocator - should be detected by "custom" pattern
pub const CustomAllocator = struct {
    arena: std.heap.ArenaAllocator,
    allocations: u32,
    
    pub fn init() CustomAllocator {
        return CustomAllocator{
            .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
            .allocations = 0,
        };
    }
    
    pub fn deinit(self: *CustomAllocator) void {
        self.arena.deinit();
    }
    
    pub fn allocator(self: *CustomAllocator) std.mem.Allocator {
        return std.mem.Allocator{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }
    
    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *CustomAllocator = @ptrCast(@alignCast(ctx));
        self.allocations += 1;
        
        const arena_allocator = self.arena.allocator();
        return arena_allocator.rawAlloc(len, ptr_align, ret_addr);
    }
    
    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *CustomAllocator = @ptrCast(@alignCast(ctx));
        const arena_allocator = self.arena.allocator();
        return arena_allocator.rawResize(buf, buf_align, new_len, ret_addr);
    }
    
    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        // Arena-based, so individual free is a no-op
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = ret_addr;
    }
};

/// Project-specific allocator - should be detected by "project" pattern
pub const ProjectAllocator = struct {
    gpa: std.heap.GeneralPurposeAllocator(.{}),
    total_allocated: usize,
    
    pub fn init() ProjectAllocator {
        return ProjectAllocator{
            .gpa = std.heap.GeneralPurposeAllocator(.{}){},
            .total_allocated = 0,
        };
    }
    
    pub fn deinit(self: *ProjectAllocator) void {
        _ = self.gpa.deinit();
    }
    
    pub fn allocator(self: *ProjectAllocator) std.mem.Allocator {
        return std.mem.Allocator{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }
    
    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *ProjectAllocator = @ptrCast(@alignCast(ctx));
        self.total_allocated += len;
        
        const gpa_allocator = self.gpa.allocator();
        return gpa_allocator.rawAlloc(len, ptr_align, ret_addr);
    }
    
    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *ProjectAllocator = @ptrCast(@alignCast(ctx));
        const gpa_allocator = self.gpa.allocator();
        
        if (new_len > buf.len) {
            self.total_allocated += (new_len - buf.len);
        }
        
        return gpa_allocator.rawResize(buf, buf_align, new_len, ret_addr);
    }
    
    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        const self: *ProjectAllocator = @ptrCast(@alignCast(ctx));
        const gpa_allocator = self.gpa.allocator();
        
        if (self.total_allocated >= buf.len) {
            self.total_allocated -= buf.len;
        }
        
        gpa_allocator.rawFree(buf, buf_align, ret_addr);
    }
};

/// Test functions using the custom allocators
pub fn demonstratePoolUsage() !void {
    var my_pool_allocator = PoolAllocator.init();
    defer my_pool_allocator.deinit();
    
    const pool_alloc = my_pool_allocator.allocator();
    
    const buffer = try pool_alloc.alloc(u8, 256);
    defer pool_alloc.free(buffer);
    
    std.mem.set(u8, buffer, 0xAA);
}

pub fn demonstrateCustomUsage() !void {
    var my_custom_allocator = CustomAllocator.init();
    defer my_custom_allocator.deinit();
    
    const custom_alloc = my_custom_allocator.allocator();
    
    const buffer = try custom_alloc.alloc(u8, 128);
    // No individual free needed with arena-based custom allocator
    
    std.mem.set(u8, buffer, 0xBB);
}

pub fn demonstrateProjectUsage() !void {
    var project_allocator = ProjectAllocator.init();
    defer project_allocator.deinit();
    
    const proj_alloc = project_allocator.allocator();
    
    const buffer = try proj_alloc.alloc(u8, 512);
    defer proj_alloc.free(buffer);
    
    std.mem.set(u8, buffer, 0xCC);
}
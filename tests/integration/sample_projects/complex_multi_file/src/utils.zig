//! Utility functions for the complex multi-file project
//! 
//! Contains various memory management patterns and helper functions
//! that should be analyzed for compliance.

const std = @import("std");

/// Fill a buffer with a specific value
pub fn fillBuffer(buffer: []u8, value: u8) void {
    std.mem.set(u8, buffer, value);
}

/// Process input data and return allocated result
/// This function has proper memory management
pub fn processData(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const result = try allocator.alloc(u8, input.len * 2);
    
    for (input, 0..) |char, i| {
        result[i * 2] = char;
        result[i * 2 + 1] = char;
    }
    
    return result;
}

/// Create a temporary buffer for processing
/// This function has a memory leak - missing defer
pub fn createTempBuffer(allocator: std.mem.Allocator, size: usize) ![]u8 {
    const buffer = try allocator.alloc(u8, size);
    // Missing: defer allocator.free(buffer);
    
    std.mem.set(u8, buffer, 0);
    return buffer;
}

/// Helper function with proper error handling
pub fn safeProcessing(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    if (data.len == 0) {
        return try allocator.dupe(u8, "empty");
    }
    
    const buffer = try allocator.alloc(u8, data.len + 10);
    errdefer allocator.free(buffer);
    
    std.mem.copy(u8, buffer[0..data.len], data);
    std.mem.set(u8, buffer[data.len..], 0);
    
    return buffer;
}

/// String manipulation with potential issues
pub fn duplicateString(allocator: std.mem.Allocator, str: []const u8, count: u32) ![]u8 {
    const total_len = str.len * count;
    const result = try allocator.alloc(u8, total_len);
    
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const start = i * str.len;
        std.mem.copy(u8, result[start..start + str.len], str);
    }
    
    return result;
}

/// Function with conditional memory management
pub fn conditionalAllocation(allocator: std.mem.Allocator, use_large: bool) ![]u8 {
    if (use_large) {
        const buffer = try allocator.alloc(u8, 4096);
        defer allocator.free(buffer); // Proper cleanup
        
        // Process buffer...
        const result = try allocator.dupe(u8, buffer[0..100]);
        return result;
    } else {
        const buffer = try allocator.alloc(u8, 256);
        // Missing defer allocator.free(buffer) in this branch
        
        // Process buffer...
        const result = try allocator.dupe(u8, buffer[0..50]);
        return result;
    }
}
//! Complex Multi-File Sample Project
//! 
//! This project demonstrates analysis across multiple files with various
//! memory patterns, test compliance issues, and inter-module dependencies.

const std = @import("std");
const utils = @import("utils.zig");
const allocator_manager = @import("allocator_manager.zig");
const data_structures = @import("data_structures.zig");

pub fn main() !void {
    std.debug.print("Complex Multi-File Demo\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    try demonstrateModuleInteractions(allocator);
    try demonstrateDataStructures(allocator);
    try demonstrateUtilityUsage(allocator);
}

fn demonstrateModuleInteractions(allocator: std.mem.Allocator) !void {
    std.debug.print("Testing module interactions...\n", .{});
    
    // Test allocator manager
    var manager = try allocator_manager.AllocatorManager.init(allocator);
    defer manager.deinit();
    
    const buffer = try manager.allocate(1024);
    defer manager.deallocate(buffer);
    
    utils.fillBuffer(buffer, 0xAB);
    std.debug.print("Module interaction test complete\n", .{});
}

fn demonstrateDataStructures(allocator: std.mem.Allocator) !void {
    std.debug.print("Testing data structures...\n", .{});
    
    var list = try data_structures.DynamicList.init(allocator);
    defer list.deinit();
    
    try list.append(42);
    try list.append(84);
    try list.append(126);
    
    std.debug.print("Dynamic list has {} items\n", .{list.len()});
}

fn demonstrateUtilityUsage(allocator: std.mem.Allocator) !void {
    std.debug.print("Testing utility functions...\n", .{});
    
    const processed_data = try utils.processData(allocator, "test input");
    defer allocator.free(processed_data);
    
    std.debug.print("Processed data: {s}\n", .{processed_data});
}
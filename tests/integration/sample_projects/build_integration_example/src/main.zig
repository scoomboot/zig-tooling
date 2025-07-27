//! Build Integration Example Project
//! 
//! This project demonstrates integration with build systems and
//! shows how the library can be used in real build workflows.

const std = @import("std");

pub fn main() !void {
    std.debug.print("Build Integration Demo\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    try processData(allocator);
    try demonstrateBuildIntegration();
}

fn processData(allocator: std.mem.Allocator) !void {
    std.debug.print("Processing data with proper memory management...\n", .{});
    
    const data = try allocator.alloc(u8, 1024);
    defer allocator.free(data);
    
    std.mem.set(u8, data, 0x42);
    
    const processed = try transformData(allocator, data);
    defer allocator.free(processed);
    
    std.debug.print("Processed {} bytes\n", .{processed.len});
}

fn transformData(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const output = try allocator.alloc(u8, input.len);
    
    for (input, 0..) |byte, i| {
        output[i] = byte ^ 0xFF;
    }
    
    return output;
}

fn demonstrateBuildIntegration() !void {
    std.debug.print("Demonstrating build integration patterns...\n", .{});
    
    // This function would typically be called as part of build process
    try validateCodeQuality();
    try runPerformanceChecks();
}

fn validateCodeQuality() !void {
    std.debug.print("Running code quality validation...\n", .{});
    
    // Simulate quality checks that would be run during build
    const allocator = std.heap.page_allocator;
    
    const temp_data = try allocator.alloc(u8, 512);
    defer allocator.free(temp_data);
    
    std.mem.set(u8, temp_data, 0x00);
    
    std.debug.print("Code quality validation complete\n", .{});
}

fn runPerformanceChecks() !void {
    std.debug.print("Running performance checks...\n", .{});
    
    const start_time = std.time.milliTimestamp();
    
    // Simulate some work
    var i: u32 = 0;
    while (i < 1000000) : (i += 1) {
        _ = i * 2;
    }
    
    const end_time = std.time.milliTimestamp();
    const duration = end_time - start_time;
    
    std.debug.print("Performance check completed in {}ms\n", .{duration});
}
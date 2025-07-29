//! Advanced Example: Custom Allocator and Ownership Patterns
//!
//! This example demonstrates how to configure zig-tooling to work with:
//! - Custom allocator types
//! - Project-specific ownership transfer patterns
//! - Pattern conflict resolution
//! - Advanced configuration options

const std = @import("std");
const zig_tooling = @import("zig_tooling");

// === Custom Allocators ===

// Example custom allocator wrapper
pub const ProjectAllocator = struct {
    underlying: std.mem.Allocator,
    debug_name: []const u8,
    
    pub fn init(underlying: std.mem.Allocator, name: []const u8) ProjectAllocator {
        return .{
            .underlying = underlying,
            .debug_name = name,
        };
    }
    
    pub fn allocator(self: *ProjectAllocator) std.mem.Allocator {
        return self.underlying;
    }
};

// Thread-safe pool allocator
pub const ThreadSafePool = struct {
    mutex: std.Thread.Mutex,
    pool: std.heap.MemoryPool(u8),
    
    pub fn init() ThreadSafePool {
        return .{
            .mutex = .{},
            .pool = std.heap.MemoryPool(u8).init(std.heap.page_allocator),
        };
    }
    
    pub fn allocator(self: *ThreadSafePool) std.mem.Allocator {
        // In real code, this would wrap allocations with mutex
        return self.pool.allocator();
    }
    
    pub fn deinit(self: *ThreadSafePool) void {
        self.pool.deinit();
    }
};

// === Ownership Transfer Patterns ===

// Resource that transfers ownership
pub const OwnedResource = struct {
    data: []u8,
    allocator: std.mem.Allocator,
    
    // Factory function - transfers ownership
    pub fn acquire(allocator: std.mem.Allocator, size: usize) !OwnedResource {
        const data = try allocator.alloc(u8, size);
        errdefer allocator.free(data);
        
        return OwnedResource{
            .data = data,
            .allocator = allocator,
        };
    }
    
    pub fn release(self: *OwnedResource) void {
        self.allocator.free(self.data);
        self.* = undefined;
    }
};

// Builder pattern that transfers ownership
pub const MessageBuilder = struct {
    allocator: std.mem.Allocator,
    parts: std.ArrayList([]const u8),
    
    pub fn init(allocator: std.mem.Allocator) MessageBuilder {
        return .{
            .allocator = allocator,
            .parts = std.ArrayList([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *MessageBuilder) void {
        for (self.parts.items) |part| {
            self.allocator.free(part);
        }
        self.parts.deinit();
    }
    
    pub fn addPart(self: *MessageBuilder, text: []const u8) !void {
        const copy = try self.allocator.dupe(u8, text);
        try self.parts.append(copy);
    }
    
    // Transfers ownership to caller
    pub fn buildMessage(self: *MessageBuilder) ![]u8 {
        var total_len: usize = 0;
        for (self.parts.items) |part| {
            total_len += part.len;
        }
        
        const message = try self.allocator.alloc(u8, total_len);
        errdefer self.allocator.free(message);
        
        var offset: usize = 0;
        for (self.parts.items) |part| {
            @memcpy(message[offset..][0..part.len], part);
            offset += part.len;
        }
        
        return message; // Ownership transferred
    }
};

// === Configuration Example ===

pub fn getCustomConfig() zig_tooling.Config {
    return zig_tooling.Config{
        .memory = .{
            // Basic checks
            .check_defer = true,
            .check_arena_usage = true,
            .check_allocator_usage = true,
            
            // Disable conflicting default patterns
            .disabled_default_patterns = &.{
                "std.testing.allocator", // We'll define our own
            },
            
            // Define allowed allocators
            .allowed_allocators = &.{
                "ProjectAllocator",
                "ThreadSafePool",
                "std.heap.GeneralPurposeAllocator",
                "TestAllocator", // Our custom test allocator
            },
            
            // Custom allocator detection patterns
            .allocator_patterns = &.{
                // Detect ProjectAllocator instances
                .{ .name = "ProjectAllocator", .pattern = "project_alloc" },
                .{ .name = "ProjectAllocator", .pattern = "proj_allocator" },
                
                // Detect ThreadSafePool
                .{ .name = "ThreadSafePool", .pattern = "thread_pool" },
                .{ .name = "ThreadSafePool", .pattern = "safe_pool" },
                
                // Custom test allocator pattern
                .{ .name = "TestAllocator", .pattern = "test_allocator" },
            },
            
            // Ownership transfer patterns
            .ownership_patterns = &.{
                // Resource acquisition
                .{ 
                    .function_pattern = "acquire",
                    .return_type_pattern = "!OwnedResource",
                    .description = "Resource acquisition" 
                },
                
                // Builder pattern
                .{ 
                    .function_pattern = "build",
                    .description = "Builder methods that return owned data" 
                },
                
                // Message/string creation
                .{ 
                    .function_pattern = "Message$",  // Ends with "Message"
                    .return_type_pattern = "![]u8",
                    .description = "Message builders" 
                },
                
                // Factory functions for custom types
                .{ 
                    .function_pattern = "create",
                    .return_type_pattern = "!*",  // Any pointer type
                    .description = "Factory functions" 
                },
            },
        },
        .testing = .{
            .enforce_categories = true,
            .enforce_naming = true,
            .allowed_categories = &.{ "unit", "integration", "stress", "perf" },
        },
        .options = .{
            .max_issues = 100,
            .verbose = true,
            .continue_on_error = true,
        },
    };
}

// === Example Usage ===

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Run analysis with custom configuration
    const config = getCustomConfig();
    
    // Analyze this file to demonstrate pattern detection
    const result = try zig_tooling.analyzeFile(allocator, "custom_patterns.zig", config);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    // Display results
    const output = try zig_tooling.formatters.formatAsText(allocator, result, .{
        .color = true,
        .verbose = true,
    });
    defer allocator.free(output);
    
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(output);
}

// === Example Code to Analyze ===

fn exampleCorrectUsage() !void {
    // Using custom allocator correctly
    var project_alloc = ProjectAllocator.init(std.heap.page_allocator, "main");
    const allocator = project_alloc.allocator();
    
    // Correct: ownership transfer recognized
    const resource = try OwnedResource.acquire(allocator, 1024);
    defer resource.release();
    
    // Correct: builder pattern recognized
    var builder = MessageBuilder.init(allocator);
    defer builder.deinit();
    
    try builder.addPart("Hello, ");
    try builder.addPart("World!");
    
    const message = try builder.buildMessage();
    defer allocator.free(message); // Caller owns the message
}

fn exampleWithIssues() !void {
    // Issue: Using non-allowed allocator
    var bad_alloc = std.heap.page_allocator;
    const data = try bad_alloc.alloc(u8, 100);
    // Issue: Missing defer
    _ = data;
    
    // Issue: Not recognizing custom pattern
    var my_pool = ThreadSafePool.init();
    defer my_pool.deinit();
    
    // This would be flagged without our custom pattern
    const pool_alloc = my_pool.allocator();
    const buffer = try pool_alloc.alloc(u8, 200);
    defer pool_alloc.free(buffer);
}

// === Tests ===

test "unit: patterns: custom allocator detection" {
    var project_alloc = ProjectAllocator.init(std.testing.allocator, "test");
    const allocator = project_alloc.allocator();
    
    const data = try allocator.alloc(u8, 100);
    defer allocator.free(data);
    
    try std.testing.expect(data.len == 100);
}

test "integration: patterns: ownership transfer" {
    const allocator = std.testing.allocator;
    
    // Test resource acquisition
    const resource = try OwnedResource.acquire(allocator, 512);
    defer resource.release();
    
    // Test builder pattern
    var builder = MessageBuilder.init(allocator);
    defer builder.deinit();
    
    try builder.addPart("Test");
    const msg = try builder.buildMessage();
    defer allocator.free(msg);
    
    try std.testing.expectEqualStrings("Test", msg);
}

// Custom test allocator for testing
var test_allocator_instance = std.testing.allocator;

test "unit: patterns: custom test allocator" {
    // This uses our custom test allocator pattern
    const allocator = test_allocator_instance;
    
    const buffer = try allocator.alloc(u8, 50);
    defer allocator.free(buffer);
    
    try std.testing.expect(buffer.len == 50);
}
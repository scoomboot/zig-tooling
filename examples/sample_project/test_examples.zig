const std = @import("std");
const testing = std.testing;

// Good: Properly named test with memory management
test "memory: allocation and cleanup" {
    const allocator = testing.allocator;
    
    const data = try allocator.alloc(u8, 100);
    defer allocator.free(data);
    
    try testing.expect(data.len == 100);
}

// Bad: Improperly named test (should start with "test")
fn testSomething() !void {
    // This won't be recognized as a test
}

// Bad: Test without proper prefix
test "something without category" {
    // Should be categorized like "unit: " or "integration: "
}

// Good: Categorized integration test
test "integration: database connection" {
    const allocator = testing.allocator;
    
    const conn = try allocator.create(DatabaseConnection);
    defer allocator.destroy(conn);
    
    try conn.connect();
    defer conn.disconnect();
    
    try testing.expect(conn.isConnected());
}

// Good: Performance test with proper naming
test "performance: large data processing" {
    const allocator = testing.allocator;
    
    const start = std.time.milliTimestamp();
    defer {
        const end = std.time.milliTimestamp();
        std.debug.print("Test took {}ms\n", .{end - start});
    }
    
    const large_data = try allocator.alloc(u8, 1024 * 1024);
    defer allocator.free(large_data);
    
    processData(large_data);
}

// Test helpers
const DatabaseConnection = struct {
    connected: bool = false,
    
    fn connect(self: *DatabaseConnection) !void {
        self.connected = true;
    }
    
    fn disconnect(self: *DatabaseConnection) void {
        self.connected = false;
    }
    
    fn isConnected(self: DatabaseConnection) bool {
        return self.connected;
    }
};

fn processData(data: []u8) void {
    _ = data;
    // Simulate processing
}
//! Tests for utility functions
//! 
//! This file demonstrates various test compliance patterns and issues
//! that should be detected by the testing analyzer.

const std = @import("std");
const testing = std.testing;
const utils = @import("../src/utils.zig");

// Proper test with category
test "unit: utils: fillBuffer works correctly" {
    var buffer: [10]u8 = undefined;
    utils.fillBuffer(&buffer, 0x42);
    
    for (buffer) |byte| {
        try testing.expectEqual(@as(u8, 0x42), byte);
    }
}

// Proper test with category
test "unit: utils: processData duplicates input" {
    const allocator = testing.allocator;
    
    const input = "hello";
    const result = try utils.processData(allocator, input);
    defer allocator.free(result);
    
    try testing.expectEqual(@as(usize, 10), result.len);
    try testing.expectEqualStrings("hheelllloo", result);
}

// Test missing category - should be flagged
test "safeProcessing handles empty input" {
    const allocator = testing.allocator;
    
    const result = try utils.safeProcessing(allocator, "");
    defer allocator.free(result);
    
    try testing.expectEqualStrings("empty", result);
}

// Test with incorrect category format
test "integration:duplicateString creates multiple copies" {
    const allocator = testing.allocator;
    
    const result = try utils.duplicateString(allocator, "abc", 3);
    defer allocator.free(result);
    
    try testing.expectEqualStrings("abcabcabc", result);
}

// Test with wrong naming convention - should be flagged
test "BadTestName" {
    const allocator = testing.allocator;
    
    const result = try utils.conditionalAllocation(allocator, true);
    defer allocator.free(result);
    
    try testing.expect(result.len == 100);
}

// Test missing test function prefix - should be flagged
test "e2e: utils: memory leak in conditionalAllocation" {
    const allocator = testing.allocator;
    
    // This test demonstrates how memory leaks might be detected
    const result = try utils.conditionalAllocation(allocator, false);
    defer allocator.free(result);
    
    try testing.expect(result.len == 50);
}

// Properly categorized performance test
test "performance: utils: processData performance" {
    const allocator = testing.allocator;
    
    const large_input = "x" ** 1000;
    const start_time = std.time.milliTimestamp();
    
    const result = try utils.processData(allocator, large_input);
    defer allocator.free(result);
    
    const end_time = std.time.milliTimestamp();
    const duration = end_time - start_time;
    
    std.debug.print("processData took {}ms for 1000 chars\n", .{duration});
    try testing.expect(result.len == 2000);
}

// Test with good naming and category
test "integration: utils: createTempBuffer integration test" {
    const allocator = testing.allocator;
    
    // This test might reveal memory leaks in createTempBuffer
    const buffer = try utils.createTempBuffer(allocator, 512);
    defer allocator.free(buffer); // We have to clean up the leak
    
    try testing.expect(buffer.len == 512);
    
    // All bytes should be zero
    for (buffer) |byte| {
        try testing.expectEqual(@as(u8, 0), byte);
    }
}
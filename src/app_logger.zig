//! Lightweight callback-based logging for library usage
//!
//! This module provides a simple, optional logging interface that allows
//! library users to integrate their own logging implementations.
//!
//! ## Example Usage
//! ```zig
//! const LogConfig = LoggingConfig{
//!     .enabled = true,
//!     .callback = myLogHandler,
//!     .min_level = .info,
//! };
//!
//! fn myLogHandler(event: LogEvent) void {
//!     std.debug.print("[{s}] {s}: {s}\n", .{
//!         @tagName(event.level),
//!         event.category,
//!         event.message,
//!     });
//! }
//! ```

const std = @import("std");

/// Log severity levels
///
/// Used to categorize log messages by importance and control
/// which messages are emitted based on the minimum level setting.
///
/// ## Levels (from least to most severe)
/// - `debug`: Detailed debugging information
/// - `info`: General informational messages
/// - `warn`: Warning messages for potential issues
/// - `err`: Error messages for problems that need attention
pub const LogLevel = enum {
    debug,
    info,
    warn,
    err,
    
    pub fn toString(self: LogLevel) []const u8 {
        return switch (self) {
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
        };
    }
};

/// Optional context information for log events
///
/// Provides additional metadata about the context in which a log event
/// occurred. All fields are optional to allow flexible usage.
///
/// ## Example
/// ```zig
/// const context = LogContext{
///     .file_path = "src/main.zig",
///     .line = 42,
///     .operation = "memory_analysis",
/// };
/// ```
pub const LogContext = struct {
    /// File path being analyzed
    file_path: ?[]const u8 = null,
    
    /// Line number in source file
    line: ?u32 = null,
    
    /// Column number in source file  
    column: ?u32 = null,
    
    /// Analysis phase or operation
    operation: ?[]const u8 = null,
    
    /// Additional key-value pairs for custom data
    extra: ?std.json.Value = null,
};

/// Source location information
pub const SourceLocation = struct {
    file: []const u8,
    function: []const u8,
    line: u32,
};

/// Structured log event
///
/// Contains all information about a single log event. This structure
/// is passed to the log callback function.
///
/// ## Memory Management
/// The strings in LogEvent are owned by the logger and are only valid
/// during the callback execution. If you need to store them, make copies.
pub const LogEvent = struct {
    /// Timestamp in milliseconds since epoch
    timestamp: i64,
    
    /// Log severity level
    level: LogLevel,
    
    /// User-defined category string (e.g., "memory_analyzer", "testing_analyzer")
    category: []const u8,
    
    /// Log message
    message: []const u8,
    
    /// Optional context information
    context: ?LogContext = null,
    
    /// Optional source location (where the log was generated)
    source_location: ?SourceLocation = null,
};

/// Log event callback function type
///
/// User-provided function that handles log events. The callback
/// should be efficient as it may be called frequently during analysis.
///
/// ## Example
/// ```zig
/// fn myLogHandler(event: LogEvent) void {
///     const stderr = std.io.getStdErr().writer();
///     stderr.print("[{s}] {s}\n", .{ event.level.toString(), event.message }) catch {};
/// }
/// ```
///
/// ## Note
/// The callback must not call back into the analyzer to avoid recursion.
pub const LogCallback = *const fn (event: LogEvent) void;

/// Logging configuration
///
/// Controls whether and how logging is performed during analysis.
/// When enabled is false, no logging overhead is incurred.
///
/// ## Example
/// ```zig
/// const config = LoggingConfig{
///     .enabled = true,
///     .callback = stderrLogCallback,
///     .min_level = .warn,  // Only warnings and errors
/// };
/// ```
pub const LoggingConfig = struct {
    /// Enable or disable logging
    enabled: bool = false,
    
    /// Callback function to handle log events (required if enabled)
    callback: ?LogCallback = null,
    
    /// Minimum log level to emit (events below this level are filtered)
    min_level: LogLevel = .info,
};

/// Simple logger that uses callbacks
///
/// The Logger provides a lightweight logging interface that delegates
/// actual log handling to user-provided callbacks. This design allows
/// library users to integrate with their own logging systems.
///
/// ## Thread Safety
/// The logger itself is thread-safe for read operations. However,
/// the provided callback must handle its own thread safety if needed.
pub const Logger = struct {
    config: LoggingConfig,
    allocator: std.mem.Allocator,
    
    /// Initialize a new logger
    pub fn init(allocator: std.mem.Allocator, config: LoggingConfig) Logger {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }
    
    /// Check if logging is enabled and callback is set
    pub fn isEnabled(self: *const Logger) bool {
        return self.config.enabled and self.config.callback != null;
    }
    
    /// Check if a log level meets the minimum threshold
    pub fn shouldLog(self: *const Logger, level: LogLevel) bool {
        if (!self.isEnabled()) return false;
        return @intFromEnum(level) >= @intFromEnum(self.config.min_level);
    }
    
    /// Log an event
    pub fn log(
        self: *const Logger,
        level: LogLevel,
        category: []const u8,
        message: []const u8,
        context: ?LogContext,
    ) void {
        if (!self.shouldLog(level)) return;
        
        const event = LogEvent{
            .timestamp = std.time.milliTimestamp(),
            .level = level,
            .category = category,
            .message = message,
            .context = context,
            .source_location = null,
        };
        
        if (self.config.callback) |callback| {
            callback(event);
        }
    }
    
    /// Log with source location information
    pub fn logWithSource(
        self: *const Logger,
        level: LogLevel,
        category: []const u8,
        message: []const u8,
        context: ?LogContext,
        source_location: ?SourceLocation,
    ) void {
        if (!self.shouldLog(level)) return;
        
        const event = LogEvent{
            .timestamp = std.time.milliTimestamp(),
            .level = level,
            .category = category,
            .message = message,
            .context = context,
            .source_location = source_location,
        };
        
        if (self.config.callback) |callback| {
            callback(event);
        }
    }
    
    /// Convenience methods for common log levels
    pub fn debug(self: *const Logger, category: []const u8, message: []const u8, context: ?LogContext) void {
        self.log(.debug, category, message, context);
    }
    
    pub fn info(self: *const Logger, category: []const u8, message: []const u8, context: ?LogContext) void {
        self.log(.info, category, message, context);
    }
    
    pub fn warn(self: *const Logger, category: []const u8, message: []const u8, context: ?LogContext) void {
        self.log(.warn, category, message, context);
    }
    
    pub fn err(self: *const Logger, category: []const u8, message: []const u8, context: ?LogContext) void {
        self.log(.err, category, message, context);
    }
    
    /// Log with formatted message
    pub fn logFmt(
        self: *const Logger,
        level: LogLevel,
        category: []const u8,
        comptime fmt: []const u8,
        args: anytype,
        context: ?LogContext,
    ) void {
        if (!self.shouldLog(level)) return;
        
        const message = std.fmt.allocPrint(self.allocator, fmt, args) catch return;
        defer self.allocator.free(message);
        
        self.log(level, category, message, context);
    }
};

/// Example log callback that prints to stderr
///
/// A ready-to-use callback implementation that formats log events
/// and writes them to stderr. Useful for development and debugging.
///
/// ## Format
/// ```
/// [LEVEL] category: message
/// ```
///
/// ## Usage
/// ```zig
/// const config = LoggingConfig{
///     .enabled = true,
///     .callback = stderrLogCallback,
///     .min_level = .info,
/// };
/// ```
pub fn stderrLogCallback(event: LogEvent) void {
    const stderr = std.io.getStdErr().writer();
    
    // Format timestamp
    const timestamp_sec = @divFloor(event.timestamp, 1000);
    const timestamp_ms = @mod(event.timestamp, 1000);
    
    // Basic format: [TIMESTAMP] LEVEL [CATEGORY] MESSAGE
    stderr.print("[{d}.{d:0>3}] {s} [{s}] {s}", .{
        timestamp_sec,
        timestamp_ms,
        event.level.toString(),
        event.category,
        event.message,
    }) catch return;
    
    // Add context if present
    if (event.context) |ctx| {
        if (ctx.file_path) |path| {
            stderr.print(" (file: {s}", .{path}) catch return;
            if (ctx.line) |line| {
                stderr.print(":{d}", .{line}) catch return;
                if (ctx.column) |col| {
                    stderr.print(":{d}", .{col}) catch return;
                }
            }
            stderr.print(")", .{}) catch return;
        }
        if (ctx.operation) |op| {
            stderr.print(" [op: {s}]", .{op}) catch return;
        }
    }
    
    stderr.print("\n", .{}) catch return;
}

/// Example log callback that collects events in memory
pub fn createMemoryLogCallback(allocator: std.mem.Allocator) MemoryLogCollector {
    return MemoryLogCollector.init(allocator);
}

pub const MemoryLogCollector = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayList(LogEvent),
    
    pub fn init(allocator: std.mem.Allocator) MemoryLogCollector {
        return .{
            .allocator = allocator,
            .events = std.ArrayList(LogEvent).init(allocator),
        };
    }
    
    pub fn deinit(self: *MemoryLogCollector) void {
        self.events.deinit();
    }
    
    pub fn callback(self: *MemoryLogCollector) LogCallback {
        return &self.logEvent;
    }
    
    fn logEvent(ctx: *anyopaque, event: LogEvent) void {
        const self: *MemoryLogCollector = @ptrCast(@alignCast(ctx));
        self.events.append(event) catch return;
    }
    
    pub fn getEvents(self: *const MemoryLogCollector) []const LogEvent {
        return self.events.items;
    }
    
    pub fn clear(self: *MemoryLogCollector) void {
        self.events.clearRetainingCapacity();
    }
};

// Test helpers
var test_log_called: bool = false;
var test_last_event: ?LogEvent = null;

fn testLogCallback(event: LogEvent) void {
    test_log_called = true;
    test_last_event = event;
}

test "unit: Logger: basic functionality" {
    const testing = std.testing;
    
    // Reset test state
    test_log_called = false;
    test_last_event = null;
    
    const config = LoggingConfig{
        .enabled = true,
        .callback = testLogCallback,
        .min_level = .info,
    };
    
    const logger = Logger.init(testing.allocator, config);
    
    // Should log info level
    logger.info("test", "Info message", null);
    try testing.expect(test_log_called);
    try testing.expectEqual(LogLevel.info, test_last_event.?.level);
    try testing.expectEqualStrings("test", test_last_event.?.category);
    try testing.expectEqualStrings("Info message", test_last_event.?.message);
    
    // Should not log debug level (below min_level)
    test_log_called = false;
    logger.debug("test", "Debug message", null);
    try testing.expect(!test_log_called);
}

test "unit: Logger: with context" {
    const testing = std.testing;
    
    // Reset test state
    test_log_called = false;
    test_last_event = null;
    
    const config = LoggingConfig{
        .enabled = true,
        .callback = testLogCallback,
        .min_level = .debug,
    };
    
    const logger = Logger.init(testing.allocator, config);
    
    const context = LogContext{
        .file_path = "test.zig",
        .line = 42,
        .column = 15,
        .operation = "memory_check",
    };
    
    logger.warn("analyzer", "Found issue", context);
    
    try testing.expect(test_last_event != null);
    try testing.expect(test_last_event.?.context != null);
    try testing.expectEqualStrings("test.zig", test_last_event.?.context.?.file_path.?);
    try testing.expectEqual(@as(u32, 42), test_last_event.?.context.?.line.?);
    try testing.expectEqual(@as(u32, 15), test_last_event.?.context.?.column.?);
    try testing.expectEqualStrings("memory_check", test_last_event.?.context.?.operation.?);
}

test "unit: Logger: disabled functionality" {
    const testing = std.testing;
    
    // Reset test state
    test_log_called = false;
    test_last_event = null;
    
    // Logger disabled
    const config = LoggingConfig{
        .enabled = false,
        .callback = testLogCallback,
        .min_level = .debug,
    };
    
    const logger = Logger.init(testing.allocator, config);
    
    logger.err("test", "Error message", null);
    try testing.expect(!test_log_called);
}
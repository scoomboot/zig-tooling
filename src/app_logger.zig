const std = @import("std");
const time = std.time;
const fs = std.fs;

pub const AppLogLevel = enum {
    debug,
    info,
    warn,
    err,
    fatal,
};

pub const AppLogCategory = enum {
    simulation,
    api,
    database,
    data_import,
    performance,
    security,
    cache,
    export_data,
    validation,
    general,
    
    pub fn toString(self: AppLogCategory) []const u8 {
        return switch (self) {
            .simulation => "SIMULATION",
            .api => "API",
            .database => "DATABASE",
            .data_import => "DATA_IMPORT",
            .performance => "PERFORMANCE",
            .security => "SECURITY",
            .cache => "CACHE",
            .export_data => "EXPORT",
            .validation => "VALIDATION",
            .general => "GENERAL",
        };
    }
};

pub const LogContext = struct {
    request_id: ?[]const u8 = null,
    user_id: ?[]const u8 = null,
    game_id: ?[]const u8 = null,
    operation_type: ?[]const u8 = null,
    duration_ms: ?u64 = null,
    
    pub fn format(self: LogContext, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        
        var has_context = false;
        try writer.writeAll("[");
        
        if (self.request_id) |req_id| {
            try writer.print("req:{s}", .{req_id});
            has_context = true;
        }
        
        if (self.user_id) |user_id| {
            if (has_context) try writer.writeAll(",");
            try writer.print("user:{s}", .{user_id});
            has_context = true;
        }
        
        if (self.game_id) |game_id| {
            if (has_context) try writer.writeAll(",");
            try writer.print("game:{s}", .{game_id});
            has_context = true;
        }
        
        if (self.operation_type) |op_type| {
            if (has_context) try writer.writeAll(",");
            try writer.print("op:{s}", .{op_type});
            has_context = true;
        }
        
        if (self.duration_ms) |duration| {
            if (has_context) try writer.writeAll(",");
            try writer.print("dur:{d}ms", .{duration});
            has_context = true;
        }
        
        if (!has_context) {
            try writer.writeAll("no-context");
        }
        
        try writer.writeAll("]");
    }
};

pub const AppLogEntry = struct {
    timestamp: i64,
    level: AppLogLevel,
    category: AppLogCategory,
    message: []const u8,
    context: LogContext,
    source_location: ?[]const u8 = null,
    error_code: ?i32 = null,
    use_color: bool = true,
    
    pub fn format(self: AppLogEntry, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        
        // ANSI color codes
        const RESET = if (self.use_color) "\x1b[0m" else "";
        const GRAY = if (self.use_color) "\x1b[90m" else "";
        const CYAN = if (self.use_color) "\x1b[36m" else "";
        const YELLOW = if (self.use_color) "\x1b[33m" else "";
        const RED = if (self.use_color) "\x1b[31m" else "";
        const MAGENTA = if (self.use_color) "\x1b[35m" else "";
        const GREEN = if (self.use_color) "\x1b[32m" else "";
        const BRIGHT_RED = if (self.use_color) "\x1b[91m" else "";
        
        const level_text = switch (self.level) {
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
            .fatal => "FATAL",
        };
        
        const level_color = switch (self.level) {
            .debug => GRAY,
            .info => CYAN,
            .warn => YELLOW,
            .err => RED,
            .fatal => BRIGHT_RED,
        };
        
        // Format timestamp
        const dt = std.time.timestamp();
        const dt_str = try std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{dt});
        defer std.heap.page_allocator.free(dt_str);
        
        const category_str = self.category.toString();
        
        // Category colors
        const category_color = switch (self.category) {
            .api => GREEN,
            .database => YELLOW,
            .simulation => MAGENTA,
            .performance => CYAN,
            .security => BRIGHT_RED,
            else => GRAY,
        };
        
        // Format: [timestamp] LEVEL [CATEGORY] context source: message (error_code)
        try writer.print("{s}[{s}]{s} {s}{s}{s} {s}[{s}]{s} {}", 
            .{ GRAY, dt_str, RESET, level_color, level_text, RESET, category_color, category_str, RESET, self.context });
        
        if (self.source_location) |source| {
            try writer.print(" {s}{s}:{s}", .{GRAY, source, RESET});
        }
        
        try writer.print(" {s}", .{self.message});
        
        if (self.error_code) |code| {
            try writer.print(" {s}(code: {d}){s}", .{GRAY, code, RESET});
        }
        
        try writer.print("\n", .{});
    }
};

pub const LogStats = struct { 
    size: u64, 
    lines: usize, 
    archives: usize 
};

pub const AppLogger = struct {
    allocator: std.mem.Allocator,
    log_file_path: []const u8,
    max_log_size: usize = 10 * 1024 * 1024, // 10MB default
    max_archives: u8 = 5, // Keep 5 archived logs
    
    pub fn init(allocator: std.mem.Allocator, log_file_path: []const u8) AppLogger {
        return AppLogger{
            .allocator = allocator,
            .log_file_path = log_file_path,
        };
    }
    
    pub fn log(self: *AppLogger, level: AppLogLevel, category: AppLogCategory, message: []const u8, context: LogContext) !void {
        return self.logWithSource(level, category, message, context, null, null);
    }
    
    pub fn logWithSource(self: *AppLogger, level: AppLogLevel, category: AppLogCategory, message: []const u8, context: LogContext, source_location: ?[]const u8, error_code: ?i32) !void {
        // Check if log rotation is needed before writing
        try self.rotateIfNeeded();
        
        // Create entry without color for file
        var entry = AppLogEntry{
            .timestamp = time.timestamp(),
            .level = level,
            .category = category,
            .message = message,
            .context = context,
            .source_location = source_location,
            .error_code = error_code,
            .use_color = false,
        };
        
        // Write to file (without color)
        try self.writeToFile(entry);
        
        // Also write to stderr for immediate visibility of errors (with color)
        if (level == .err or level == .fatal) {
            entry.use_color = true;
            const stderr = std.io.getStdErr().writer();
            try stderr.print("{}", .{entry});
        }
    }
    
    fn writeToFile(self: *AppLogger, entry: AppLogEntry) !void {
        // Format the entire entry first to ensure atomic write
        var buffer: [4096]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buffer);
        try fbs.writer().print("{}", .{entry});
        const formatted = fbs.getWritten();
        
        // Open file in write mode - we'll use pwriteAll for atomic positioning
        const file = fs.cwd().openFile(self.log_file_path, .{ 
            .mode = .write_only,
        }) catch |err| switch (err) {
            error.FileNotFound => blk: {
                // Extract directory path from log file path
                const dir_end = std.mem.lastIndexOfScalar(u8, self.log_file_path, '/');
                if (dir_end) |end| {
                    const dir_path = self.log_file_path[0..end];
                    // Try to create the directory (will succeed if it already exists)
                    fs.cwd().makePath(dir_path) catch {};
                }
                
                // Create file if it doesn't exist
                const new_file = try fs.cwd().createFile(self.log_file_path, .{});
                new_file.close();
                // Re-open in write mode
                break :blk try fs.cwd().openFile(self.log_file_path, .{ 
                    .mode = .write_only,
                });
            },
            else => return err,
        };
        defer file.close();
        
        // Write atomically at end of file using pwriteAll
        const end_pos = try file.getEndPos();
        try file.pwriteAll(formatted, end_pos);
    }
    
    // Convenience methods for common logging patterns
    pub fn logInfo(self: *AppLogger, category: AppLogCategory, message: []const u8, context: LogContext) !void {
        try self.log(.info, category, message, context);
    }
    
    pub fn logWarn(self: *AppLogger, category: AppLogCategory, message: []const u8, context: LogContext) !void {
        try self.log(.warn, category, message, context);
    }
    
    pub fn logError(self: *AppLogger, category: AppLogCategory, message: []const u8, context: LogContext, error_code: ?i32) !void {
        try self.logWithSource(.err, category, message, context, null, error_code);
    }
    
    pub fn logDebug(self: *AppLogger, category: AppLogCategory, message: []const u8, context: LogContext) !void {
        try self.log(.debug, category, message, context);
    }
    
    pub fn logFatal(self: *AppLogger, category: AppLogCategory, message: []const u8, context: LogContext, error_code: ?i32) !void {
        try self.logWithSource(.fatal, category, message, context, null, error_code);
    }
    
    // API-specific logging methods
    pub fn logAPIRequest(self: *AppLogger, method: []const u8, uri: []const u8, request_id: []const u8, user_id: ?[]const u8) !void {
        const msg = try std.fmt.allocPrint(self.allocator, "API request: {s} {s}", .{ method, uri });
        defer self.allocator.free(msg);
        
        const context = LogContext{
            .request_id = request_id,
            .user_id = user_id,
            .operation_type = "api_request",
        };
        
        try self.log(.info, .api, msg, context);
    }
    
    pub fn logAPIResponse(self: *AppLogger, status_code: u16, request_id: []const u8, duration_ms: u64) !void {
        const msg = try std.fmt.allocPrint(self.allocator, "API response: {d}", .{status_code});
        defer self.allocator.free(msg);
        
        const context = LogContext{
            .request_id = request_id,
            .duration_ms = duration_ms,
            .operation_type = "api_response",
        };
        
        const level: AppLogLevel = if (status_code >= 500) .err else if (status_code >= 400) .warn else .info;
        try self.log(level, .api, msg, context);
    }
    
    // Simulation-specific logging methods
    pub fn logSimulationStart(self: *AppLogger, game_id: []const u8, teams: []const u8) !void {
        const msg = try std.fmt.allocPrint(self.allocator, "Simulation started: {s}", .{teams});
        defer self.allocator.free(msg);
        
        const context = LogContext{
            .game_id = game_id,
            .operation_type = "simulation_start",
        };
        
        try self.log(.info, .simulation, msg, context);
    }
    
    pub fn logSimulationEnd(self: *AppLogger, game_id: []const u8, duration_ms: u64, final_score: []const u8) !void {
        const msg = try std.fmt.allocPrint(self.allocator, "Simulation completed: {s}", .{final_score});
        defer self.allocator.free(msg);
        
        const context = LogContext{
            .game_id = game_id,
            .duration_ms = duration_ms,
            .operation_type = "simulation_end",
        };
        
        try self.log(.info, .simulation, msg, context);
    }
    
    // Database-specific logging methods
    pub fn logQueryExecution(self: *AppLogger, query_type: []const u8, duration_ms: u64, rows_affected: ?u64) !void {
        const msg = if (rows_affected) |rows|
            try std.fmt.allocPrint(self.allocator, "Query executed: {s} ({d} rows)", .{ query_type, rows })
        else
            try std.fmt.allocPrint(self.allocator, "Query executed: {s}", .{query_type});
        defer self.allocator.free(msg);
        
        const context = LogContext{
            .duration_ms = duration_ms,
            .operation_type = query_type,
        };
        
        const level: AppLogLevel = if (duration_ms > 1000) .warn else .debug;
        try self.log(level, .database, msg, context);
    }
    
    // Performance logging methods
    pub fn logPerformanceMetric(self: *AppLogger, metric_name: []const u8, value: f64, unit: []const u8, context: LogContext) !void {
        const msg = try std.fmt.allocPrint(self.allocator, "Performance metric: {s} = {d:.2} {s}", .{ metric_name, value, unit });
        defer self.allocator.free(msg);
        
        try self.log(.info, .performance, msg, context);
    }
    
    pub fn logPerformanceRegression(self: *AppLogger, metric_name: []const u8, old_value: f64, new_value: f64, threshold: f64) !void {
        const regression_pct = ((new_value - old_value) / old_value) * 100.0;
        const msg = try std.fmt.allocPrint(self.allocator, "Performance regression: {s} {d:.2} -> {d:.2} ({d:.1}% increase, threshold: {d:.1}%)", .{ metric_name, old_value, new_value, regression_pct, threshold });
        defer self.allocator.free(msg);
        
        const context = LogContext{
            .operation_type = "performance_regression",
        };
        
        try self.log(.warn, .performance, msg, context);
    }
    
    // Log management methods
    pub fn getLogStats(self: *AppLogger) !LogStats {
        var stats = LogStats{ .size = 0, .lines = 0, .archives = 0 };
        
        // Get current log file stats
        const file = fs.cwd().openFile(self.log_file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return stats,
            else => return err,
        };
        defer file.close();
        
        stats.size = try file.getEndPos();
        
        // Count lines
        const contents = try self.allocator.alloc(u8, @intCast(stats.size));
        defer self.allocator.free(contents);
        _ = try file.preadAll(contents, 0);
        
        var it = std.mem.tokenizeScalar(u8, contents, '\n');
        while (it.next()) |_| {
            stats.lines += 1;
        }
        
        // Count archives
        const dir_path = fs.path.dirname(self.log_file_path) orelse ".";
        const base_name = fs.path.basename(self.log_file_path);
        
        var dir = try fs.cwd().openDir(dir_path, .{ .iterate = true });
        defer dir.close();
        
        var dir_it = dir.iterate();
        while (try dir_it.next()) |entry| {
            if (entry.kind == .file and std.mem.startsWith(u8, entry.name, base_name) and std.mem.endsWith(u8, entry.name, ".archive")) {
                stats.archives += 1;
            }
        }
        
        return stats;
    }
    
    pub fn forceRotate(self: *AppLogger) !void {
        const file = fs.cwd().openFile(self.log_file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return, // Nothing to rotate
            else => return err,
        };
        file.close();
        
        try self.rotateLog();
    }
    
    pub fn readRecentLogs(self: *AppLogger, allocator: std.mem.Allocator, max_lines: usize) ![][]u8 {
        const file = fs.cwd().openFile(self.log_file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return &[_][]u8{},
            else => return err,
        };
        defer file.close();
        
        const file_size = try file.getEndPos();
        if (file_size == 0) return &[_][]u8{};
        
        const contents = try allocator.alloc(u8, file_size);
        defer allocator.free(contents);
        _ = try file.readAll(contents);
        
        var lines = std.ArrayList([]u8).init(allocator);
        defer lines.deinit();
        
        var it = std.mem.splitScalar(u8, contents, '\n');
        
        while (it.next()) |line| {
            if (line.len > 0) {
                const owned_line = try allocator.dupe(u8, line);
                errdefer allocator.free(owned_line);
                try lines.append(owned_line);
            }
        }
        
        const total_lines = lines.items.len;
        const start_idx = if (total_lines > max_lines) total_lines - max_lines else 0;
        
        const result = try allocator.alloc([]u8, total_lines - start_idx);
        errdefer allocator.free(result);
        for (lines.items[start_idx..], 0..) |line, i| {
            result[i] = line;
        }
        
        // Free the lines that we're not returning
        for (lines.items[0..start_idx]) |line| {
            allocator.free(line);
        }
        
        return result;
    }
    
    pub fn clearLogs(self: *AppLogger) !void {
        const file = fs.cwd().createFile(self.log_file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        file.close();
    }
    
    fn rotateIfNeeded(self: *AppLogger) !void {
        const file = fs.cwd().openFile(self.log_file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return, // No file to rotate
            else => return err,
        };
        defer file.close();
        
        const file_size = try file.getEndPos();
        if (file_size >= self.max_log_size) {
            try self.rotateLog();
        }
    }
    
    fn rotateLog(self: *AppLogger) !void {
        // Generate archive filename with timestamp
        const timestamp = time.timestamp();
        const archive_name = try std.fmt.allocPrint(self.allocator, "{s}.{d}.archive", .{ self.log_file_path, timestamp });
        defer self.allocator.free(archive_name);
        
        // Rename current log to archive
        try fs.cwd().rename(self.log_file_path, archive_name);
        
        // Clean up old archives
        try self.cleanupOldArchives();
    }
    
    fn cleanupOldArchives(self: *AppLogger) !void {
        const dir_path = fs.path.dirname(self.log_file_path) orelse ".";
        const base_name = fs.path.basename(self.log_file_path);
        
        var archives = std.ArrayList([]const u8).init(self.allocator);
        defer {
            for (archives.items) |archive| {
                self.allocator.free(archive);
            }
            archives.deinit();
        }
        
        // Find all archive files
        var dir = try fs.cwd().openDir(dir_path, .{ .iterate = true });
        defer dir.close();
        
        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind == .file and std.mem.startsWith(u8, entry.name, base_name) and std.mem.endsWith(u8, entry.name, ".archive")) {
                const owned_name = try self.allocator.dupe(u8, entry.name);
                errdefer self.allocator.free(owned_name);
                try archives.append(owned_name);
            }
        }
        
        // Sort archives by name (timestamp is in the name)
        std.mem.sort([]const u8, archives.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.order(u8, a, b) == .lt;
            }
        }.lessThan);
        
        // Delete oldest archives if we exceed max_archives
        if (archives.items.len > self.max_archives) {
            const to_delete = archives.items.len - self.max_archives;
            for (archives.items[0..to_delete]) |archive| {
                const full_path = try fs.path.join(self.allocator, &[_][]const u8{ dir_path, archive });
                defer self.allocator.free(full_path);
                fs.cwd().deleteFile(full_path) catch |err| {
                    // Log deletion failure but don't fail the operation
                    // TODO: Consider proper error handling for library usage (LC012)
                    _ = err;
                };
            }
        }
    }
};

// Utility function to get the default application logger
pub fn getDefaultAppLogger(allocator: std.mem.Allocator) AppLogger {
    return AppLogger.init(allocator, "../logs/app.log");
}

// Test the application logger
test "unit: app logger basic functionality" {
    var logger = AppLogger.init(std.testing.allocator, "test_app.log");
    
    const context = LogContext{
        .request_id = "req-123",
        .operation_type = "test",
    };
    
    try logger.logInfo(.general, "Application started", context);
    try logger.logWarn(.performance, "High memory usage detected", context);
    try logger.logError(.database, "Connection failed", context, 500);
    
    // Clean up test file
    fs.cwd().deleteFile("test_app.log") catch {};
}

test "integration: app logger api logging" {
    var logger = AppLogger.init(std.testing.allocator, "test_api.log");
    
    try logger.logAPIRequest("GET", "/api/v1/stats", "req-456", "user-789");
    try logger.logAPIResponse(200, "req-456", 45);
    try logger.logAPIResponse(500, "req-457", 120);
    
    // Clean up test file
    fs.cwd().deleteFile("test_api.log") catch {};
}

test "simulation: app logger simulation logging" {
    var logger = AppLogger.init(std.testing.allocator, "test_sim.log");
    
    try logger.logSimulationStart("game-123", "Team A vs Team B");
    try logger.logSimulationEnd("game-123", 1500, "Team A 21 - Team B 14");
    
    // Clean up test file
    fs.cwd().deleteFile("test_sim.log") catch {};
}
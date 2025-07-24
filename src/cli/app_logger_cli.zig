const std = @import("std");
const zig_tooling = @import("zig_tooling");
const AppLogger = zig_tooling.app_logger.AppLogger;
const AppLogLevel = zig_tooling.app_logger.AppLogLevel;
const AppLogCategory = zig_tooling.app_logger.AppLogCategory;
const LogContext = zig_tooling.app_logger.LogContext;
const config = zig_tooling.config;
const config_loader = zig_tooling.config_loader;
const print = std.debug.print;

var tool_config: ?config.ToolConfig = null;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printHelp();
        return;
    }

    // Load configuration
    var cfg_loader = config_loader.ConfigLoader.init(allocator);
    tool_config = try cfg_loader.loadConfig();
    defer if (tool_config) |*tc| tc.deinit();
    
    // Check for --config flag and filter args
    var filtered_args = std.ArrayList([:0]u8).init(allocator);
    defer filtered_args.deinit();
    var custom_config_path: ?[]const u8 = null;
    
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--config") and i + 1 < args.len) {
            custom_config_path = args[i + 1];
            i += 1; // Skip the config path
        } else {
            try filtered_args.append(args[i]);
        }
    }
    
    // Load custom config if specified
    if (custom_config_path) |path| {
        cfg_loader.loadFromFile(&tool_config.?, path) catch |err| {
            print("Error loading config from {s}: {}\n", .{path, err});
            return err;
        };
    }
    
    // Use filtered args for command parsing
    const filtered_items = filtered_args.items;
    if (filtered_items.len < 2) {
        try printHelp();
        return;
    }
    
    const command = filtered_items[1];
    
    if (std.mem.eql(u8, command, "stats")) {
        try runLogStats(allocator, filtered_items[2..]);
    } else if (std.mem.eql(u8, command, "tail")) {
        try runLogTail(allocator, filtered_items[2..]);
    } else if (std.mem.eql(u8, command, "rotate")) {
        try runLogRotate(allocator, filtered_items[2..]);
    } else if (std.mem.eql(u8, command, "clear")) {
        try runLogClear(allocator, filtered_items[2..]);
    } else if (std.mem.eql(u8, command, "test")) {
        try runLogTest(allocator, filtered_items[2..]);
    } else if (std.mem.eql(u8, command, "config")) {
        try runConfigCommand(allocator, filtered_items[2..], &cfg_loader);
    } else if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        try printHelp();
    } else {
        print("Unknown command: {s}\n", .{command});
        try printHelp();
    }
}

fn runLogStats(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    const default_path = if (tool_config) |tc| tc.global.log_path orelse "logs/app.log" else "logs/app.log";
    const log_path = if (args.len > 0) args[0] else default_path;
    
    print("📊 Application Log Statistics\n", .{});
    print("=============================\n\n", .{});
    
    var logger = AppLogger.init(allocator, log_path);
    const stats = logger.getLogStats() catch |err| {
        print("Error getting log stats: {}\n", .{err});
        return;
    };
    
    print("Log file: {s}\n", .{log_path});
    print("Size: {d} bytes\n", .{stats.size});
    print("Lines: {d}\n", .{stats.lines});
    print("Archives: {d}\n", .{stats.archives});
    
    // Convert size to human-readable format
    const size_mb = @as(f64, @floatFromInt(stats.size)) / (1024.0 * 1024.0);
    if (size_mb > 1.0) {
        print("Size (MB): {d:.2}\n", .{size_mb});
    }
}

fn runLogTail(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    const default_path = if (tool_config) |tc| tc.global.log_path orelse "logs/app.log" else "logs/app.log";
    const log_path = if (args.len > 0) args[0] else default_path;
    const max_lines: usize = if (args.len > 1) 
        std.fmt.parseInt(usize, args[1], 10) catch 20 
    else 
        20;
    
    print("📖 Recent Log Entries (last {d} lines)\n", .{max_lines});
    print("=======================================\n\n", .{});
    
    var logger = AppLogger.init(allocator, log_path);
    const lines = logger.readRecentLogs(allocator, max_lines) catch |err| {
        print("Error reading logs: {}\n", .{err});
        return;
    };
    defer {
        for (lines) |line| {
            allocator.free(line);
        }
        allocator.free(lines);
    }
    
    // Color codes for terminal output
    const RESET = "\x1b[0m";
    const GRAY = "\x1b[90m";
    const CYAN = "\x1b[36m";
    const YELLOW = "\x1b[33m";
    const RED = "\x1b[31m";
    const BRIGHT_RED = "\x1b[91m";
    
    for (lines) |line| {
        // Check log level and colorize
        if (std.mem.indexOf(u8, line, " ERROR ") != null) {
            print("{s}{s}{s}", .{RED, line, RESET});
        } else if (std.mem.indexOf(u8, line, " FATAL ") != null) {
            print("{s}{s}{s}", .{BRIGHT_RED, line, RESET});
        } else if (std.mem.indexOf(u8, line, " WARN ") != null) {
            print("{s}{s}{s}", .{YELLOW, line, RESET});
        } else if (std.mem.indexOf(u8, line, " INFO ") != null) {
            print("{s}{s}{s}", .{CYAN, line, RESET});
        } else if (std.mem.indexOf(u8, line, " DEBUG ") != null) {
            print("{s}{s}{s}", .{GRAY, line, RESET});
        } else {
            print("{s}", .{line});
        }
    }
}

fn runLogRotate(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    const default_path = if (tool_config) |tc| tc.global.log_path orelse "logs/app.log" else "logs/app.log";
    const log_path = if (args.len > 0) args[0] else default_path;
    
    print("🔄 Rotating Log Files\n", .{});
    print("====================\n\n", .{});
    
    var logger = AppLogger.init(allocator, log_path);
    logger.forceRotate() catch |err| {
        print("Error rotating logs: {}\n", .{err});
        return;
    };
    
    print("Log rotation completed successfully.\n", .{});
    print("Log file: {s}\n", .{log_path});
}

fn runLogClear(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    const default_path = if (tool_config) |tc| tc.global.log_path orelse "logs/app.log" else "logs/app.log";
    const log_path = if (args.len > 0) args[0] else default_path;
    
    print("🗑️  Clearing Log Files\n", .{});
    print("======================\n\n", .{});
    print("Are you sure you want to clear all logs? This cannot be undone. (y/N): ", .{});
    
    // Read user confirmation
    const stdin = std.io.getStdIn().reader();
    var buf: [10]u8 = undefined;
    if (try stdin.readUntilDelimiterOrEof(buf[0..], '\n')) |input| {
        const trimmed = std.mem.trim(u8, input, " \t\r\n");
        if (std.mem.eql(u8, trimmed, "y") or std.mem.eql(u8, trimmed, "Y")) {
            var logger = AppLogger.init(allocator, log_path);
            logger.clearLogs() catch |err| {
                print("Error clearing logs: {}\n", .{err});
                return;
            };
            print("All logs cleared successfully.\n", .{});
        } else {
            print("Operation cancelled.\n", .{});
        }
    }
}

fn runLogTest(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    const default_path = if (tool_config) |tc| tc.global.log_path orelse "logs/app.log" else "logs/app.log";
    const log_path = if (args.len > 0) args[0] else default_path;
    
    print("🧪 Testing Application Logger\n", .{});
    print("=============================\n\n", .{});
    
    // Ensure logs directory exists
    std.fs.cwd().makeDir("logs") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    
    var logger = AppLogger.init(allocator, log_path);
    
    print("Writing test log entries...\n", .{});
    
    // Test different log levels and categories
    const context = LogContext{ .request_id = "test-123", .operation_type = "cli-test" };
    
    try logger.logInfo(.general, "CLI test started", context);
    try logger.logDebug(.validation, "Testing debug level logging", context);
    try logger.logWarn(.performance, "Testing warning level logging", context);
    try logger.logError(.api, "Testing error level logging", context, 404);
    
    // Test specialized logging methods
    try logger.logAPIRequest("GET", "/test", "test-123", "cli-user");
    try logger.logAPIResponse(200, "test-123", 150);
    try logger.logQueryExecution("SELECT", 25, 100);
    try logger.logPerformanceMetric("test_metric", 1.23, "ms", context);
    
    print("Test entries written successfully.\n", .{});
    print("Log file: {s}\n", .{log_path});
    
    // Show stats after test
    const stats = logger.getLogStats() catch |err| {
        print("Error getting post-test stats: {}\n", .{err});
        return;
    };
    
    print("\nPost-test statistics:\n", .{});
    print("Size: {d} bytes, Lines: {d}\n", .{ stats.size, stats.lines });
}

fn runConfigCommand(allocator: std.mem.Allocator, args: [][:0]u8, loader: *config_loader.ConfigLoader) !void {
    _ = allocator;
    if (args.len == 0) {
        print("Error: config subcommand required (show, init, validate)\n", .{});
        return;
    }
    
    const subcommand = args[0];
    
    if (std.mem.eql(u8, subcommand, "show")) {
        if (tool_config) |tc| {
            print("Current Configuration:\n", .{});
            print("===================\n\n", .{});
            
            print("Global:\n", .{});
            print("  Log Path: {s}\n", .{tc.global.log_path orelse "(default)"});
            print("  Output Format: {s}\n", .{tc.global.output_format});
            print("  Color Output: {}\n", .{tc.global.color_output});
            print("  Verbosity: {d}\n\n", .{tc.global.verbosity});
            
            print("Logger:\n", .{});
            print("  Max Log Size MB: {d}\n", .{tc.logger.max_log_size_mb});
            print("  Max Archives: {d}\n", .{tc.logger.max_archives});
            print("  Performance Warn Threshold MS: {d}\n", .{tc.logger.performance_warn_threshold_ms});
            print("  Log Level: {s}\n", .{tc.logger.log_level});
            print("  Include Timestamps: {}\n", .{tc.logger.include_timestamps});
            print("  Archive Compression: {s}\n", .{tc.logger.archive_compression});
        } else {
            print("No configuration loaded\n", .{});
        }
    } else if (std.mem.eql(u8, subcommand, "init")) {
        const config_path = if (args.len > 1) args[1] else ".zigtools.json";
        loader.createDefaultConfig(config_path) catch |err| {
            print("Error creating config file: {}\n", .{err});
            return err;
        };
        print("Created default configuration at: {s}\n", .{config_path});
    } else if (std.mem.eql(u8, subcommand, "validate")) {
        const config_path = if (args.len > 1) args[1] else ".zigtools.json";
        loader.validateConfig(config_path) catch |err| {
            print("Configuration validation failed: {}\n", .{err});
            return err;
        };
        print("Configuration is valid: {s}\n", .{config_path});
    } else {
        print("Unknown config subcommand: {s}\n", .{subcommand});
        print("Valid subcommands: show, init, validate\n", .{});
    }
}

fn printHelp() !void {
    print("App Logger CLI Tool\n", .{});
    print("===================\n\n", .{});
    print("A command-line interface for managing application logs in the NFL Simulation engine.\n\n", .{});
    print("USAGE:\n", .{});
    print("    app_logger_cli <COMMAND> [OPTIONS]\n\n", .{});
    print("COMMANDS:\n", .{});
    print("    stats [LOG_PATH]           Show log file statistics\n", .{});
    print("    tail [LOG_PATH] [LINES]    Show recent log entries (default: 20 lines)\n", .{});
    print("    rotate [LOG_PATH]          Force log rotation\n", .{});
    print("    clear [LOG_PATH]           Clear all log files (with confirmation)\n", .{});
    print("    test [LOG_PATH]            Write test entries and validate logging system\n", .{});
    print("    config <subcmd>            Manage configuration (show, init, validate)\n", .{});
    print("    help                       Show this help message\n\n", .{});
    print("OPTIONS:\n", .{});
    print("    LOG_PATH                   Path to log file (default: logs/app.log)\n", .{});
    print("    LINES                      Number of lines to show with tail command\n", .{});
    print("    --config <path>            Use custom configuration file (default: .zigtools.json)\n\n", .{});
    print("EXAMPLES:\n", .{});
    print("    app_logger_cli stats                    # Show default log stats\n", .{});
    print("    app_logger_cli tail logs/app.log 50     # Show last 50 lines\n", .{});
    print("    app_logger_cli rotate                   # Rotate current log\n", .{});
    print("    app_logger_cli test                     # Test logging functionality\n\n", .{});
    print("NOTE:\n", .{});
    print("    Default log directory is 'logs/' (current working directory).\n", .{});
    print("    The tool will create the logs directory if it doesn't exist.\n", .{});
}
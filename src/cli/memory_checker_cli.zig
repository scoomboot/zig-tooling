const std = @import("std");
const zig_tooling = @import("zig_tooling");
const MemoryAnalyzer = zig_tooling.memory_analyzer.MemoryAnalyzer;
const AppLogger = zig_tooling.app_logger.AppLogger;
const LogContext = zig_tooling.app_logger.LogContext;
const print = std.debug.print;

var output_json = false;

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

    // Check for --json flag before logger init
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--json")) {
            output_json = true;
            break;
        }
    }

    // Get log path from environment or use default
    const log_path = std.process.getEnvVarOwned(allocator, "ZIG_TOOLING_LOG_PATH") catch try allocator.dupe(u8, "logs/app.log");
    defer allocator.free(log_path);
    
    // Ensure logs directory exists
    const log_dir = std.fs.path.dirname(log_path) orelse "logs";
    try std.fs.cwd().makePath(log_dir);
    
    // Initialize modern logger
    var app_logger = AppLogger.init(allocator, log_path);

    const command = args[1];
    
    // Log tool start with proper category
    if (!output_json) {
        const context = LogContext{ .operation_type = command };
        try app_logger.logInfo(.validation, "Memory Checker started", context);
    }
    
    if (std.mem.eql(u8, command, "check")) {
        try runMemoryCheck(allocator, args[2..], &app_logger);
    } else if (std.mem.eql(u8, command, "scan")) {
        try runProjectScan(allocator, args[2..], &app_logger);
    } else if (std.mem.eql(u8, command, "file")) {
        if (args.len < 3) {
            print("Error: file path required\n", .{});
            try printHelp();
            return;
        }
        try runSingleFileCheck(allocator, args[2], &app_logger);
    } else if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        try printHelp();
    } else {
        print("Unknown command: {s}\n", .{command});
        try printHelp();
    }
}

fn runMemoryCheck(allocator: std.mem.Allocator, paths: [][:0]u8, logger: *AppLogger) !void {
    if (!output_json) {
        print("🔍 Running Memory Management Check\n", .{});
        print("===================================\n\n", .{});
    }
    
    const start_time = std.time.milliTimestamp();
    
    if (paths.len == 0) {
        // Default to checking current directory
        var default_args = [_][:0]u8{@constCast(".")};
        try runProjectScan(allocator, &default_args, logger);
        return;
    }
    
    var analyzer = MemoryAnalyzer.init(allocator);
    defer analyzer.deinit();
    
    var total_files: u32 = 0;
    var total_issues: u32 = 0;
    
    for (paths) |path| {
        if (std.fs.path.extension(path).len > 0 and std.mem.eql(u8, std.fs.path.extension(path), ".zig")) {
            // Single file
            if (!output_json) {
                print("Analyzing: {s}\n", .{path});
                const file_context = LogContext{ 
                    .operation_type = "analyze_file",
                    .request_id = path
                };
                try logger.logDebug(.validation, "Analyzing single file for memory patterns", file_context);
            }
            try analyzer.analyzeFile(path);
            total_files += 1;
        } else {
            // Directory
            const files_processed = try scanDirectory(allocator, &analyzer, path, logger);
            total_files += files_processed;
        }
    }
    
    total_issues = @intCast(analyzer.getIssues().len);
    
    if (!output_json) {
        print("\n", .{});
        analyzer.printReport();
        
        print("\n📊 Analysis Summary\n", .{});
        print("=================\n", .{});
        print("Files analyzed: {d}\n", .{total_files});
        print("Issues found: {d}\n", .{total_issues});
    }
    
    const duration_ms = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
    
    if (analyzer.hasErrors()) {
        if (!output_json) {
            print("\n❌ MEMORY CHECK FAILED\n", .{});
            print("Please fix the errors above before proceeding.\n", .{});
            
            const context = LogContext{ 
                .operation_type = "memory_check_complete",
                .duration_ms = duration_ms
            };
            const msg = try std.fmt.allocPrint(allocator, "Memory check failed with {d} issues in {d} files", .{total_issues, total_files});
            defer allocator.free(msg);
            try logger.logError(.validation, msg, context, @intCast(total_issues));
        }
        std.process.exit(1);
    } else {
        if (!output_json) {
            print("\n✅ MEMORY CHECK PASSED\n", .{});
            print("All files follow memory management best practices.\n", .{});
            
            const context = LogContext{ 
                .operation_type = "memory_check_complete",
                .duration_ms = duration_ms
            };
            const msg = try std.fmt.allocPrint(allocator, "Memory check passed: analyzed {d} files", .{total_files});
            defer allocator.free(msg);
            try logger.logInfo(.validation, msg, context);
        }
    }
}

fn runProjectScan(allocator: std.mem.Allocator, args: [][:0]u8, logger: *AppLogger) !void {
    const scan_path = if (args.len > 0) args[0] else ".";
    
    if (!output_json) {
        print("🔍 Scanning project for memory management issues\n", .{});
        print("================================================\n", .{});
        print("Scan path: {s}\n\n", .{scan_path});
    }
    
    const start_time = std.time.milliTimestamp();
    const context = LogContext{ 
        .operation_type = "project_scan",
        .request_id = scan_path
    };
    if (!output_json) {
        try logger.logInfo(.validation, "Starting project memory scan", context);
    }
    
    var analyzer = MemoryAnalyzer.init(allocator);
    defer analyzer.deinit();
    
    const files_processed = try scanDirectory(allocator, &analyzer, scan_path, logger);
    
    print("\n", .{});
    analyzer.printReport();
    
    print("\n📊 Project Scan Summary\n", .{});
    print("======================\n", .{});
    print("Files analyzed: {d}\n", .{files_processed});
    print("Issues found: {d}\n", .{analyzer.getIssues().len});
    
    const duration_ms = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
    const issues = analyzer.getIssues();
    
    if (analyzer.hasErrors()) {
        if (!output_json) {
            print("\n❌ PROJECT MEMORY CHECK FAILED\n", .{});
            print("Critical memory management issues found.\n", .{});
            
            const fail_context = LogContext{ 
                .operation_type = "project_scan_complete",
                .request_id = scan_path,
                .duration_ms = duration_ms
            };
            const msg = try std.fmt.allocPrint(allocator, "Project scan failed: {d} issues in {d} files", .{issues.len, files_processed});
            defer allocator.free(msg);
            try logger.logError(.validation, msg, fail_context, @intCast(issues.len));
        }
        std.process.exit(1);
    } else if (issues.len > 0) {
        if (!output_json) {
            print("\n⚠️  PROJECT MEMORY CHECK PASSED WITH WARNINGS\n", .{});
            print("Consider addressing the warnings above.\n", .{});
            
            const warn_context = LogContext{ 
                .operation_type = "project_scan_complete",
                .request_id = scan_path,
                .duration_ms = duration_ms
            };
            const msg = try std.fmt.allocPrint(allocator, "Project scan completed with warnings: {d} issues in {d} files", .{issues.len, files_processed});
            defer allocator.free(msg);
            try logger.logWarn(.validation, msg, warn_context);
        }
    } else {
        if (!output_json) {
            print("\n✅ PROJECT MEMORY CHECK PASSED\n", .{});
            print("All project files follow memory management best practices.\n", .{});
            
            const pass_context = LogContext{ 
                .operation_type = "project_scan_complete",
                .request_id = scan_path,
                .duration_ms = duration_ms
            };
            const msg = try std.fmt.allocPrint(allocator, "Project scan passed: {d} files analyzed", .{files_processed});
            defer allocator.free(msg);
            try logger.logInfo(.validation, msg, pass_context);
        }
    }
}

fn runSingleFileCheck(allocator: std.mem.Allocator, file_path: []const u8, logger: *AppLogger) !void {
    if (!output_json) {
        print("🔍 Checking single file: {s}\n", .{file_path});
        print("=====================================\n\n", .{});
    }
    
    const start_time = std.time.milliTimestamp();
    const context = LogContext{ 
        .operation_type = "single_file_check",
        .request_id = file_path
    };
    if (!output_json) {
        try logger.logInfo(.validation, "Checking single file for memory patterns", context);
    }
    
    var analyzer = MemoryAnalyzer.init(allocator);
    defer analyzer.deinit();
    
    analyzer.analyzeFile(file_path) catch |err| {
        if (!output_json) {
            print("❌ Error analyzing file: {}\n", .{err});
            
            const err_context = LogContext{ 
                .operation_type = "file_analysis_error",
                .request_id = file_path
            };
            const msg = try std.fmt.allocPrint(allocator, "Failed to analyze file: {}", .{err});
            defer allocator.free(msg);
            try logger.logError(.validation, msg, err_context, null);
        } else {
            print("{{\"error\": \"Failed to analyze file: {}\", \"file\": \"{s}\"}}", .{err, file_path});
        }
        std.process.exit(1);
    };
    
    if (!output_json) {
        analyzer.printReport();
    }
    
    const duration_ms = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
    const issues = analyzer.getIssues();
    
    if (analyzer.hasErrors()) {
        if (!output_json) {
            print("\n❌ FILE MEMORY CHECK FAILED\n", .{});
            
            const fail_context = LogContext{ 
                .operation_type = "file_check_complete",
                .request_id = file_path,
                .duration_ms = duration_ms
            };
            const msg = try std.fmt.allocPrint(allocator, "File check failed with {d} issues", .{issues.len});
            defer allocator.free(msg);
            try logger.logError(.validation, msg, fail_context, @intCast(issues.len));
        } else {
            print("{{\"file\": \"{s}\", \"issues_found\": {d}, \"has_errors\": true}}", .{file_path, issues.len});
        }
        std.process.exit(1);
    } else {
        if (!output_json) {
            print("\n✅ FILE MEMORY CHECK PASSED\n", .{});
            
            const pass_context = LogContext{ 
                .operation_type = "file_check_complete",
                .request_id = file_path,
                .duration_ms = duration_ms
            };
            const msg = if (issues.len > 0)
                try std.fmt.allocPrint(allocator, "File check passed with {d} warnings", .{issues.len})
            else
                try std.fmt.allocPrint(allocator, "File check passed with no issues", .{});
            defer allocator.free(msg);
            
            if (issues.len > 0) {
                try logger.logWarn(.validation, msg, pass_context);
            } else {
                try logger.logInfo(.validation, msg, pass_context);
            }
        } else {
            print("{{\"file\": \"{s}\", \"issues_found\": {d}, \"has_errors\": false}}", .{file_path, issues.len});
        }
    }
}

fn scanDirectory(allocator: std.mem.Allocator, analyzer: *MemoryAnalyzer, dir_path: []const u8, logger: *AppLogger) !u32 {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => {
            print("Warning: Directory not found: {s}\n", .{dir_path});
            return 0;
        },
        error.AccessDenied => {
            print("Warning: Access denied to directory: {s}\n", .{dir_path});
            return 0;
        },
        else => return err,
    };
    defer dir.close();
    
    var files_processed: u32 = 0;
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    
    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        
        // Only process .zig files
        if (!std.mem.endsWith(u8, entry.path, ".zig")) continue;
        
        // Skip test files and generated files if desired
        if (shouldSkipFile(entry.path)) continue;
        
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.path });
        defer allocator.free(full_path);
        
        if (!output_json) {
            print("  Analyzing: {s}\n", .{entry.path});
        }
        
        analyzer.analyzeFile(full_path) catch |err| {
            if (!output_json) {
                print("    Warning: Failed to analyze {s}: {}\n", .{entry.path, err});
                
                const err_context = LogContext{ 
                    .operation_type = "file_scan_error",
                    .request_id = entry.path
                };
                const msg = try std.fmt.allocPrint(allocator, "Failed to analyze file during scan: {}", .{err});
                defer allocator.free(msg);
                logger.logWarn(.validation, msg, err_context) catch {};
            }
            continue;
        };
        
        files_processed += 1;
    }
    
    return files_processed;
}

fn shouldSkipFile(file_path: []const u8) bool {
    // Skip common files that don't need memory analysis or are generated
    const skip_patterns = [_][]const u8{
        "test_", 
        ".test.zig",
        "generated_",
        "build_runner.zig",
    };
    
    for (skip_patterns) |pattern| {
        if (std.mem.indexOf(u8, file_path, pattern) != null) {
            return true;
        }
    }
    
    return false;
}

fn printHelp() !void {
    print(
        \\Memory Management Checker - NFL Simulation Project
        \\
        \\Usage: memory_checker_cli [COMMAND] [OPTIONS]
        \\
        \\Commands:
        \\  check [paths...]     Check memory management in specified files/directories
        \\                       (defaults to current directory if no paths given)
        \\  scan [path]          Scan entire project directory for memory issues
        \\                       (defaults to current directory)
        \\  file <path>          Check a single specific file
        \\  help, --help, -h     Show this help message
        \\
        \\Examples:
        \\  memory_checker_cli check                     # Check current directory
        \\  memory_checker_cli check src/               # Check src directory
        \\  memory_checker_cli check src/ tests/        # Check multiple directories
        \\  memory_checker_cli file src/main.zig        # Check single file
        \\  memory_checker_cli scan                      # Scan entire project
        \\  memory_checker_cli scan /path/to/project     # Scan specific project
        \\
        \\Memory Management Checks:
        \\  ✓ Allocations have corresponding defer cleanup
        \\  ✓ Arena allocators are properly deinitialized
        \\  ✓ Error handling includes errdefer cleanup
        \\  ✓ Allocator choice matches component strategy
        \\  ✓ No potential memory leaks in loops
        \\
        \\Exit Codes:
        \\  0 - All checks passed (may have warnings)
        \\  1 - Critical memory management errors found
        \\
        \\Integration:
        \\  This tool can be used as a slash command in development workflows:
        \\  /check-memory-management
        \\
        \\For more information about memory management strategy, see:
        \\  sim-engine/docs/archive/MEMORY-MANAGEMENT-STRATEGY.md
        \\
    , .{});
}

// Slash command integration helper
pub fn slashCommandHelp() void {
    print(
        \\📋 /check-memory-management - Memory Management Validation
        \\
        \\Validates that all Zig code follows the established memory management strategy.
        \\
        \\What it checks:
        \\  • Every allocation has corresponding cleanup (defer/errdefer)
        \\  • Arena allocators are properly deinitialized
        \\  • Allocator choice matches component guidelines
        \\  • Error handling includes memory cleanup
        \\
        \\Usage in todo lists and migration plans:
        \\  Add "/check-memory-management" at the end of implementation phases
        \\  to ensure memory safety compliance before marking tasks complete.
        \\
        \\Exit behavior:
        \\  • Returns 0 if no critical errors (may have warnings)
        \\  • Returns 1 if critical memory issues found
        \\  • Prevents proceeding with unsafe memory patterns
        \\
    , .{});
}
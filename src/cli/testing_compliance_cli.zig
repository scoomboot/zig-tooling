const std = @import("std");
const zig_tooling = @import("zig_tooling");
const TestingAnalyzer = zig_tooling.testing_analyzer.TestingAnalyzer;
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
        try app_logger.logInfo(.validation, "Testing Compliance Checker started", context);
    }
    
    if (std.mem.eql(u8, command, "check")) {
        try runTestingCheck(allocator, args[2..], &app_logger);
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

fn runTestingCheck(allocator: std.mem.Allocator, paths: [][:0]u8, logger: *AppLogger) !void {
    if (!output_json) {
        print("🔍 Running Testing Compliance Check\n", .{});
        print("===================================\n\n", .{});
    }
    
    const start_time = std.time.milliTimestamp();
    
    if (paths.len == 0) {
        // Default to checking current directory
        var default_args = [_][:0]u8{@constCast(".")};
        try runProjectScan(allocator, &default_args, logger);
        return;
    }
    
    var analyzer = TestingAnalyzer.init(allocator);
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
                try logger.logDebug(.validation, "Analyzing file for testing compliance", file_context);
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
    } else {
        // JSON output for CI/CD
        print("{{\"files_analyzed\": {d}, \"issues_found\": {d}, \"has_errors\": {}}}", .{total_files, total_issues, analyzer.hasErrors()});
    }
    
    const duration_ms = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
    
    if (analyzer.hasErrors()) {
        if (!output_json) {
            print("\n❌ TESTING COMPLIANCE CHECK FAILED\n", .{});
            print("Please fix the errors above before proceeding.\n", .{});
            
            const context = LogContext{ 
                .operation_type = "testing_check_complete",
                .duration_ms = duration_ms
            };
            const msg = try std.fmt.allocPrint(allocator, "Testing compliance check failed with {d} issues in {d} files", .{total_issues, total_files});
            defer allocator.free(msg);
            try logger.logError(.validation, msg, context, @intCast(total_issues));
        }
        std.process.exit(1);
    } else {
        if (!output_json) {
            print("\n✅ TESTING COMPLIANCE CHECK PASSED\n", .{});
            print("All files follow testing strategy best practices.\n", .{});
            
            const context = LogContext{ 
                .operation_type = "testing_check_complete",
                .duration_ms = duration_ms
            };
            const msg = try std.fmt.allocPrint(allocator, "Testing compliance check passed: analyzed {d} files", .{total_files});
            defer allocator.free(msg);
            try logger.logInfo(.validation, msg, context);
        }
    }
}

fn runProjectScan(allocator: std.mem.Allocator, args: [][:0]u8, logger: *AppLogger) !void {
    const scan_path = if (args.len > 0) args[0] else ".";
    
    if (!output_json) {
        print("🔍 Scanning project for testing compliance issues\n", .{});
        print("================================================\n", .{});
        print("Scan path: {s}\n\n", .{scan_path});
    }
    
    const start_time = std.time.milliTimestamp();
    const context = LogContext{ 
        .operation_type = "project_scan",
        .request_id = scan_path
    };
    if (!output_json) {
        try logger.logInfo(.validation, "Starting project testing compliance scan", context);
    }
    
    var analyzer = TestingAnalyzer.init(allocator);
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
            print("\n❌ PROJECT TESTING COMPLIANCE CHECK FAILED\n", .{});
            print("Critical testing compliance issues found.\n", .{});
            
            const fail_context = LogContext{ 
                .operation_type = "project_scan_complete",
                .request_id = scan_path,
                .duration_ms = duration_ms
            };
            const msg = try std.fmt.allocPrint(allocator, "Project testing scan failed: {d} issues in {d} files", .{issues.len, files_processed});
            defer allocator.free(msg);
            try logger.logError(.validation, msg, fail_context, @intCast(issues.len));
        }
        std.process.exit(1);
    } else if (issues.len > 0) {
        if (!output_json) {
            print("\n⚠️  PROJECT TESTING COMPLIANCE CHECK PASSED WITH WARNINGS\n", .{});
            print("Consider addressing the warnings above.\n", .{});
            
            const warn_context = LogContext{ 
                .operation_type = "project_scan_complete",
                .request_id = scan_path,
                .duration_ms = duration_ms
            };
            const msg = try std.fmt.allocPrint(allocator, "Project testing scan completed with warnings: {d} issues in {d} files", .{issues.len, files_processed});
            defer allocator.free(msg);
            try logger.logWarn(.validation, msg, warn_context);
        }
    } else {
        if (!output_json) {
            print("\n✅ PROJECT TESTING COMPLIANCE CHECK PASSED\n", .{});
            print("All project files follow testing strategy best practices.\n", .{});
            
            const pass_context = LogContext{ 
                .operation_type = "project_scan_complete",
                .request_id = scan_path,
                .duration_ms = duration_ms
            };
            const msg = try std.fmt.allocPrint(allocator, "Project testing scan passed: {d} files analyzed", .{files_processed});
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
        try logger.logInfo(.validation, "Checking single file for testing compliance", context);
    }
    
    var analyzer = TestingAnalyzer.init(allocator);
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
            print("\n❌ FILE TESTING COMPLIANCE CHECK FAILED\n", .{});
            
            const fail_context = LogContext{ 
                .operation_type = "file_check_complete",
                .request_id = file_path,
                .duration_ms = duration_ms
            };
            const msg = try std.fmt.allocPrint(allocator, "File testing check failed with {d} issues", .{issues.len});
            defer allocator.free(msg);
            try logger.logError(.validation, msg, fail_context, @intCast(issues.len));
        } else {
            print("{{\"file\": \"{s}\", \"issues_found\": {d}, \"has_errors\": true}}", .{file_path, issues.len});
        }
        std.process.exit(1);
    } else {
        if (!output_json) {
            print("\n✅ FILE TESTING COMPLIANCE CHECK PASSED\n", .{});
            
            const pass_context = LogContext{ 
                .operation_type = "file_check_complete",
                .request_id = file_path,
                .duration_ms = duration_ms
            };
            const msg = if (issues.len > 0)
                try std.fmt.allocPrint(allocator, "File testing check passed with {d} warnings", .{issues.len})
            else
                try std.fmt.allocPrint(allocator, "File testing check passed with no issues", .{});
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

fn scanDirectory(allocator: std.mem.Allocator, analyzer: *TestingAnalyzer, dir_path: []const u8, logger: *AppLogger) !u32 {
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
        
        // Skip files that don't need testing analysis
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
    // Skip common files that don't need testing analysis or are generated
    const skip_patterns = [_][]const u8{
        "build_runner.zig",
        "memory_checker_cli.zig",
        "testing_compliance_cli.zig",
        "memory_analyzer.zig", 
        "testing_analyzer.zig",
        "generated_",
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
        \\Testing Compliance Checker - NFL Simulation Project
        \\
        \\Usage: testing_compliance_cli [COMMAND] [OPTIONS]
        \\
        \\Commands:
        \\  check [paths...]     Check testing compliance in specified files/directories
        \\                       (defaults to current directory if no paths given)
        \\  scan [path]          Scan entire project directory for testing issues
        \\                       (defaults to current directory)
        \\  file <path>          Check a single specific file
        \\  help, --help, -h     Show this help message
        \\
        \\Examples:
        \\  testing_compliance_cli check                     # Check current directory
        \\  testing_compliance_cli check src/               # Check src directory
        \\  testing_compliance_cli check src/ tests/        # Check multiple directories
        \\  testing_compliance_cli file src/main.zig        # Check single file
        \\  testing_compliance_cli scan                      # Scan entire project
        \\  testing_compliance_cli scan /path/to/project     # Scan specific project
        \\
        \\Testing Compliance Checks:
        \\  ✓ Test naming conventions follow strategy patterns
        \\  ✓ Tests are properly categorized (Unit, Integration, Simulation, etc.)
        \\  ✓ Memory safety patterns in tests (std.validation.allocator, defer, errdefer)
        \\  ✓ Source files have corresponding test files (co-location)
        \\  ✓ Test organization follows established structure
        \\  ✓ Test functions use appropriate memory management
        \\
        \\Test Categories Validated:
        \\  • Unit Tests: test "module_name: specific behavior"
        \\  • Integration Tests: test "integration: component1 + component2"
        \\  • Simulation Tests: test "simulation: scenario description"
        \\  • Data Validation: test "data validation: csv/data specific test"
        \\  • Performance Tests: test "performance: operation benchmark"
        \\  • Memory Safety: test "memory: allocator strategy/pattern"
        \\
        \\Exit Codes:
        \\  0 - All checks passed (may have warnings)
        \\  1 - Critical testing compliance errors found
        \\
        \\Integration:
        \\  This tool can be used as a slash command in development workflows:
        \\  /check-testing-compliance
        \\
        \\For more information about testing strategy, see:
        \\  sim-engine/docs/archive/TESTING-STRATEGY.md
        \\
    , .{});
}

// Slash command integration helper
pub fn slashCommandHelp() void {
    print(
        \\📋 /check-testing-compliance - Testing Strategy Validation
        \\
        \\Validates that all Zig test code follows the established testing strategy.
        \\
        \\What it checks:
        \\  • Test naming conventions and categorization
        \\  • Memory safety patterns in test code
        \\  • Co-location of tests with source files
        \\  • Proper test organization and structure
        \\
        \\Usage in todo lists and migration plans:
        \\  Add "/check-testing-compliance" at the end of implementation phases
        \\  to ensure testing strategy compliance before marking tasks complete.
        \\
        \\Exit behavior:
        \\  • Returns 0 if no critical errors (may have warnings)
        \\  • Returns 1 if critical testing issues found
        \\  • Prevents proceeding with non-compliant testing patterns
        \\
    , .{});
}
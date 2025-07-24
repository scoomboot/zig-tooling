const std = @import("std");
const zig_tooling = @import("zig_tooling");
const TestingAnalyzer = zig_tooling.testing_analyzer.TestingAnalyzer;
const AppLogger = zig_tooling.app_logger.AppLogger;
const LogContext = zig_tooling.app_logger.LogContext;
const config = zig_tooling.config;
const config_loader = zig_tooling.config_loader;
const print = std.debug.print;

var output_json = false;
var tool_config: ?config.ToolConfig = null;

// JSON output structures
const JsonOutput = struct {
    tool: []const u8,
    version: []const u8,
    timestamp: []const u8,
    summary: Summary,
    issues: []JsonIssue,

    const Summary = struct {
        files_analyzed: u32,
        total_issues: u32,
        errors: u32,
        warnings: u32,
        info: u32,
    };

    const JsonIssue = struct {
        file_path: []const u8,
        line: u32,
        column: u32,
        issue_type: []const u8,
        description: []const u8,
        suggestion: []const u8,
        severity: []const u8,
    };
};

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
    
    // Check for --json and --config flags before logger init and filter args
    var filtered_args = std.ArrayList([:0]u8).init(allocator);
    defer filtered_args.deinit();
    var custom_config_path: ?[]const u8 = null;
    
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--json")) {
            output_json = true;
        } else if (std.mem.eql(u8, args[i], "--config") and i + 1 < args.len) {
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
    
    // Override output format from config if not set by flag
    if (!output_json and tool_config != null) {
        output_json = tool_config.?.isJsonOutput();
    }

    // Get log path from config or environment
    const log_path = if (tool_config) |tc| 
        tc.getLogPath() orelse try allocator.dupe(u8, "logs/app.log")
    else 
        std.process.getEnvVarOwned(allocator, "ZIG_TOOLING_LOG_PATH") catch try allocator.dupe(u8, "logs/app.log");
    defer if (tool_config == null or tool_config.?.global.log_path == null) allocator.free(log_path);
    
    // Ensure logs directory exists
    const log_dir = std.fs.path.dirname(log_path) orelse "logs";
    try std.fs.cwd().makePath(log_dir);
    
    // Initialize modern logger
    var app_logger = AppLogger.init(allocator, log_path);

    // Use filtered args for command parsing
    const filtered_items = filtered_args.items;
    if (filtered_items.len < 2) {
        try printHelp();
        return;
    }
    
    const command = filtered_items[1];
    
    // Log tool start with proper category
    if (!output_json) {
        const context = LogContext{ .operation_type = command };
        try app_logger.logInfo(.validation, "Testing Compliance Checker started", context);
    }
    
    if (std.mem.eql(u8, command, "check")) {
        try runTestingCheck(allocator, filtered_items[2..], &app_logger);
    } else if (std.mem.eql(u8, command, "scan")) {
        try runProjectScan(allocator, filtered_items[2..], &app_logger);
    } else if (std.mem.eql(u8, command, "file")) {
        if (filtered_items.len < 3) {
            print("Error: file path required\n", .{});
            try printHelp();
            return;
        }
        try runSingleFileCheck(allocator, filtered_items[2], &app_logger);
    } else if (std.mem.eql(u8, command, "config")) {
        try runConfigCommand(allocator, filtered_items[2..], &cfg_loader);
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
    }
    
    const duration_ms = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
    
    if (output_json) {
        try outputJsonReport(allocator, &analyzer, total_files, duration_ms);
    }
    
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
    
    if (!output_json) {
        print("\n", .{});
        analyzer.printReport();
        
        print("\n📊 Project Scan Summary\n", .{});
        print("======================\n", .{});
        print("Files analyzed: {d}\n", .{files_processed});
        print("Issues found: {d}\n", .{analyzer.getIssues().len});
    }
    
    const duration_ms = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
    const issues = analyzer.getIssues();
    
    if (output_json) {
        try outputJsonReport(allocator, &analyzer, files_processed, duration_ms);
    }
    
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
            // Output error in JSON format
            const error_output = struct {
                tool: []const u8,
                version: []const u8,
                error_message: []const u8,
                file: []const u8,
                details: []const u8,
            }{
                .tool = "testing_compliance",
                .version = "0.1.0",
                .error_message = "Failed to analyze file",
                .file = file_path,
                .details = @errorName(err),
            };
            const stdout = std.io.getStdOut().writer();
            try std.json.stringify(error_output, .{}, stdout);
            try stdout.writeAll("\n");
        }
        std.process.exit(1);
    };
    
    if (!output_json) {
        analyzer.printReport();
    }
    
    const duration_ms = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
    const issues = analyzer.getIssues();
    
    if (output_json) {
        try outputJsonReport(allocator, &analyzer, 1, duration_ms);
    }
    
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
    // Use config skip patterns if available, otherwise use defaults
    const skip_patterns = if (tool_config) |tc|
        tc.testing_compliance.skip_patterns
    else
        &[_][]const u8{
            "build_runner.zig",
            "generated_",
            "zig-cache/",
            "zig-out/",
        };
    
    for (skip_patterns) |pattern| {
        if (std.mem.indexOf(u8, file_path, pattern) != null) {
            return true;
        }
    }
    
    return false;
}

fn outputJsonReport(allocator: std.mem.Allocator, analyzer: *TestingAnalyzer, files_analyzed: u32, _: u64) !void {
    const issues = analyzer.getIssues();
    
    // Count issues by severity
    var errors: u32 = 0;
    var warnings: u32 = 0;
    var info: u32 = 0;
    
    for (issues) |issue| {
        switch (issue.severity) {
            .err => errors += 1,
            .warning => warnings += 1,
            .info => info += 1,
        }
    }
    
    // Create JSON issues array
    var json_issues = try allocator.alloc(JsonOutput.JsonIssue, issues.len);
    defer allocator.free(json_issues);
    
    for (issues, 0..) |issue, i| {
        json_issues[i] = .{
            .file_path = issue.file_path,
            .line = issue.line,
            .column = issue.column,
            .issue_type = @tagName(issue.issue_type),
            .description = issue.description,
            .suggestion = issue.suggestion,
            .severity = @tagName(issue.severity),
        };
    }
    
    // Create timestamp
    const timestamp = std.time.timestamp();
    var buf: [64]u8 = undefined;
    const timestamp_str = try std.fmt.bufPrint(&buf, "{d}", .{timestamp});
    
    // Create JSON output
    const json_output = JsonOutput{
        .tool = "testing_compliance",
        .version = "0.1.0",
        .timestamp = timestamp_str,
        .summary = .{
            .files_analyzed = files_analyzed,
            .total_issues = @intCast(issues.len),
            .errors = errors,
            .warnings = warnings,
            .info = info,
        },
        .issues = json_issues,
    };
    
    // Write JSON to stdout
    const stdout = std.io.getStdOut().writer();
    try std.json.stringify(json_output, .{}, stdout);
    try stdout.writeAll("\n");
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
            
            print("Testing Compliance:\n", .{});
            print("  Test Naming Strict: {}\n", .{tc.testing_compliance.test_naming_strict});
            print("  Test File Prefix: {s}\n", .{tc.testing_compliance.test_file_prefix});
            print("  Require Test Category: {}\n", .{tc.testing_compliance.require_test_category});
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
        \\  config <subcmd>      Manage configuration (show, init, validate)
        \\  help, --help, -h     Show this help message
        \\
        \\Options:
        \\  --json               Output results in JSON format (for CI/CD integration)
        \\  --config <path>      Use custom configuration file (default: .zigtools.json)
        \\
        \\Examples:
        \\  testing_compliance_cli check                     # Check current directory
        \\  testing_compliance_cli check src/               # Check src directory
        \\  testing_compliance_cli check src/ tests/        # Check multiple directories
        \\  testing_compliance_cli file src/main.zig        # Check single file
        \\  testing_compliance_cli scan                      # Scan entire project
        \\  testing_compliance_cli scan /path/to/project     # Scan specific project
        \\  testing_compliance_cli check --json              # Output JSON to stdout
        \\  testing_compliance_cli scan src/ --json          # Scan with JSON output
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
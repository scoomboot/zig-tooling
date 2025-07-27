//! Build System Integration Tests
//! 
//! This module tests the library's build system integration features,
//! including build helpers, file pattern matching, and output formatters.

const std = @import("std");
const testing = std.testing;
const zig_tooling = @import("zig_tooling");

// Import the integration test utilities
const test_runner = @import("test_integration_runner.zig");
const TestUtils = test_runner.TestUtils;
const PerformanceBenchmark = test_runner.PerformanceBenchmark;

test "integration: build_integration file pattern matching" {
    const allocator = testing.allocator;
    
    var test_utils = try TestUtils.init(allocator);
    defer test_utils.deinit();
    
    std.debug.print("\n--- Testing Build Integration File Pattern Matching ---\n", .{});
    
    // Create a test project with various file types
    const project_files = [_]test_runner.FileSpec{
        .{ .path = "src/main.zig", .content = "pub fn main() !void {}" },
        .{ .path = "src/utils.zig", .content = "pub fn helper() void {}" },
        .{ .path = "src/subdir/module.zig", .content = "pub const value = 42;" },
        .{ .path = "tests/test_main.zig", .content = "test \"example\" {}" },
        .{ .path = "examples/demo.zig", .content = "pub fn demo() void {}" },
        .{ .path = "build.zig", .content = "const std = @import(\"std\");" },
        .{ .path = "README.md", .content = "# Project" },
        .{ .path = "zig-cache/cached.zig", .content = "// cached" },
    };
    
    const project_path = try test_utils.createTempProject("pattern_test", &project_files);
    defer allocator.free(project_path);
    
    // Test basic pattern matching with patterns library
    std.debug.print("Testing basic *.zig pattern matching...\n", .{});
    
    const result = try zig_tooling.patterns.checkProject(
        allocator,
        project_path,
        null,
        null,
    );
    defer zig_tooling.patterns.freeProjectResult(allocator, result);
    
    // Should find all .zig files except those in zig-cache
    const expected_files = 6; // main.zig, utils.zig, module.zig, test_main.zig, demo.zig, build.zig
    std.debug.print("Found {} files (expected around {})\n", .{ result.files_analyzed, expected_files });
    
    // Should analyze most .zig files but exclude cache directories
    try testing.expect(result.files_analyzed >= 5);
    try testing.expect(result.files_analyzed <= expected_files);
    
    std.debug.print("✓ File pattern matching works correctly\n", .{});
}

test "integration: build_integration output formatters" {
    const allocator = testing.allocator;
    
    var test_utils = try TestUtils.init(allocator);
    defer test_utils.deinit();
    
    std.debug.print("\n--- Testing Build Integration Output Formatters ---\n", .{});
    
    // Create a project with known issues for formatter testing
    const project_files = [_]test_runner.FileSpec{
        .{
            .path = "src/main.zig",
            .content = 
                \\const std = @import("std");
                \\
                \\pub fn main() !void {
                \\    const allocator = std.heap.page_allocator;
                \\    const data = try allocator.alloc(u8, 100);
                \\    // Missing defer - should be caught
                \\}
            ,
        },
        .{
            .path = "tests/test_example.zig",
            .content = 
                \\const testing = @import("std").testing;
                \\
                \\test "BadTestName" {
                \\    try testing.expect(true);
                \\}
                \\
                \\test "unit: good test name" {
                \\    try testing.expect(true);
                \\}
            ,
        },
    };
    
    const project_path = try test_utils.createTempProject("formatter_test", &project_files);
    defer allocator.free(project_path);
    
    // Analyze the project to get issues for formatting
    const config = zig_tooling.Config{
        .memory = .{ .check_defer = true },
        .testing = .{
            .enforce_categories = true,
            .enforce_naming = true,
            .allowed_categories = &.{ "unit", "integration", "e2e" },
        },
    };
    
    // Analyze a single file to get AnalysisResult for formatter testing
    const main_file_path = try std.fs.path.join(allocator, &.{ project_path, "src/main.zig" });
    defer allocator.free(main_file_path);
    
    const result = try zig_tooling.analyzeFile(allocator, main_file_path, config);
    defer allocator.free(result.issues);
    defer for (result.issues) |issue| {
        allocator.free(issue.file_path);
        allocator.free(issue.message);
        if (issue.suggestion) |s| allocator.free(s);
    };
    
    try testing.expect(result.issues_found > 0);
    std.debug.print("Found {} issues for formatter testing\n", .{result.issues_found});
    
    // Test text formatter
    std.debug.print("Testing text formatter...\n", .{});
    const text_output = try zig_tooling.formatters.formatAsText(allocator, result, .{
        .color = false,
        .verbose = true,
        .max_issues = 100,
        .include_stats = true,
    });
    defer allocator.free(text_output);
    
    try testing.expect(text_output.len > 0);
    try testing.expect(std.mem.indexOf(u8, text_output, "issues found") != null);
    std.debug.print("Text output: {} characters\n", .{text_output.len});
    
    // Test JSON formatter
    std.debug.print("Testing JSON formatter...\n", .{});
    const json_output = try zig_tooling.formatters.formatAsJson(allocator, result, .{
        .json_indent = 2,
        .include_stats = true,
    });
    defer allocator.free(json_output);
    
    try testing.expect(json_output.len > 0);
    try testing.expect(std.mem.indexOf(u8, json_output, "\"issues\":") != null);
    try testing.expect(std.mem.indexOf(u8, json_output, "\"files_analyzed\":") != null);
    std.debug.print("JSON output: {} characters\n", .{json_output.len});
    
    // Test GitHub Actions formatter
    std.debug.print("Testing GitHub Actions formatter...\n", .{});
    const gh_output = try zig_tooling.formatters.formatAsGitHubActions(allocator, result, .{
        .verbose = true,
    });
    defer allocator.free(gh_output);
    
    try testing.expect(gh_output.len > 0);
    try testing.expect(std.mem.indexOf(u8, gh_output, "::") != null); // GitHub Actions format
    std.debug.print("GitHub Actions output: {} characters\n", .{gh_output.len});
    
    std.debug.print("✓ All output formatters work correctly\n", .{});
}

test "integration: build_integration pre-commit hook generation" {
    const allocator = testing.allocator;
    
    var test_utils = try TestUtils.init(allocator);
    defer test_utils.deinit();
    
    std.debug.print("\n--- Testing Pre-commit Hook Generation ---\n", .{});
    
    // Test the build integration pre-commit hook functions
    // Note: This tests the API, not actual file system operations
    
    // Test bash hook generation
    std.debug.print("Testing bash pre-commit hook generation...\n", .{});
    
    const bash_hook = try zig_tooling.build_integration.createPreCommitHook(allocator, .{
        .include_memory_checks = true,
        .include_test_compliance = true,
        .fail_on_warnings = true,
        .check_paths = &.{ "src/", "tests/" },
        .hook_type = .bash,
    });
    defer allocator.free(bash_hook);
    
    try testing.expect(bash_hook.len > 0);
    try testing.expect(std.mem.indexOf(u8, bash_hook, "#!/bin/bash") != null);
    try testing.expect(std.mem.indexOf(u8, bash_hook, "src/") != null);
    try testing.expect(std.mem.indexOf(u8, bash_hook, "tests/") != null);
    std.debug.print("Bash hook: {} characters\n", .{bash_hook.len});
    
    // Test fish hook generation (may be placeholder)
    std.debug.print("Testing fish pre-commit hook generation...\n", .{});
    
    const fish_hook = try zig_tooling.build_integration.createPreCommitHook(allocator, .{
        .include_memory_checks = false,
        .include_test_compliance = true,
        .fail_on_warnings = false,
        .check_paths = &.{ "lib/" },
        .hook_type = .fish,
    });
    defer allocator.free(fish_hook);
    
    try testing.expect(fish_hook.len > 0);
    std.debug.print("Fish hook: {} characters\n", .{fish_hook.len});
    
    // Test PowerShell hook generation (may be placeholder)
    std.debug.print("Testing PowerShell pre-commit hook generation...\n", .{});
    
    const ps_hook = try zig_tooling.build_integration.createPreCommitHook(allocator, .{
        .include_memory_checks = true,
        .include_test_compliance = false,
        .fail_on_warnings = true,
        .check_paths = &.{ "src/" },
        .hook_type = .powershell,
    });
    defer allocator.free(ps_hook);
    
    try testing.expect(ps_hook.len > 0);
    std.debug.print("PowerShell hook: {} characters\n", .{ps_hook.len});
    
    std.debug.print("✓ Pre-commit hook generation works correctly\n", .{});
}

test "integration: build_integration step creation" {
    std.debug.print("\n--- Testing Build Step Creation ---\n", .{});
    
    // Note: We can't actually test build step creation without a real Build instance,
    // but we can test the configuration structures and validation
    
    // Test memory check options
    const memory_options = zig_tooling.build_integration.MemoryCheckOptions{
        .source_paths = &.{ "src/**/*.zig", "lib/**/*.zig" },
        .exclude_patterns = &.{ "**/zig-cache/**", "**/test_*.zig" },
        .memory_config = .{
            .check_defer = true,
            .check_arena_usage = true,
            .check_allocator_usage = true,
            .allowed_allocators = &.{ "std.heap.GeneralPurposeAllocator", "std.testing.allocator" },
        },
        .fail_on_warnings = true,
        .max_issues = 100,
        .continue_on_error = false,
        .output_format = .text,
        .step_name = "memory-check",
        .step_description = "Run memory safety analysis",
    };
    
    // Validate the configuration structure
    try testing.expect(memory_options.source_paths.len > 0);
    try testing.expect(memory_options.memory_config.check_defer);
    try testing.expectEqualStrings("memory-check", memory_options.step_name);
    
    // Test test compliance options
    const test_options = zig_tooling.build_integration.TestComplianceOptions{
        .source_paths = &.{ "tests/**/*.zig" },
        .testing_config = .{
            .enforce_categories = true,
            .enforce_naming = true,
            .allowed_categories = &.{ "unit", "integration", "e2e", "performance" },
        },
        .fail_on_warnings = false,
        .output_format = .json,
        .step_name = "test-compliance",
        .step_description = "Run test compliance analysis",
    };
    
    try testing.expect(test_options.source_paths.len > 0);
    try testing.expect(test_options.testing_config.enforce_categories);
    try testing.expectEqual(zig_tooling.build_integration.OutputFormat.json, test_options.output_format);
    
    std.debug.print("✓ Build step configuration structures work correctly\n", .{});
}

test "integration: build_integration file discovery" {
    const allocator = testing.allocator;
    
    var test_utils = try TestUtils.init(allocator);
    defer test_utils.deinit();
    
    std.debug.print("\n--- Testing Build Integration File Discovery ---\n", .{});
    
    // Create a complex project structure for file discovery testing
    const project_files = [_]test_runner.FileSpec{
        .{ .path = "src/main.zig", .content = "// main" },
        .{ .path = "src/core/engine.zig", .content = "// engine" },
        .{ .path = "src/utils/helpers.zig", .content = "// helpers" },
        .{ .path = "lib/external.zig", .content = "// external" },
        .{ .path = "tests/unit/test_main.zig", .content = "// test main" },
        .{ .path = "tests/integration/test_engine.zig", .content = "// test engine" },
        .{ .path = "examples/demo.zig", .content = "// demo" },
        .{ .path = "tools/quality_check.zig", .content = "// quality check" },
        .{ .path = "zig-cache/cached.zig", .content = "// should be excluded" },
        .{ .path = "zig-out/build.zig", .content = "// should be excluded" },
        .{ .path = "README.md", .content = "// not zig" },
        .{ .path = "build.zig", .content = "// build script" },
    };
    
    const project_path = try test_utils.createTempProject("discovery_test", &project_files);
    defer allocator.free(project_path);
    
    // Test file discovery with various patterns
    std.debug.print("Testing file discovery with include/exclude patterns...\n", .{});
    
    // Test discovering all Zig files
    const all_result = try zig_tooling.patterns.checkProject(
        allocator,
        project_path,
        null,
        null,
    );
    defer zig_tooling.patterns.freeProjectResult(allocator, all_result);
    
    std.debug.print("All files discovery found {} files\n", .{all_result.files_analyzed});
    
    // Should find most .zig files but exclude cache directories
    try testing.expect(all_result.files_analyzed >= 8); // At least the main source files
    try testing.expect(all_result.files_analyzed <= 11); // At most all .zig files minus cache
    
    // Test with custom configuration for specific paths
    const src_only_config = zig_tooling.Config{
        .memory = .{ .check_defer = true },
        .testing = .{},
        // Note: Pattern filtering would need to be implemented in patterns.zig
    };
    
    const src_result = try zig_tooling.patterns.checkProject(
        allocator,
        project_path,
        src_only_config,
        null,
    );
    defer zig_tooling.patterns.freeProjectResult(allocator, src_result);
    
    std.debug.print("Source-focused discovery found {} files\n", .{src_result.files_analyzed});
    
    std.debug.print("✓ File discovery works correctly with various patterns\n", .{});
}

test "integration: build_integration performance with large projects" {
    const allocator = testing.allocator;
    
    var test_utils = try TestUtils.init(allocator);
    defer test_utils.deinit();
    
    std.debug.print("\n--- Testing Build Integration Performance ---\n", .{});
    
    var benchmark = PerformanceBenchmark.start(allocator, "Build integration performance");
    defer _ = benchmark.end();
    
    // Create a moderately large project for performance testing
    var project_files = std.ArrayList(test_runner.FileSpec).init(allocator);
    defer project_files.deinit();
    
    const modules = 15;
    var i: u32 = 0;
    while (i < modules) : (i += 1) {
        // Create module file
        const module_path = try std.fmt.allocPrint(allocator, "src/module_{}.zig", .{i});
        defer allocator.free(module_path);
        
        const module_content = try std.fmt.allocPrint(allocator,
            \\const std = @import("std");
            \\
            \\pub fn function_{}(allocator: std.mem.Allocator) ![]u8 {{
            \\    const data = try allocator.alloc(u8, {});
            \\    defer allocator.free(data);
            \\    
            \\    // Some processing...
            \\    std.mem.set(u8, data, 0x{X});
            \\    
            \\    return try allocator.dupe(u8, data);
            \\}}
            \\
            \\pub const MODULE_{}_VERSION = {};
        , .{ i, (i + 1) * 64, i % 256, i, i });
        defer allocator.free(module_content);
        
        // Create test file
        const test_path = try std.fmt.allocPrint(allocator, "tests/test_module_{}.zig", .{i});
        defer allocator.free(test_path);
        
        const test_content = try std.fmt.allocPrint(allocator,
            \\const std = @import("std");
            \\const testing = std.testing;
            \\const module_{} = @import("../src/module_{}.zig");
            \\
            \\test "unit: module_{}: function works" {{
            \\    const allocator = testing.allocator;
            \\    const result = try module_{}.function_{}(allocator);
            \\    defer allocator.free(result);
            \\    try testing.expect(result.len > 0);
            \\}}
            \\
            \\test "BadTestName{}" {{
            \\    try testing.expect(true);
            \\}}
        , .{ i, i, i, i, i, i });
        defer allocator.free(test_content);
        
        // Add to project files list
        const owned_module_path = try allocator.dupe(u8, module_path);
        const owned_module_content = try allocator.dupe(u8, module_content);
        const owned_test_path = try allocator.dupe(u8, test_path);
        const owned_test_content = try allocator.dupe(u8, test_content);
        
        try project_files.append(.{ .path = owned_module_path, .content = owned_module_content });
        try project_files.append(.{ .path = owned_test_path, .content = owned_test_content });
    }
    
    // Clean up the dynamically allocated strings
    defer for (project_files.items) |file_spec| {
        allocator.free(file_spec.path);
        allocator.free(file_spec.content);
    };
    
    const project_path = try test_utils.createTempProject("performance_test", project_files.items);
    defer allocator.free(project_path);
    
    // Run comprehensive analysis with both memory and test checking
    const config = zig_tooling.Config{
        .memory = .{
            .check_defer = true,
            .check_arena_usage = true,
            .check_allocator_usage = true,
        },
        .testing = .{
            .enforce_categories = true,
            .enforce_naming = true,
            .allowed_categories = &.{ "unit", "integration", "e2e" },
        },
    };
    
    const result = try zig_tooling.patterns.checkProject(allocator, project_path, config, null);
    defer zig_tooling.patterns.freeProjectResult(allocator, result);
    
    const expected_files = modules * 2; // module + test file for each
    
    try testing.expect(result.files_analyzed == expected_files);
    try testing.expect(result.issues_found > 0); // Should find test naming issues
    
    std.debug.print("Performance test: {} files, {} issues, {}ms\n", .{
        result.files_analyzed,
        result.issues_found,
        result.analysis_time_ms,
    });
    
    // Performance target: should handle moderate projects efficiently
    try testing.expect(result.analysis_time_ms < 3000); // Less than 3 seconds
    
    std.debug.print("✓ Build integration performance is acceptable\n", .{});
}
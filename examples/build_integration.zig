//! Build System Integration Example
//!
//! This example demonstrates how to integrate zig-tooling into your build.zig
//! to automatically run code quality checks during the build process.
//!
//! Copy this file as build.zig in your project and adapt as needed.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // === Your normal build configuration ===
    const exe = b.addExecutable(.{
        .name = "my_app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add zig-tooling dependency (assumes you've added it to build.zig.zon)
    const zig_tooling_dep = b.dependency("zig_tooling", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zig_tooling", zig_tooling_dep.module("zig_tooling"));

    b.installArtifact(exe);

    // === Add zig-tooling quality checks ===

    // Create a quality check executable
    const quality_check_exe = b.addExecutable(.{
        .name = "quality_check",
        .root_source_file = b.path("tools/quality_check.zig"),
        .target = target,
        .optimize = optimize,
    });
    quality_check_exe.root_module.addImport("zig_tooling", zig_tooling_dep.module("zig_tooling"));

    // Memory safety check step
    const memory_check_step = b.step("check-memory", "Run memory safety analysis");
    const run_memory_check = b.addRunArtifact(quality_check_exe);
    run_memory_check.addArgs(&.{ "--mode", "memory" });
    memory_check_step.dependOn(&run_memory_check.step);

    // Test compliance check step
    const test_check_step = b.step("check-tests", "Run test compliance analysis");
    const run_test_check = b.addRunArtifact(quality_check_exe);
    run_test_check.addArgs(&.{ "--mode", "tests" });
    test_check_step.dependOn(&run_test_check.step);

    // Combined quality check step
    const quality_step = b.step("quality", "Run all code quality checks");
    const run_quality = b.addRunArtifact(quality_check_exe);
    run_quality.addArgs(&.{ "--mode", "all", "--fail-on-warnings" });
    quality_step.dependOn(&run_quality.step);

    // CI/CD optimized step with GitHub Actions output
    const ci_step = b.step("ci-quality", "Run quality checks for CI/CD");
    const run_ci = b.addRunArtifact(quality_check_exe);
    run_ci.addArgs(&.{
        "--mode",             "all",
        "--format",           "github-actions",
        "--fail-on-warnings",
    });
    ci_step.dependOn(&run_ci.step);

    // Make tests depend on quality checks
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(quality_step);

    const run_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_step.dependOn(&run_tests.step);

    // Pre-commit hook generation step
    const hook_step = b.step("install-hooks", "Install git pre-commit hooks");
    const run_hook_installer = b.addRunArtifact(quality_check_exe);
    run_hook_installer.addArgs(&.{"--install-hooks"});
    hook_step.dependOn(&run_hook_installer.step);
}

// === Example quality_check.zig tool ===
// Save this as tools/quality_check.zig in your project

// const std = @import("std");
// const zig_tooling = @import("zig_tooling");
//
// pub fn main() !void {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const allocator = gpa.allocator();
//
//     const args = try std.process.argsAlloc(allocator);
//     defer std.process.argsFree(allocator, args);
//
//     var mode: Mode = .all;
//     var format: Format = .text;
//     var fail_on_warnings = false;
//     var install_hooks = false;
//
//     // Parse arguments
//     var i: usize = 1;
//     while (i < args.len) : (i += 1) {
//         if (std.mem.eql(u8, args[i], "--mode")) {
//             i += 1;
//             if (i < args.len) {
//                 if (std.mem.eql(u8, args[i], "memory")) mode = .memory;
//                 if (std.mem.eql(u8, args[i], "tests")) mode = .tests;
//                 if (std.mem.eql(u8, args[i], "all")) mode = .all;
//             }
//         } else if (std.mem.eql(u8, args[i], "--format")) {
//             i += 1;
//             if (i < args.len) {
//                 if (std.mem.eql(u8, args[i], "text")) format = .text;
//                 if (std.mem.eql(u8, args[i], "json")) format = .json;
//                 if (std.mem.eql(u8, args[i], "github-actions")) format = .github_actions;
//             }
//         } else if (std.mem.eql(u8, args[i], "--fail-on-warnings")) {
//             fail_on_warnings = true;
//         } else if (std.mem.eql(u8, args[i], "--install-hooks")) {
//             install_hooks = true;
//         }
//     }
//
//     if (install_hooks) {
//         try installPreCommitHooks(allocator);
//         return;
//     }
//
//     // Configure analysis
//     const config = zig_tooling.Config{
//         .memory = .{
//             .check_defer = true,
//             .check_arena_usage = true,
//             .check_allocator_usage = true,
//             .allowed_allocators = &.{
//                 "std.heap.GeneralPurposeAllocator",
//                 "std.testing.allocator",
//                 "std.heap.ArenaAllocator",
//             },
//         },
//         .testing = .{
//             .enforce_categories = true,
//             .enforce_naming = true,
//             .allowed_categories = &.{ "unit", "integration", "e2e", "perf" },
//         },
//         .options = .{
//             .max_issues = 100,
//             .verbose = true,
//             .continue_on_error = true,
//         },
//     };
//
//     // Run analysis based on mode
//     const result = switch (mode) {
//         .memory => try analyzeMemory(allocator, config),
//         .tests => try analyzeTests(allocator, config),
//         .all => try analyzeAll(allocator, config),
//     };
//     defer zig_tooling.patterns.freeProjectResult(allocator, result);
//
//     // Format output
//     const output = switch (format) {
//         .text => try zig_tooling.formatters.formatAsText(allocator, result, .{
//             .color = true,
//             .verbose = true,
//         }),
//         .json => try zig_tooling.formatters.formatAsJson(allocator, result, .{
//             .json_indent = 2,
//             .include_stats = true,
//         }),
//         .github_actions => try zig_tooling.formatters.formatAsGitHubActions(allocator, result, .{
//             .verbose = false,
//         }),
//     };
//     defer allocator.free(output);
//
//     // Output results
//     const stdout = std.io.getStdOut().writer();
//     try stdout.writeAll(output);
//
//     // Exit with appropriate code
//     const has_errors = result.hasErrors();
//     const has_warnings = result.hasWarnings();
//
//     if (has_errors or (fail_on_warnings and has_warnings)) {
//         std.process.exit(1);
//     }
// }
//
// const Mode = enum { memory, tests, all };
// const Format = enum { text, json, github_actions };
//
// fn analyzeMemory(allocator: std.mem.Allocator, config: zig_tooling.Config) !zig_tooling.patterns.ProjectAnalysisResult {
//     var memory_config = config;
//     memory_config.testing = .{}; // Disable test analysis
//
//     return try zig_tooling.patterns.checkProject(
//         allocator,
//         ".",
//         memory_config,
//         progressCallback,
//     );
// }
//
// fn analyzeTests(allocator: std.mem.Allocator, config: zig_tooling.Config) !zig_tooling.patterns.ProjectAnalysisResult {
//     var test_config = config;
//     test_config.memory = .{}; // Disable memory analysis
//     test_config.pattern_config = .{
//         .include_patterns = &.{ "tests/**/*.zig", "src/**/*test*.zig" },
//     };
//
//     return try zig_tooling.patterns.checkProject(
//         allocator,
//         ".",
//         test_config,
//         progressCallback,
//     );
// }
//
// fn analyzeAll(allocator: std.mem.Allocator, config: zig_tooling.Config) !zig_tooling.patterns.ProjectAnalysisResult {
//     return try zig_tooling.patterns.checkProject(
//         allocator,
//         ".",
//         config,
//         progressCallback,
//     );
// }
//
// fn progressCallback(files_processed: u32, total_files: u32, current_file: []const u8) void {
//     const stderr = std.io.getStdErr().writer();
//     stderr.print("\rAnalyzing {}/{}: {s}", .{
//         files_processed + 1,
//         total_files,
//         current_file
//     }) catch {};
// }
//
// fn installPreCommitHooks(allocator: std.mem.Allocator) !void {
//     const hook_content = try zig_tooling.build_integration.createPreCommitHook(allocator, .{
//         .include_memory_checks = true,
//         .include_test_compliance = true,
//         .fail_on_warnings = true,
//         .check_paths = &.{ "src/", "tests/" },
//         .hook_type = .bash,
//     });
//     defer allocator.free(hook_content);
//
//     // Write to .git/hooks/pre-commit
//     const cwd = std.fs.cwd();
//     const hook_file = try cwd.createFile(".git/hooks/pre-commit", .{});
//     defer hook_file.close();
//
//     try hook_file.writeAll(hook_content);
//
//     // Make executable on Unix systems
//     if (builtin.os.tag != .windows) {
//         try hook_file.chmod(0o755);
//     }
//
//     std.debug.print("Pre-commit hook installed successfully!\n", .{});
// }

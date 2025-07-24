const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the root module
    const root_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
    });

    // Memory Checker CLI
    const memory_checker_exe = b.addExecutable(.{
        .name = "memory_checker_cli",
        .root_source_file = b.path("src/cli/memory_checker_cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    memory_checker_exe.root_module.addImport("zig_tooling", root_module);
    b.installArtifact(memory_checker_exe);

    // Testing Compliance CLI
    const testing_compliance_exe = b.addExecutable(.{
        .name = "testing_compliance_cli",
        .root_source_file = b.path("src/cli/testing_compliance_cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    testing_compliance_exe.root_module.addImport("zig_tooling", root_module);
    b.installArtifact(testing_compliance_exe);

    // App Logger CLI
    const app_logger_exe = b.addExecutable(.{
        .name = "app_logger_cli",
        .root_source_file = b.path("src/cli/app_logger_cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    app_logger_exe.root_module.addImport("zig_tooling", root_module);
    b.installArtifact(app_logger_exe);

    // Add run commands
    const run_memory_checker = b.addRunArtifact(memory_checker_exe);
    const run_testing_compliance = b.addRunArtifact(testing_compliance_exe);
    const run_app_logger = b.addRunArtifact(app_logger_exe);

    // Forward command line arguments
    if (b.args) |args| {
        run_memory_checker.addArgs(args);
        run_testing_compliance.addArgs(args);
        run_app_logger.addArgs(args);
    }

    // Add run steps
    const run_memory_step = b.step("run-memory", "Run memory checker");
    run_memory_step.dependOn(&run_memory_checker.step);

    const run_testing_step = b.step("run-testing", "Run testing compliance checker");
    run_testing_step.dependOn(&run_testing_compliance.step);

    const run_logger_step = b.step("run-logger", "Run app logger");
    run_logger_step.dependOn(&run_app_logger.step);

    // Tests
    const test_memory_checker = b.addTest(.{
        .root_source_file = b.path("tests/test_memory_checker_cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_memory_checker.root_module.addImport("zig_tooling", root_module);

    const test_testing_compliance = b.addTest(.{
        .root_source_file = b.path("tests/test_testing_compliance_cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_testing_compliance.root_module.addImport("zig_tooling", root_module);

    const test_app_logger = b.addTest(.{
        .root_source_file = b.path("tests/test_app_logger_cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_app_logger.root_module.addImport("zig_tooling", root_module);

    const test_scope_integration = b.addTest(.{
        .root_source_file = b.path("tests/test_scope_integration.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_scope_integration.root_module.addImport("zig_tooling", root_module);

    // Add test step
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&test_memory_checker.step);
    test_step.dependOn(&test_testing_compliance.step);
    test_step.dependOn(&test_app_logger.step);
    test_step.dependOn(&test_scope_integration.step);

    // Add a step to build all tools
    const build_all_step = b.step("build-all", "Build all tools");
    build_all_step.dependOn(b.getInstallStep());
}
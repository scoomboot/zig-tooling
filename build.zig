const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the library
    const lib = b.addStaticLibrary(.{
        .name = "zig_tooling",
        .root_source_file = b.path("src/zig_tooling.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Install the library artifact
    b.installArtifact(lib);

    // Create module for internal use and testing
    const zig_tooling_module = b.addModule("zig_tooling", .{
        .root_source_file = b.path("src/zig_tooling.zig"),
    });

    // Tests
    const test_scope_integration = b.addTest(.{
        .root_source_file = b.path("tests/test_scope_integration.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_scope_integration.root_module.addImport("zig_tooling", zig_tooling_module);

    // API tests
    const test_api = b.addTest(.{
        .root_source_file = b.path("tests/test_api.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_api.root_module.addImport("zig_tooling", zig_tooling_module);

    // Patterns library tests
    const test_patterns = b.addTest(.{
        .root_source_file = b.path("tests/test_patterns.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_patterns.root_module.addImport("zig_tooling", zig_tooling_module);

    // Unit tests for the library itself
    const lib_tests = b.addTest(.{
        .root_source_file = b.path("src/zig_tooling.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Integration tests
    const test_integration_runner = b.addTest(.{
        .root_source_file = b.path("tests/integration/test_integration_runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_integration_runner.root_module.addImport("zig_tooling", zig_tooling_module);

    const test_real_project_analysis = b.addTest(.{
        .root_source_file = b.path("tests/integration/test_real_project_analysis.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_real_project_analysis.root_module.addImport("zig_tooling", zig_tooling_module);

    const test_build_system_integration = b.addTest(.{
        .root_source_file = b.path("tests/integration/test_build_system_integration.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_build_system_integration.root_module.addImport("zig_tooling", zig_tooling_module);

    const test_memory_performance = b.addTest(.{
        .root_source_file = b.path("tests/integration/test_memory_performance.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_memory_performance.root_module.addImport("zig_tooling", zig_tooling_module);

    const test_thread_safety = b.addTest(.{
        .root_source_file = b.path("tests/integration/test_thread_safety.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_thread_safety.root_module.addImport("zig_tooling", zig_tooling_module);

    const test_error_boundaries = b.addTest(.{
        .root_source_file = b.path("tests/integration/test_error_boundaries.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_error_boundaries.root_module.addImport("zig_tooling", zig_tooling_module);

    // Test steps
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&test_scope_integration.step);
    test_step.dependOn(&test_api.step);
    test_step.dependOn(&test_patterns.step);
    test_step.dependOn(&lib_tests.step);

    // Integration test step (separate for longer-running tests)
    const integration_test_step = b.step("test-integration", "Run integration tests");
    integration_test_step.dependOn(&test_integration_runner.step);
    integration_test_step.dependOn(&test_real_project_analysis.step);
    integration_test_step.dependOn(&test_build_system_integration.step);
    integration_test_step.dependOn(&test_memory_performance.step);
    integration_test_step.dependOn(&test_thread_safety.step);
    integration_test_step.dependOn(&test_error_boundaries.step);

    // Comprehensive test step that runs everything
    const test_all_step = b.step("test-all", "Run all tests including integration tests");
    test_all_step.dependOn(test_step);
    test_all_step.dependOn(integration_test_step);
}
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

    // Patterns performance benchmark tests
    const test_patterns_performance = b.addTest(.{
        .root_source_file = b.path("tests/test_patterns_performance.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_patterns_performance.root_module.addImport("zig_tooling", zig_tooling_module);

    // Allocator pattern tests
    const test_allocator_patterns = b.addTest(.{
        .root_source_file = b.path("tests/test_allocator_patterns.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_allocator_patterns.root_module.addImport("zig_tooling", zig_tooling_module);

    // ScopeTracker memory leak tests
    const test_scope_tracker_memory = b.addTest(.{
        .root_source_file = b.path("tests/test_scope_tracker_memory.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_scope_tracker_memory.root_module.addImport("zig_tooling", zig_tooling_module);

    // Example validation tests
    const test_example_validation = b.addTest(.{
        .root_source_file = b.path("tests/test_example_validation.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_example_validation.root_module.addImport("zig_tooling", zig_tooling_module);

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
    test_step.dependOn(&test_allocator_patterns.step);
    test_step.dependOn(&test_scope_tracker_memory.step);
    test_step.dependOn(&test_example_validation.step);
    test_step.dependOn(&lib_tests.step);

    // Integration test step (separate for longer-running tests)
    const integration_test_step = b.step("test-integration", "Run integration tests");
    integration_test_step.dependOn(&test_integration_runner.step);
    integration_test_step.dependOn(&test_real_project_analysis.step);
    integration_test_step.dependOn(&test_build_system_integration.step);
    integration_test_step.dependOn(&test_memory_performance.step);
    integration_test_step.dependOn(&test_thread_safety.step);
    integration_test_step.dependOn(&test_error_boundaries.step);
    integration_test_step.dependOn(&test_patterns_performance.step);

    // Comprehensive test step that runs everything
    const test_all_step = b.step("test-all", "Run all tests including integration tests");
    test_all_step.dependOn(test_step);
    test_all_step.dependOn(integration_test_step);

    // Quality check tool
    const quality_check_exe = b.addExecutable(.{
        .name = "quality_check",
        .root_source_file = b.path("tools/quality_check.zig"),
        .target = target,
        .optimize = optimize,
    });
    quality_check_exe.root_module.addImport("zig_tooling", zig_tooling_module);

    // Quality check step
    const quality_step = b.step("quality", "Run all code quality checks");
    const run_quality = b.addRunArtifact(quality_check_exe);
    quality_step.dependOn(&run_quality.step);
    
    // Dogfood step - use our own tooling on ourselves (non-blocking)
    const dogfood_step = b.step("dogfood", "Run quality checks on zig-tooling itself (non-blocking)");
    const run_dogfood = b.addRunArtifact(quality_check_exe);
    run_dogfood.addArg("--no-fail-on-warnings");
    dogfood_step.dependOn(&run_dogfood.step);

    // Validate tools compilation step
    const validate_tools_step = b.step("validate-tools", "Validate that all tools compile successfully");
    
    // Add all tools here - currently just quality_check
    // When new tools are added, they should be added to this list
    const tools_to_validate = [_]*std.Build.Step.Compile{
        quality_check_exe,
    };
    
    // Make validate-tools depend on compilation of all tools
    for (tools_to_validate) |tool| {
        validate_tools_step.dependOn(&tool.step);
    }
    
    // Make test step depend on tools validation
    test_step.dependOn(validate_tools_step);
}
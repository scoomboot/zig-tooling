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

    // Unit tests for the library itself
    const lib_tests = b.addTest(.{
        .root_source_file = b.path("src/zig_tooling.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add test step
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&test_scope_integration.step);
    test_step.dependOn(&lib_tests.step);
}
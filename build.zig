const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the root module
    const root_module = b.createModule(.{
        .root_source_file = b.path("src/zig_tooling.zig"),
    });

    // Tests
    const test_scope_integration = b.addTest(.{
        .root_source_file = b.path("tests/test_scope_integration.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_scope_integration.root_module.addImport("zig_tooling", root_module);

    // Add test step
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&test_scope_integration.step);
}
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // === Main application ===
    const exe = b.addExecutable(.{
        .name = "quickstart-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add zig-tooling dependency
    const zig_tooling_dep = b.dependency("zig_tooling", .{
        .target = target,
        .optimize = optimize,
    });
    
    // Import zig-tooling into your app (optional - only if you use it in code)
    exe.root_module.addImport("zig_tooling", zig_tooling_dep.module("zig_tooling"));
    
    b.installArtifact(exe);

    // === Quality check tool ===
    const quality_check = b.addExecutable(.{
        .name = "quality_check",
        .root_source_file = b.path("tools/quality_check.zig"),
        .target = target,
        .optimize = optimize,
    });
    quality_check.root_module.addImport("zig_tooling", zig_tooling_dep.module("zig_tooling"));

    // === Build steps ===
    
    // Basic quality check
    const quality_step = b.step("quality", "Run code quality checks");
    const run_quality = b.addRunArtifact(quality_check);
    quality_step.dependOn(&run_quality.step);

    // Memory-only checks
    const memory_step = b.step("check-memory", "Run memory safety checks only");
    const run_memory = b.addRunArtifact(quality_check);
    run_memory.addArgs(&.{ "--check", "memory" });
    memory_step.dependOn(&run_memory.step);

    // Test compliance only
    const test_compliance_step = b.step("check-tests", "Run test compliance checks only");
    const run_test_compliance = b.addRunArtifact(quality_check);
    run_test_compliance.addArgs(&.{ "--check", "tests" });
    test_compliance_step.dependOn(&run_test_compliance.step);

    // CI/CD optimized output
    const ci_step = b.step("ci", "Run quality checks with CI-friendly output");
    const run_ci = b.addRunArtifact(quality_check);
    run_ci.addArgs(&.{ "--format", "github-actions" });
    ci_step.dependOn(&run_ci.step);

    // Run tests (depends on quality checks)
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(quality_step); // Quality gate before tests
    
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);

    // Clean build that enforces quality
    const clean_build_step = b.step("clean-build", "Clean build with quality checks");
    clean_build_step.dependOn(quality_step);
    clean_build_step.dependOn(&exe.step);
}
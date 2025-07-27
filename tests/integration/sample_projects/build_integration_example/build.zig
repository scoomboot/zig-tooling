//! Build.zig demonstrating zig-tooling integration
//! 
//! This build script shows how to integrate zig-tooling into a project's
//! build process for automated code quality checking.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "build_integration_demo",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the build integration demo");
    run_step.dependOn(&run_cmd.step);

    // === Quality Check Integration ===
    // 
    // In a real project, you would add zig-tooling as a dependency
    // and use it for automated quality checks:
    //
    // const zig_tooling_dep = b.dependency("zig_tooling", .{
    //     .target = target,
    //     .optimize = optimize,
    // });
    //
    // const quality_check_exe = b.addExecutable(.{
    //     .name = "quality_check",
    //     .root_source_file = b.path("tools/quality_check.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });
    // quality_check_exe.root_module.addImport("zig_tooling", zig_tooling_dep.module("zig_tooling"));
    //
    // const quality_step = b.step("check", "Run code quality checks");
    // const run_quality = b.addRunArtifact(quality_check_exe);
    // quality_step.dependOn(&run_quality.step);
    //
    // // Make build depend on quality checks
    // exe.step.dependOn(quality_step);

    // For this demo, we'll create a mock quality check step
    const mock_quality_step = b.step("check", "Run mock code quality checks");
    const mock_quality_run = b.addSystemCommand(&.{ "echo", "Mock quality check passed" });
    mock_quality_step.dependOn(&mock_quality_run.step);

    // Optional: Make the main build depend on quality checks
    // Uncomment this line to require quality checks before building
    // exe.step.dependOn(mock_quality_step);

    // Pre-commit hook generation step
    const precommit_step = b.step("install-precommit", "Install pre-commit hooks");
    const precommit_run = b.addSystemCommand(&.{ 
        "echo", 
        "Would install pre-commit hook that runs: zig build check" 
    });
    precommit_step.dependOn(&precommit_run.step);

    // CI integration step
    const ci_step = b.step("ci", "Run CI quality checks");
    ci_step.dependOn(mock_quality_step);
    ci_step.dependOn(&exe.step);
    
    const ci_report = b.addSystemCommand(&.{ 
        "echo", 
        "CI checks complete - ready for deployment" 
    });
    ci_step.dependOn(&ci_report.step);
}
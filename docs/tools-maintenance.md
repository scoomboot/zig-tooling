# Tools Directory Maintenance Guide

This guide explains how to maintain and extend the tools/ directory in the zig-tooling library.

## Overview

The `tools/` directory contains utility programs that help users integrate and use zig-tooling effectively. All tools in this directory must:

1. Compile successfully without errors
2. Be validated as part of the build process
3. Be included in CI/CD checks
4. Follow consistent patterns and conventions

## Current Tools

### quality_check
- **Purpose**: Runs comprehensive code quality analysis on projects
- **Location**: `tools/quality_check.zig`
- **Usage**: `zig build quality` or `zig build dogfood`

## Adding New Tools

When adding a new tool to the `tools/` directory, follow these steps:

### 1. Create the Tool

Create your new tool file in the `tools/` directory:

```zig
// tools/my_new_tool.zig
const std = @import("std");
const zig_tooling = @import("zig_tooling");

pub fn main() !void {
    // Tool implementation
}
```

### 2. Update build.zig

Add your tool to the build configuration:

```zig
// Add executable definition
const my_new_tool_exe = b.addExecutable(.{
    .name = "my_new_tool",
    .root_source_file = b.path("tools/my_new_tool.zig"),
    .target = target,
    .optimize = optimize,
});
my_new_tool_exe.root_module.addImport("zig_tooling", zig_tooling_module);

// Add to tools validation list
const tools_to_validate = [_]*std.Build.Step.Compile{
    quality_check_exe,
    my_new_tool_exe, // Add your tool here
};

// Optionally create a build step to run the tool
const my_tool_step = b.step("my-tool", "Run my new tool");
const run_my_tool = b.addRunArtifact(my_new_tool_exe);
my_tool_step.dependOn(&run_my_tool.step);
```

### 3. Test Locally

Before committing, ensure your tool compiles and runs correctly:

```bash
# Validate compilation
zig build validate-tools

# Run your tool
zig build my-tool

# Run all tests to ensure nothing broke
zig build test-all
```

### 4. Document the Tool

Add documentation for your tool:

1. Update this file's "Current Tools" section
2. Add usage examples to the tool's `--help` output
3. Consider adding an example in the `examples/` directory

## Build Validation

The build system automatically validates all tools through:

### Local Validation

```bash
# Validate all tools compile
zig build validate-tools

# Run as part of test suite
zig build test
```

### CI/CD Validation

The GitHub Actions workflow (`.github/workflows/ci.yml`) includes:

- **validate-tools job**: Ensures all tools compile on every PR
- **cross-platform job**: Tests tool compilation on Linux, macOS, and Windows
- **quality-check job**: Runs the quality tool to validate the codebase

## Common Patterns

### Command Line Arguments

Tools should follow consistent argument patterns:

```zig
- --help              Show help message
- --format <format>   Output format (text, json, github-actions)
- --verbose          Verbose output
- --no-fail-on-warnings  Don't exit with error on warnings
```

### Error Handling

Tools should:
- Exit with code 0 on success
- Exit with code 1 on errors
- Exit with code 1 on warnings (unless --no-fail-on-warnings)
- Print errors to stderr
- Print results to stdout

### Progress Reporting

For long-running operations, provide progress feedback:

```zig
fn progressCallback(current: u32, total: u32, item: []const u8) void {
    const stderr = std.io.getStdErr().writer();
    stderr.print("\rProcessing {}/{}: {s}", .{current, total, item}) catch {};
}
```

## Troubleshooting

### Tool Compilation Errors

If a tool fails to compile:

1. Run `zig build validate-tools` locally to see the error
2. Check that all imports are correct
3. Ensure the tool is properly added to `tools_to_validate` array
4. Verify the zig-tooling module is imported correctly

### CI Failures

If CI fails on the validate-tools job:

1. Check the GitHub Actions logs for specific errors
2. Ensure the tool compiles on all platforms (test with cross-compilation)
3. Verify no platform-specific code without proper guards

## Best Practices

1. **Keep tools focused**: Each tool should have a single, clear purpose
2. **Reuse library code**: Use zig-tooling's APIs rather than reimplementing
3. **Test thoroughly**: Tools are part of the user experience and must work reliably
4. **Document clearly**: Good --help output and examples are essential
5. **Handle errors gracefully**: Provide clear error messages to help users

## Release Checklist

Before releasing a new version with tool changes:

- [ ] All tools compile without warnings
- [ ] Tools pass validation on all platforms
- [ ] Documentation is updated
- [ ] Examples work correctly
- [ ] CI/CD passes all checks
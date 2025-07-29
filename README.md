# Zig Tooling

[![Zig Version](https://img.shields.io/badge/Zig-0.14.1-orange.svg)](https://ziglang.org)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Latest Release](https://img.shields.io/badge/Release-v0.1.5-green.svg)](https://github.com/yourusername/zig-tooling/releases)

A powerful code analysis library for Zig that catches memory leaks, validates testing patterns, and ensures code quality - integrated directly into your build process.

## 🚀 Quick Start

Add zig-tooling to your project in under 5 minutes:

```bash
# Add the dependency
zig fetch --save https://github.com/yourusername/zig-tooling/archive/refs/tags/v0.1.5.tar.gz

# Run your first analysis
zig build quality
```

That's it! The library will analyze your code and report any issues found.

## ✨ Features

### 🔍 Memory Safety Analysis
Catch memory issues before they reach production:
- **Missing defer statements** - Detects allocations without cleanup
- **Allocator mismatches** - Ensures allocations and frees use the same allocator
- **Ownership transfer tracking** - Smart detection of factory/builder patterns
- **Arena allocator validation** - Prevents misuse of arena allocators

```zig
// ❌ Detected: Missing defer
const data = try allocator.alloc(u8, 100);
// Missing: defer allocator.free(data);

// ✅ Correctly handled
const buffer = try allocator.alloc(u8, 100);
defer allocator.free(buffer);
```

### 🧪 Testing Compliance
Enforce consistent testing patterns:
- **Test categorization** - Organize tests as unit, integration, e2e, etc.
- **Naming conventions** - Ensure descriptive test names
- **Memory safety in tests** - Validate proper cleanup in test code
- **Test organization** - Enforce test file structure

```zig
// ✅ Well-structured test
test "unit: Parser: handles empty input gracefully" {
    // Test implementation
}
```

### 🛠️ Deep Integration

**Build System Integration**
```zig
// In your build.zig
const quality_step = b.step("quality", "Run code quality checks");
const quality_check = b.addExecutable(.{
    .name = "quality_check",
    .root_source_file = b.path("tools/quality_check.zig"),
});
quality_check.root_module.addImport("zig_tooling", zig_tooling_dep.module("zig_tooling"));
quality_step.dependOn(&b.addRunArtifact(quality_check).step);
```

**Programmatic API**
```zig
const zig_tooling = @import("zig_tooling");

// Analyze a file
const result = try zig_tooling.analyzeFile(allocator, "src/main.zig", null);
defer allocator.free(result.issues);

// Check for errors
if (result.hasErrors()) {
    // Handle issues
}
```

## 📦 Installation

### Using `zig fetch` (Recommended)

```bash
zig fetch --save https://github.com/yourusername/zig-tooling/archive/refs/tags/v0.1.5.tar.gz
```

### Manual Installation

1. Add to your `build.zig.zon`:
```zig
.dependencies = .{
    .zig_tooling = .{
        .url = "https://github.com/yourusername/zig-tooling/archive/refs/tags/v0.1.5.tar.gz",
        .hash = "...", // Use the hash from zig fetch
    },
},
```

2. Import in your `build.zig`:
```zig
const zig_tooling_dep = b.dependency("zig_tooling", .{
    .target = target,
    .optimize = optimize,
});
```

## 📖 Documentation

### Getting Started
- [**Quick Start Guide**](docs/getting-started.md) - Get up and running in minutes
- [**Implementation Guide**](docs/implementation-guide.md) - Detailed setup instructions
- [**Examples**](examples/) - Ready-to-use code examples

### Reference
- [**API Reference**](docs/api-reference.md) - Complete API documentation
- [**Configuration Guide**](docs/claude-integration.md) - All configuration options
- [**User Guide**](docs/user-guide.md) - Comprehensive usage guide

### Advanced Topics
- [**Build Integration**](docs/implementation-guide.md#build-system-integration) - Integrate with your build system
- [**CI/CD Setup**](docs/implementation-guide.md#cicd-setup) - GitHub Actions, GitLab CI examples
- [**Custom Patterns**](examples/advanced/custom_patterns.zig) - Configure for your project

## 🎯 Examples

### Basic Analysis
```zig
const zig_tooling = @import("zig_tooling");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Analyze entire project
    const result = try zig_tooling.patterns.checkProject(allocator, ".", null, null);
    defer zig_tooling.patterns.freeProjectResult(allocator, result);
    
    std.debug.print("Analyzed {} files, found {} issues\n", .{
        result.files_analyzed, result.issues_found
    });
}
```

### Custom Configuration
```zig
const config = zig_tooling.Config{
    .memory = .{
        .allowed_allocators = &.{ "MyCustomAllocator" },
        .allocator_patterns = &.{
            .{ .name = "MyCustomAllocator", .pattern = "my_alloc" },
        },
    },
    .testing = .{
        .allowed_categories = &.{ "unit", "integration", "benchmark" },
    },
};

const result = try zig_tooling.analyzeFile(allocator, "src/main.zig", config);
```

More examples:
- [**Quickstart Project**](examples/quickstart/) - Complete project setup
- [**Custom Patterns**](examples/advanced/custom_patterns.zig) - Advanced configuration
- [**CI Integration**](examples/advanced/ci_github_actions.yml) - GitHub Actions workflow
- [**Build Integration**](examples/build_integration.zig) - Build system setup

## 🤔 Why zig-tooling?

- **Catch bugs early** - Find memory leaks and issues during development
- **Enforce standards** - Maintain consistent code quality across teams
- **Zero overhead** - Analysis happens at build time, not runtime
- **Deep Zig integration** - Built specifically for Zig's patterns and idioms
- **Fully configurable** - Adapt to your project's specific needs

## 🛣️ Roadmap

- [x] Memory safety analysis
- [x] Testing compliance
- [x] Build system integration
- [x] Custom allocator patterns
- [ ] Performance profiling integration
- [ ] IDE plugins (VSCode, Sublime)
- [ ] Web dashboard for metrics

## 🤝 Contributing

We welcome contributions! See our [Contributing Guide](CONTRIBUTING.md) for details.

Quick links:
- [Report a bug](https://github.com/yourusername/zig-tooling/issues)
- [Request a feature](https://github.com/yourusername/zig-tooling/issues)
- [Submit a PR](https://github.com/yourusername/zig-tooling/pulls)

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

## 🙏 Acknowledgments

Built with inspiration from:
- The Zig community for excellent tooling ideas
- Static analysis tools like clippy and pylint
- Memory safety tools like valgrind and AddressSanitizer

---

**Ready to improve your Zig code quality?** Start with our [Getting Started Guide](docs/getting-started.md) →
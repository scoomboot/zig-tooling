# zig-tooling Examples

This directory contains practical examples demonstrating various ways to integrate and use zig-tooling in your projects. Examples range from basic usage to advanced CI/CD integration.

## 📁 Example Categories

### 🚀 Quickstart
**[quickstart/](quickstart/)** - Complete project example
- Full project structure with build.zig and build.zig.zon
- Ready-to-run quality check tool
- Demonstrates both correct code and intentional issues
- Perfect starting point for new projects

**What you'll learn:**
- How to structure a project with zig-tooling
- Basic configuration and setup
- Running quality checks
- Understanding analysis output

### 🔧 Individual Examples

#### [basic_usage.zig](basic_usage.zig)
Simple, standalone example showing core functionality.

**Use case:** Quick reference for common analysis tasks
- File and source analysis
- Basic configuration
- Error handling patterns
- Memory cleanup

**Run it:**
```bash
zig run --dep zig_tooling -Mroot=examples/basic_usage.zig -Mzig_tooling=src/zig_tooling.zig
```

#### [build_integration.zig](build_integration.zig)
Demonstrates integration with Zig's build system.

**Use case:** Adding quality checks to your build process
- Creating quality check build steps
- Multiple check configurations (memory, tests, all)
- Custom build targets
- Pre-commit hook installation

**Key features:**
- Separate steps for memory and test checks
- Configurable output formats
- Integration with existing build pipeline

#### [ci_integration.zig](ci_integration.zig)
Shows how to format output for CI/CD systems.

**Use case:** Automated quality checks in CI pipelines
- GitHub Actions annotation format
- JUnit XML output for GitLab/Jenkins
- JSON output for custom processing
- Error code management

**Supports:**
- GitHub Actions
- GitLab CI
- Jenkins
- Custom CI systems

#### [custom_analyzer.zig](custom_analyzer.zig)
Build your own specialized analyzer using zig-tooling components.

**Use case:** Project-specific code analysis rules
- Creating custom analysis rules
- Using ScopeTracker for AST navigation  
- Implementing domain-specific checks
- Extending built-in functionality

**Example checks:**
- Function naming conventions
- Project-specific patterns
- Custom memory management rules

#### [ide_integration.zig](ide_integration.zig)
Template for IDE/editor plugin development.

**Use case:** Real-time code analysis in editors
- Language Server Protocol (LSP) integration
- Real-time error reporting
- Code action suggestions
- Performance optimizations for interactive use

**Compatible with:**
- VS Code
- Neovim
- Sublime Text
- Any LSP-compatible editor

### 🚄 Advanced Examples
**[advanced/](advanced/)** - Sophisticated integration patterns

#### [custom_patterns.zig](advanced/custom_patterns.zig)
Advanced configuration for complex projects.

**What it demonstrates:**
- Custom allocator detection patterns
- Project-specific ownership rules
- Pattern conflict resolution
- Disabling default patterns

**Use cases:**
- Projects with custom allocators
- Non-standard memory management
- Domain-specific patterns

#### [ci_github_actions.yml](advanced/ci_github_actions.yml)
Production-ready GitHub Actions workflow.

**Features:**
- Parallel job execution
- Caching for performance
- Multi-version testing
- PR comment integration
- Release automation

**Workflow includes:**
- Basic quality checks
- Performance regression detection
- Coverage reporting
- Release preparation

#### [pre_commit_setup.zig](advanced/pre_commit_setup.zig)
Git pre-commit hook installer.

**Capabilities:**
- Multi-shell support (bash, fish, PowerShell)
- Selective file checking
- Performance optimizations
- Easy installation/removal

**Usage:**
```bash
zig run advanced/pre_commit_setup.zig
```

## 🎯 Which Example Should I Start With?

### New to zig-tooling?
→ Start with **[quickstart/](quickstart/)**

### Adding to existing project?
→ Check **[basic_usage.zig](basic_usage.zig)** and **[build_integration.zig](build_integration.zig)**

### Setting up CI/CD?
→ See **[ci_integration.zig](ci_integration.zig)** and **[advanced/ci_github_actions.yml](advanced/ci_github_actions.yml)**

### Need custom rules?
→ Study **[custom_analyzer.zig](custom_analyzer.zig)** and **[advanced/custom_patterns.zig](advanced/custom_patterns.zig)**

### Building developer tools?
→ Review **[ide_integration.zig](ide_integration.zig)**

## 📝 Common Patterns

### Pattern 1: Basic Analysis
```zig
const result = try zig_tooling.analyzeFile(allocator, "main.zig", null);
defer allocator.free(result.issues);
```

### Pattern 2: Custom Configuration
```zig
const config = zig_tooling.Config{
    .memory = .{
        .allowed_allocators = &.{ "MyAllocator" },
    },
};
const result = try zig_tooling.analyzeFile(allocator, "main.zig", config);
```

### Pattern 3: Project-Wide Analysis
```zig
const result = try zig_tooling.patterns.checkProject(
    allocator, ".", config, progressCallback
);
defer zig_tooling.patterns.freeProjectResult(allocator, result);
```

### Pattern 4: Formatted Output
```zig
const output = try zig_tooling.formatters.formatAsText(allocator, result, .{
    .color = true,
    .verbose = true,
});
defer allocator.free(output);
```

## 🔧 Running Examples

Most examples can be run directly:

```bash
# Run basic example
zig run --dep zig_tooling -Mroot=examples/basic_usage.zig -Mzig_tooling=src/zig_tooling.zig

# Run with optimizations
zig run -O ReleaseFast --dep zig_tooling -Mroot=examples/basic_usage.zig -Mzig_tooling=src/zig_tooling.zig

# Build and run
zig build-exe --dep zig_tooling -Mroot=examples/custom_analyzer.zig -Mzig_tooling=src/zig_tooling.zig
./custom_analyzer
```

For the quickstart example:
```bash
cd examples/quickstart
zig build quality
```

## 📚 Learning Path

1. **Understand basics**: Read through `basic_usage.zig`
2. **Try quickstart**: Run the quickstart example
3. **Integrate**: Use `build_integration.zig` as template
4. **Configure**: Customize with patterns from `advanced/custom_patterns.zig`
5. **Automate**: Set up CI with `advanced/ci_github_actions.yml`
6. **Extend**: Build custom tools using `custom_analyzer.zig`

## 💡 Tips

- Always free memory as shown in examples
- Use ReleaseFast for better performance
- Start with default configuration, customize as needed
- Check example output comments to understand expected behavior
- Examples include intentional issues to demonstrate detection

## 🤝 Contributing Examples

Have a useful integration pattern? We welcome example contributions!

1. Follow existing example structure
2. Include comprehensive comments
3. Show both correct and incorrect patterns
4. Document expected output
5. Test with latest zig-tooling version

---

For more details, see the [main documentation](../docs/) or [API reference](../docs/api-reference.md).
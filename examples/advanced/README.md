# Advanced Examples - zig-tooling

This directory contains production-ready examples for sophisticated zig-tooling integration scenarios. These examples are designed for teams and projects that need custom analysis rules, automated workflows, and enterprise-grade quality enforcement.

## 📁 Example Files

### 🎯 custom_patterns.zig
**Advanced pattern configuration for complex projects**

This example demonstrates how to handle projects with non-standard memory management patterns, custom allocators, and domain-specific conventions.

**Use Cases:**
- 🏗️ **Custom Memory Management** - Projects using specialized allocators (pools, slabs, bump allocators)
- 🏭 **Domain-Specific Patterns** - Game engines, embedded systems, or high-performance computing
- 🔧 **Legacy Code Integration** - Adapting analysis for existing codebases with established patterns
- 🎨 **Framework Development** - Libraries with their own allocation conventions

**Key Features:**
- Define custom allocator detection patterns with regex-like matching
- Configure ownership transfer rules for your factory/builder patterns  
- Resolve pattern conflicts when defaults don't match your needs
- Disable specific built-in patterns that cause false positives
- Examples show both correct usage and intentional issues for testing

**What You'll Learn:**
```zig
// Custom allocator patterns for game engine
.allocator_patterns = &.{
    .{ .name = "ObjectPool", .pattern = "object_pool" },
    .{ .name = "FrameAllocator", .pattern = "frame_alloc" },
    .{ .name = "LevelAllocator", .pattern = "level_" },
},

// Ownership patterns for resource management
.ownership_patterns = &.{
    .{ 
        .function_pattern = "acquire",
        .return_type_pattern = "!*Resource",
        .description = "Resource acquisition pattern"
    },
},
```

### 🚀 ci_github_actions.yml
**Enterprise-grade GitHub Actions workflow**

A battle-tested CI/CD configuration that goes beyond basic checks to provide comprehensive quality gates, performance tracking, and automated reporting.

**Use Cases:**
- 📊 **Open Source Projects** - Professional CI/CD for community projects
- 🏢 **Enterprise Development** - Quality gates for production deployments
- 👥 **Team Collaboration** - Automated PR feedback and review assistance
- 📈 **Performance Tracking** - Regression detection across commits

**Workflow Features:**
1. **Smart Caching** - Dependencies and build artifacts cached for speed
2. **Parallel Execution** - Memory and test checks run simultaneously
3. **Matrix Testing** - Test against multiple Zig versions (0.13.0, 0.14.1, main)
4. **PR Integration** - Automatic comments on pull requests with issues found
5. **Performance Tracking** - Compare analysis time between branches
6. **Release Automation** - Generate quality reports for releases
7. **Badge Generation** - Update README badges with build status

**Advanced Capabilities:**
```yaml
# Performance regression detection
- name: Check Performance
  run: |
    CURRENT_TIME=$(zig build quality --summary json | jq '.analysis_time_ms')
    BASELINE_TIME=$(curl -s ${{ github.event.base.url }}/checks | jq '.analysis_time_ms')
    if (( CURRENT_TIME > BASELINE_TIME * 120 / 100 )); then
      echo "::warning::Performance regression detected (20% slower)"
    fi
```

### 🔐 pre_commit_setup.zig
**Intelligent git hook installer**

A sophisticated script that sets up pre-commit hooks with multi-shell support, performance optimizations, and team-friendly configuration.

**Use Cases:**
- 👨‍💻 **Individual Developers** - Catch issues before they reach the repository
- 👥 **Team Standards** - Enforce quality standards automatically
- 🚄 **Fast Feedback** - Get instant feedback on code quality
- 🛡️ **Security** - Prevent sensitive allocator misuse from being committed

**Features:**
- **Multi-Shell Support** - Works with bash, zsh, fish, and PowerShell
- **Incremental Checking** - Only analyzes staged files for speed
- **Configurable Strictness** - Can be set to warn or block commits
- **Skip Option** - `git commit --no-verify` for emergencies
- **Easy Management** - Install, update, and uninstall commands

**Usage Examples:**
```bash
# Install for current shell
zig run pre_commit_setup.zig

# Install for specific shell
zig run pre_commit_setup.zig --shell=fish

# Install in warning mode (doesn't block commits)
zig run pre_commit_setup.zig --mode=warn

# Update existing hook
zig run pre_commit_setup.zig --update

# Remove hook
zig run pre_commit_setup.zig --uninstall
```

**Hook Behavior:**
- Runs only on `.zig` files
- Shows clear, actionable error messages
- Provides instructions to bypass when needed
- Integrates with your project's build configuration

## 💡 Integration Strategies

### Starting with Custom Patterns

1. **Baseline Analysis** - Run with defaults to understand current state
2. **Identify Patterns** - Note false positives and missing detections
3. **Configure Patterns** - Add custom patterns iteratively
4. **Test Thoroughly** - Ensure patterns don't hide real issues
5. **Document Decisions** - Explain why patterns were added

### Rolling Out CI/CD

1. **Start Simple** - Use basic quality check first
2. **Add Caching** - Improve performance with smart caching
3. **Enable Parallelism** - Run checks concurrently
4. **Add PR Comments** - Help reviewers with automated feedback
5. **Track Metrics** - Monitor performance over time

### Pre-commit Hook Adoption

1. **Team Discussion** - Agree on standards first
2. **Soft Launch** - Start with warning mode
3. **Gradual Enforcement** - Move to blocking mode after comfort period
4. **Provide Escape Hatches** - Document `--no-verify` for emergencies
5. **Monitor Feedback** - Adjust based on team experience

## 🔧 Common Customization Scenarios

### Embedded Systems Project
```zig
// No heap allocation allowed
.memory = .{
    .allowed_allocators = &.{ "FixedBufferAllocator" },
    .allocator_patterns = &.{
        .{ .name = "FixedBufferAllocator", .pattern = "fixed_buf" },
    },
},
```

### Game Engine
```zig
// Frame-based allocation patterns
.ownership_patterns = &.{
    .{ .function_pattern = "spawnEntity", .description = "Entity creation" },
    .{ .function_pattern = "loadAsset", .description = "Asset loading" },
},
.memory = .{
    .allowed_allocators = &.{ "FrameAllocator", "LevelAllocator", "AssetAllocator" },
},
```

### Web Server
```zig
// Request-scoped allocations
.memory = .{
    .allocator_patterns = &.{
        .{ .name = "RequestAllocator", .pattern = "req_alloc" },
    },
    .ownership_patterns = &.{
        .{ .function_pattern = "handleRequest", .description = "Request handler" },
    },
},
```

## 📊 Performance Considerations

- **Pattern Matching** - More patterns = slightly slower analysis
- **File Size** - Large files may benefit from incremental analysis  
- **CI Caching** - Can reduce workflow time by 70%
- **Pre-commit Scope** - Checking only staged files keeps it fast

## 🚦 Getting Started

1. **Choose Your Example** - Pick based on your immediate need
2. **Copy and Customize** - Adapt the example to your project
3. **Test Thoroughly** - Ensure it works with your workflow
4. **Iterate** - Refine based on team feedback
5. **Share** - Document your customizations for the team

## 📚 Further Reading

- [User Guide](../../docs/user-guide.md) - Comprehensive usage documentation
- [API Reference](../../docs/api-reference.md) - Detailed API documentation
- [Implementation Guide](../../docs/implementation-guide.md) - Step-by-step integration
- [Main Examples](../) - More example code

---

**Pro Tip:** These examples are designed to be mixed and matched. Use custom patterns with the CI workflow and pre-commit hooks for maximum effectiveness!
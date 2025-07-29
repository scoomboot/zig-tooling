# zig-tooling Documentation

Welcome to the comprehensive documentation for zig-tooling. This guide will help you navigate our documentation and find exactly what you need.

## 📚 Documentation Structure

### 🚀 Getting Started
**For new users who want to get up and running quickly**

1. [**Getting Started Guide**](getting-started.md) ⭐ *Start here!*
   - Prerequisites and installation
   - Your first quality check
   - Understanding the output
   - Common first-time issues

2. [**Implementation Guide**](implementation-guide.md)
   - Detailed setup instructions
   - Build system integration
   - CI/CD configuration
   - Migration strategies

### 📖 Core Documentation
**Essential guides for effective usage**

3. [**User Guide**](user-guide.md)
   - Configuration deep dive
   - All analysis features explained
   - Performance optimization
   - Team adoption strategies

4. [**API Reference**](api-reference.md)
   - Complete API documentation
   - Type definitions
   - Code examples
   - Memory management patterns

### 🔧 Specialized Guides
**Deep dives into specific topics**

5. [**Configuration Guide**](claude-integration.md)
   - All configuration options
   - Pattern examples
   - Advanced scenarios
   - Best practices

6. [**Scope Tracking Guide**](scope-tracking-guide.md)
   - Technical implementation details
   - How scope analysis works
   - Integration patterns
   - Performance considerations

7. [**Integration Tests Guide**](integration-tests.md)
   - Test suite architecture
   - Resource requirements and limits
   - Running tests locally vs CI
   - Troubleshooting and debugging

### 📊 Analysis & Planning
**Understanding the project**

8. [**Current State Analysis**](analysis/tooling-current-state.md)
   - Honest assessment of capabilities
   - Known limitations
   - Performance characteristics
   - Future roadmap

9. [**Library Conversion Plan**](implementation/library-conversion-plan.md)
   - Architecture overview
   - Migration from CLI tools
   - Design decisions
   - Implementation phases

## 🗺️ Reading Paths

### "I'm new to zig-tooling"
1. Start with [Getting Started](getting-started.md)
2. Try the [Quickstart Example](../examples/quickstart/)
3. Read the [User Guide](user-guide.md) for configuration
4. Check [Examples](../examples/) for patterns

### "I need to integrate into my build"
1. Jump to [Implementation Guide](implementation-guide.md#build-system-integration)
2. See [Build Integration Example](../examples/build_integration.zig)
3. Configure using [User Guide](user-guide.md#build-system-integration)

### "I want custom analysis rules"
1. Read [Custom Patterns](user-guide.md#custom-allocator-patterns) in User Guide
2. Study [Advanced Examples](../examples/advanced/)
3. Check [API Reference](api-reference.md) for types
4. See [Configuration Guide](../CLAUDE.md) for all options

### "Setting up CI/CD"
1. Go to [CI/CD Setup](implementation-guide.md#cicd-setup)
2. Copy [GitHub Actions Example](../examples/advanced/ci_github_actions.yml)
3. Read about [Output Formats](api-reference.md#formatters)

### "Understanding how it works"
1. Read [Scope Tracking Guide](scope-tracking-guide.md)
2. Review [Current State](analysis/tooling-current-state.md)
3. Explore [API internals](api-reference.md#analyzers)

## 🔍 Quick Links by Topic

### Configuration
- [Basic Configuration](user-guide.md#configuration-deep-dive)
- [Memory Settings](user-guide.md#memory-configuration)
- [Testing Settings](user-guide.md#testing-configuration)
- [All Options](claude-integration.md)

### Patterns
- [Allocator Patterns](user-guide.md#custom-allocator-patterns)
- [Ownership Patterns](user-guide.md#ownership-transfer-patterns)
- [Pattern Examples](../examples/advanced/custom_patterns.zig)

### Integration
- [Build System](implementation-guide.md#build-system-integration)
- [CI/CD](implementation-guide.md#cicd-setup)
- [IDE Integration](../examples/ide_integration.zig)
- [Pre-commit Hooks](../examples/advanced/pre_commit_setup.zig)

### Performance
- [Optimization Tips](user-guide.md#performance-optimization)
- [Large Codebases](user-guide.md#large-codebase-strategies)
- [Build Settings](implementation-guide.md#performance-optimization)

### Troubleshooting
- [Common Issues](getting-started.md#common-first-time-issues)
- [FAQ](user-guide.md#troubleshooting)
- [Debug Mode](user-guide.md#debug-mode)
- [Integration Test Issues](integration-tests.md#troubleshooting)

## 📝 Documentation Versions

- **Current**: v0.1.5 (Latest release)
- **Minimum Zig Version**: 0.14.1
- **Last Updated**: See individual file timestamps

## 🤝 Contributing to Documentation

Found an issue or want to improve the docs?

1. **Report Issues**: [GitHub Issues](https://github.com/yourusername/zig-tooling/issues)
2. **Submit PRs**: Documentation improvements always welcome
3. **Ask Questions**: [GitHub Discussions](https://github.com/yourusername/zig-tooling/discussions)

## 📋 Documentation TODO

- [ ] Video tutorials
- [ ] Migration guide from other tools
- [ ] Cookbook with recipes
- [ ] Troubleshooting decision tree
- [ ] Performance benchmarks

---

**Can't find what you need?** Check the [examples](../examples/) or ask in [discussions](https://github.com/yourusername/zig-tooling/discussions)!
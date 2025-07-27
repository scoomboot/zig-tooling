# Zig Tooling - Code Quality Analysis Library for Zig

A comprehensive library for code quality and analysis in Zig projects, providing memory safety validation, testing compliance checks, and logging capabilities.

## Features

### Memory Analyzer
- Validates allocator usage, defer cleanup, and memory safety patterns
- Ownership transfer pattern detection
- Arena allocator pattern support
- Test allocator pattern recognition

### Testing Analyzer
- Enforces test naming conventions and memory safety in tests
- Categorizes tests by type (Unit, Integration, Simulation, etc.)
- Validates test organization and colocation

### Logging System
- Structured logging with consistent format
- Auto-rotation (10MB files, 5 archives)
- Multiple log levels and categories
- Log file statistics and monitoring

## Library Conversion Notice

**This project is currently being converted from CLI tools to a pure Zig library package.**

The library conversion will provide:
- Direct integration into Zig projects via build.zig
- Programmatic API for all analysis functionality
- Better performance without process spawning overhead
- Type-safe interfaces for analysis results
- Composable analyzers for custom tooling

See [Library Conversion Plan](docs/implementation/library-conversion-plan.md) for details.

## Known Limitations

- Pattern-based detection may flag legitimate patterns
- Single-file analysis has minor memory leak (acceptable for CLI usage)
- See issue tracker for current known issues

## Documentation

- [Configuration Guide](docs/configuration.md) - Complete configuration reference
- [Scope Tracking Guide](docs/scope-tracking-guide.md) - Implementation details
- [Current State](docs/analysis/tooling-current-state.md) - Honest assessment of tool capabilities
- [Issue Tracker](docs/issue-tracker/README.md) - Report and track issues
- [Library Conversion Plan](docs/implementation/library-conversion-plan.md) - Library conversion details

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create your feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) file for details
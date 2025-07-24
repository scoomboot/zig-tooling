# Zig Tooling - Code Quality Analysis Tools for Zig

A comprehensive suite of code quality and analysis tools for Zig projects, providing memory safety validation, testing compliance checks, and unified logging capabilities.

## Features

### Memory Checker
- Validates allocator usage, defer cleanup, and memory safety patterns
- Ownership transfer pattern detection
- Arena allocator pattern support
- Test allocator pattern recognition
- 47% false positive reduction with enhanced scope tracking
- Performance: ~3.23ms per file with ReleaseFast builds

### Testing Compliance
- Enforces test naming conventions and memory safety in tests
- Categorizes tests by type (Unit, Integration, Simulation, etc.)
- Validates test organization and colocation
- Performance: ~0.84ms per file with ReleaseFast builds

### Unified Logging System
- Structured logging with consistent format
- Auto-rotation (10MB files, 5 archives)
- Multiple log levels and categories
- Log file statistics and monitoring

## Quick Start

1. **Install the tools** (see Installation section below)
2. **Initialize configuration:**
   ```bash
   memory_checker_cli config init
   ```
3. **Run checks on your project:**
   ```bash
   memory_checker_cli scan
   testing_compliance_cli scan
   ```

## Installation

### Option 1: Download Pre-built Binaries (Recommended)

1. Download the latest release for your platform from the releases page
2. Extract the archive:
   ```bash
   tar xzf zig-tooling-v0.1.0-linux-x64.tar.gz
   ```
3. Add to PATH:
   ```bash
   export PATH="$PATH:$(pwd)/zig-tooling-v0.1.0-linux-x64/bin"
   ```
4. Verify installation:
   ```bash
   memory_checker_cli --version
   ```

### Option 2: Build from Source

Prerequisites:
- Zig 0.13.0 or later

```bash
git clone <repository-url>
cd zig-tooling
zig build -Doptimize=ReleaseFast install
```

This will install three executables to `zig-out/bin/`:
- `memory_checker_cli`
- `testing_compliance_cli`
- `app_logger_cli`

## Usage

### Memory Checker

Check a single file:
```bash
memory_checker_cli file src/main.zig
```

Scan entire project:
```bash
memory_checker_cli scan
```

Check specific directory:
```bash
memory_checker_cli check src/
```

### Testing Compliance

Check a single file:
```bash
testing_compliance_cli file src/test_main.zig
```

Scan entire project:
```bash
testing_compliance_cli scan
```

Check specific directory:
```bash
testing_compliance_cli check tests/
```

### App Logger

View log statistics:
```bash
app_logger_cli stats
```

Tail log file:
```bash
app_logger_cli tail logs/app.log 50
```

Rotate logs:
```bash
app_logger_cli rotate
```

## Configuration

The tools support flexible configuration through JSON files, environment variables, and command-line arguments. See the [Configuration Guide](docs/configuration.md) for complete details.

### Quick Configuration

1. **Create default configuration:**
   ```bash
   memory_checker_cli config init
   ```
   This creates `.zigtools.json` with sensible defaults.

2. **View current configuration:**
   ```bash
   memory_checker_cli config show
   ```

3. **Use custom configuration:**
   ```bash
   memory_checker_cli --config custom-config.json scan
   ```

### Configuration Options

Key settings you can configure:
- **Output format**: JSON or text output
- **Log paths**: Custom log file locations
- **Severity levels**: Error, warning, or info for different issue types
- **Skip patterns**: Files to exclude from analysis
- **Performance settings**: File size limits, log rotation

### Output Formats
All tools support JSON output for integration with CI/CD:
```bash
memory_checker_cli scan --json
testing_compliance_cli scan --json
```

## Integration

### Pre-commit Hook
Create `.git/hooks/pre-commit`:
```bash
#!/bin/sh
memory_checker_cli scan || exit 1
testing_compliance_cli scan || exit 1
```

### CI/CD Integration
Example GitHub Actions workflow:
```yaml
- name: Download Zig Tooling
  run: |
    wget https://github.com/your-org/zig-tooling/releases/download/v0.1.0/zig-tooling-v0.1.0-linux-x64.tar.gz
    tar xzf zig-tooling-v0.1.0-linux-x64.tar.gz
    echo "$PWD/zig-tooling-v0.1.0-linux-x64/bin" >> $GITHUB_PATH
    
- name: Run Memory Checks
  run: memory_checker scan
  
- name: Run Testing Compliance
  run: testing_compliance scan
```

### Editor Integration
For VSCode, add to `.vscode/tasks.json`:
```json
{
  "label": "Check Memory Safety",
  "type": "shell",
  "command": "memory_checker_cli",
  "args": ["file", "${file}"],
  "problemMatcher": []
}
```

## Performance

With ReleaseFast builds:
- Memory checker: ~3.23ms per file (49x improvement over Debug)
- Testing compliance: ~0.84ms per file (71x improvement over Debug)

## Known Limitations

- Pattern-based detection may flag legitimate patterns
- Single-file analysis has minor memory leak (acceptable for CLI usage)
- See issue tracker for current known issues

## Documentation

- [Configuration Guide](docs/configuration.md) - Complete configuration reference
- [User Guide](docs/user-guide/user-guide.md) - Comprehensive usage guide
- [Scope Tracking Guide](docs/scope-tracking-guide.md) - Implementation details
- [Current State](docs/analysis/tooling-current-state.md) - Honest assessment of tool capabilities
- [Issue Tracker](docs/issue-tracker/README.md) - Report and track issues

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create your feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) file for details
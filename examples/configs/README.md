# Configuration Examples

This directory contains example configuration files for the Zig Tooling Suite.

## Available Configurations

### default.json
The default configuration with balanced settings suitable for most projects.
- Text output with colors
- Standard severity levels
- Reasonable file size limits

### ci-strict.json
Strict configuration optimized for CI/CD pipelines:
- JSON output for machine parsing
- All issues treated as errors
- No color output
- Higher performance thresholds

### dev-relaxed.json
Relaxed configuration for development environments:
- Verbose logging
- All issues as warnings
- Higher file size limits
- Debug log level

### minimal.json
Minimal configuration showing that you only need to specify what you want to change.
The system will use defaults for all unspecified values.

## Usage

To use a configuration file:

```bash
# Specify config file with --config flag
memory_checker_cli --config examples/configs/ci-strict.json scan

# Or copy to project root as .zigtools.json
cp examples/configs/default.json .zigtools.json
memory_checker_cli scan  # Will auto-load .zigtools.json
```

## Configuration Precedence

Settings are applied in this order (later overrides earlier):
1. Built-in defaults
2. Configuration file
3. Environment variables
4. Command-line flags

## Creating Your Own Configuration

1. Start with one of these examples
2. Modify only the settings you need to change
3. Use `memory_checker_cli config validate your-config.json` to verify
4. Place in project root as `.zigtools.json` for automatic loading
# Integration Test Documentation

## Overview

The zig-tooling library includes a comprehensive integration test suite designed to validate the library's behavior in real-world scenarios. These tests go beyond unit testing to ensure that all components work correctly together and that the library performs well under various conditions.

## Test Suite Architecture

### Test Categories

The integration test suite is organized into six main test modules:

1. **test_integration_runner.zig** - Core test infrastructure and utilities
2. **test_real_project_analysis.zig** - End-to-end project analysis workflows
3. **test_build_system_integration.zig** - Build system helpers and output formatters
4. **test_memory_performance.zig** - Memory usage validation and performance benchmarks
5. **test_thread_safety.zig** - Concurrent analysis and thread safety validation
6. **test_error_boundaries.zig** - Error handling and edge case testing

### Sample Projects

The test suite includes four sample projects that simulate different real-world scenarios:

- **simple_memory_issues** - Basic memory leak patterns for testing detection
- **complex_multi_file** - Multi-file project with various code patterns
- **custom_allocators** - Projects using custom allocator implementations
- **build_integration_example** - Example of build system integration

## Resource Requirements

Integration tests are more resource-intensive than unit tests due to:

- **Memory Usage**: Tests analyze large files and run multiple concurrent operations
- **CPU Usage**: Thread safety tests spawn multiple threads for concurrent analysis
- **Disk I/O**: Tests create temporary projects and write analysis results
- **Time**: Performance benchmarks and stress tests take longer to complete

### CI Resource Limits

To ensure consistent test behavior across environments, the CI configuration enforces the following resource limits:

- **Memory**: 4GB container limit (with 3GB available to tests)
- **CPU**: 2 CPU cores
- **Timeout**: 30 minutes for the entire integration test suite

These limits are configured in `.github/workflows/ci.yml` using Docker container options:

```yaml
container:
  image: ubuntu:22.04
  options: --memory 4g --cpus 2
```

### Environment Variables

The following environment variables control test behavior:

- `ZTOOL_TEST_MAX_MEMORY_MB` - Maximum memory tests should allocate (default: 3072)
- `ZTOOL_TEST_MAX_THREADS` - Maximum concurrent threads for tests (default: 4)

## Running Integration Tests

### Local Development

To run integration tests locally:

```bash
# Run all integration tests
zig build test-integration

# Run with verbose output
zig build test-integration --summary all
```

### CI/CD Pipeline

Integration tests run automatically on:
- Every push to `main` or `develop` branches
- All pull requests
- Manual workflow dispatch

The tests run in a controlled container environment to ensure reproducibility.

## Performance Targets

The integration tests validate the following performance targets:

1. **Simple Analysis**: < 100ms for basic file analysis
2. **Complex Analysis**: < 500ms for files with many allocations
3. **Large Files**: Linear scaling with file size (< 2ms per line)
4. **Concurrent Operations**: No race conditions or memory corruption
5. **Memory Usage**: No memory leaks detected by GeneralPurposeAllocator

## Troubleshooting

### Common Issues

1. **Out of Memory Errors**
   - Ensure you have at least 4GB of available RAM
   - Check that no other memory-intensive processes are running
   - Consider running tests sequentially rather than in parallel

2. **Timeout Failures**
   - Performance tests may fail on slower hardware
   - Try increasing timeout values for local testing
   - Ensure no background processes are consuming CPU

3. **Thread Safety Test Failures**
   - May indicate actual race conditions in the library
   - Run with `--test-filter "thread safety"` to isolate the issue
   - Use thread sanitizers if available

4. **File System Errors**
   - Ensure sufficient disk space for temporary files
   - Check file system permissions
   - Clean up any leftover test artifacts

### Debug Mode

For detailed test output during debugging:

```bash
# Enable debug prints
export ZTOOL_TEST_DEBUG=1
zig build test-integration

# Run specific test
zig build test-integration --test-filter "memory leak detection"
```

## Test Maintenance

### Adding New Integration Tests

1. Create test file in `tests/integration/`
2. Import `test_integration_runner.zig` for utilities
3. Follow existing patterns for test organization
4. Update this documentation if adding new test categories

### Updating Resource Limits

If tests require more resources:

1. Update container options in `.github/workflows/ci.yml`
2. Adjust environment variables as needed
3. Document the changes and rationale
4. Ensure tests still pass on typical developer machines

## Best Practices

1. **Isolation**: Each test should clean up its resources
2. **Determinism**: Tests should produce consistent results
3. **Performance**: Keep test execution time reasonable
4. **Coverage**: Test both success and failure scenarios
5. **Documentation**: Comment complex test scenarios

## CI Integration Details

### GitHub Actions Workflow

The integration tests are part of the main CI pipeline with:

- Dedicated job: `integration-tests`
- Container-based execution for resource isolation
- Dependency caching for faster builds
- Parallel execution with other test jobs

### Resource Monitoring

While GitHub Actions doesn't provide detailed resource usage metrics, the container limits ensure tests don't exceed available resources. Monitor for:

- Job duration trends
- Memory-related failures
- Timeout occurrences

### Optimization Opportunities

1. **Parallel Test Execution**: Tests within modules run sequentially but modules could run in parallel
2. **Incremental Testing**: Only run tests affected by changes
3. **Resource Pooling**: Share expensive resources between tests
4. **Test Data Caching**: Cache generated test projects

## Related Documentation

- [Getting Started Guide](getting-started.md) - Basic library usage
- [Implementation Guide](implementation-guide.md) - Detailed setup instructions
- [API Reference](api-reference.md) - Complete API documentation
- [CI/CD Workflow](.github/workflows/ci.yml) - GitHub Actions configuration
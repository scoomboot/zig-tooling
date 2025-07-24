# Sample Project - Zig Tooling Examples

This directory contains example files demonstrating common issues that the Zig tooling can detect.

## Files

- **memory_issues.zig** - Examples of memory management issues:
  - Missing `defer` statements
  - Missing `errdefer` for error handling
  - Proper memory management patterns

- **test_examples.zig** - Examples of testing compliance issues:
  - Improperly named tests
  - Tests without proper categorization
  - Good examples of categorized tests

- **.zigtools** - Example configuration file (future feature)

## Running the Tools

From this directory:

```bash
# Check for memory issues
memory_checker_cli file memory_issues.zig

# Check testing compliance
testing_compliance_cli file test_examples.zig

# Scan the entire sample project
memory_checker_cli scan
testing_compliance_cli scan
```

## Expected Results

### Memory Checker
Should detect:
- Missing `defer` in `leakyFunction`
- Missing `errdefer` in `riskyOperation`
- Recognize proper ownership transfer in `goodExample`

### Testing Compliance
Should detect:
- `testSomething` function not following test naming convention
- Test "something without category" lacking proper categorization
- Recognize properly categorized tests
#\!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Zig Tooling Test Suite ==="
echo "Project root: $PROJECT_ROOT"
echo ""

cd "$PROJECT_ROOT"

FAILED_TESTS=0
TOTAL_TESTS=0

echo "Running all tests..."
echo ""

if zig build test 2>&1  < /dev/null |  tee test-output.tmp; then
    echo ""
    echo "✓ All tests passed!"
    TEST_SUCCESS=true
else
    echo ""
    echo "✗ Some tests failed!"
    TEST_SUCCESS=false
    FAILED_TESTS=1
fi

if [ -f test-output.tmp ]; then
    PASSED=$(grep -c "passed" test-output.tmp 2>/dev/null || echo "0")
    rm -f test-output.tmp
fi

echo ""
echo "=== Test Summary ==="
echo "Zig version: $(zig version)"
echo "Platform: $(uname -s) $(uname -m)"
echo ""

if [ "$TEST_SUCCESS" = true ]; then
    echo "Status: SUCCESS"
    exit 0
else
    echo "Status: FAILED"
    echo ""
    echo "To run individual test files:"
    echo "  zig test tests/test_memory_checker_cli.zig"
    echo "  zig test tests/test_testing_compliance_cli.zig"
    echo "  zig test tests/test_app_logger_cli.zig"
    echo "  zig test tests/test_scope_integration.zig"
    exit 1
fi

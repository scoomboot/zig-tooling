#\!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/zig-out"
DIST_DIR="$PROJECT_ROOT/dist"

echo "=== Zig Tooling Release Build ==="
echo "Project root: $PROJECT_ROOT"
echo ""

cd "$PROJECT_ROOT"

echo "Step 1: Cleaning previous builds..."
rm -rf "$BUILD_DIR"
rm -rf "$DIST_DIR"

echo "Step 2: Running tests..."
zig build test || {
    echo "ERROR: Tests failed\!"
    exit 1
}

echo "Step 3: Building release binaries..."
zig build -Doptimize=ReleaseFast install || {
    echo "ERROR: Build failed\!"
    exit 1
}

echo "Step 4: Creating distribution directory..."
mkdir -p "$DIST_DIR/bin"

echo "Step 5: Copying binaries..."
cp "$BUILD_DIR/bin/memory_checker_cli" "$DIST_DIR/bin/memory_checker"
cp "$BUILD_DIR/bin/testing_compliance_cli" "$DIST_DIR/bin/testing_compliance"
cp "$BUILD_DIR/bin/app_logger_cli" "$DIST_DIR/bin/app_logger"

echo "Step 6: Stripping debug symbols..."
if command -v strip >/dev/null 2>&1; then
    strip "$DIST_DIR/bin/memory_checker"
    strip "$DIST_DIR/bin/testing_compliance"
    strip "$DIST_DIR/bin/app_logger"
    echo "Debug symbols stripped"
else
    echo "WARNING: 'strip' command not found, skipping symbol stripping"
fi

echo "Step 7: Generating checksums..."
cd "$DIST_DIR"
if command -v sha256sum >/dev/null 2>&1; then
    sha256sum bin/* > checksums.txt
elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 bin/* > checksums.txt
else
    echo "WARNING: No checksum utility found (sha256sum or shasum)"
fi

echo "Step 8: Build information..."
echo "Built on: $(date)" > build-info.txt
echo "Zig version: $(zig version)" >> build-info.txt
echo "Platform: $(uname -s) $(uname -m)" >> build-info.txt

echo ""
echo "=== Build Complete ==="
echo "Distribution files created in: $DIST_DIR"
echo ""
echo "Binaries:"
ls -lh "$DIST_DIR/bin/"
echo ""
if [ -f "$DIST_DIR/checksums.txt" ]; then
    echo "Checksums:"
    cat "$DIST_DIR/checksums.txt"
fi

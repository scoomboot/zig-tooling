#\!/bin/bash

set -euo pipefail

VERSION="${1:-0.1.0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
RELEASE_DIR="$PROJECT_ROOT/releases"

echo "=== Zig Tooling Release Packaging ==="
echo "Version: $VERSION"
echo "Project root: $PROJECT_ROOT"
echo ""

if [ \! -d "$DIST_DIR/bin" ]; then
    echo "ERROR: Distribution directory not found. Run build-release.sh first\!"
    exit 1
fi

cd "$PROJECT_ROOT"

echo "Step 1: Creating release directory..."
mkdir -p "$RELEASE_DIR"

PLATFORM="$(uname -s  < /dev/null |  tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

if [ "$ARCH" = "x86_64" ]; then
    ARCH="x64"
elif [ "$ARCH" = "aarch64" ]; then
    ARCH="arm64"
fi

ARCHIVE_NAME="zig-tooling-v${VERSION}-${PLATFORM}-${ARCH}"
ARCHIVE_DIR="$RELEASE_DIR/$ARCHIVE_NAME"

echo "Step 2: Preparing archive directory..."
rm -rf "$ARCHIVE_DIR"
mkdir -p "$ARCHIVE_DIR/bin"

echo "Step 3: Copying binaries..."
cp -r "$DIST_DIR/bin/"* "$ARCHIVE_DIR/bin/"

echo "Step 4: Copying documentation..."
if [ -f "$PROJECT_ROOT/README.md" ]; then
    cp "$PROJECT_ROOT/README.md" "$ARCHIVE_DIR/"
else
    echo "WARNING: README.md not found"
fi

if [ -f "$PROJECT_ROOT/LICENSE" ]; then
    cp "$PROJECT_ROOT/LICENSE" "$ARCHIVE_DIR/"
else
    echo "WARNING: LICENSE not found"
fi

if [ -f "$PROJECT_ROOT/CHANGELOG.md" ]; then
    cp "$PROJECT_ROOT/CHANGELOG.md" "$ARCHIVE_DIR/"
else
    echo "WARNING: CHANGELOG.md not found"
fi

echo "Step 5: Creating archives..."
cd "$RELEASE_DIR"

echo "  - Creating tar.gz archive..."
tar czf "${ARCHIVE_NAME}.tar.gz" "$ARCHIVE_NAME"

echo "  - Creating zip archive..."
zip -qr "${ARCHIVE_NAME}.zip" "$ARCHIVE_NAME"

echo "Step 6: Generating release checksums..."
if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${ARCHIVE_NAME}.tar.gz" "${ARCHIVE_NAME}.zip" > "${ARCHIVE_NAME}-checksums.txt"
elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${ARCHIVE_NAME}.tar.gz" "${ARCHIVE_NAME}.zip" > "${ARCHIVE_NAME}-checksums.txt"
fi

echo "Step 7: Cleaning up temporary directory..."
rm -rf "$ARCHIVE_DIR"

echo ""
echo "=== Packaging Complete ==="
echo "Release archives created in: $RELEASE_DIR"
echo ""
echo "Archives:"
ls -lh "$RELEASE_DIR/${ARCHIVE_NAME}".*
echo ""
if [ -f "$RELEASE_DIR/${ARCHIVE_NAME}-checksums.txt" ]; then
    echo "Checksums:"
    cat "$RELEASE_DIR/${ARCHIVE_NAME}-checksums.txt"
fi

echo ""
echo "Installation instructions:"
echo "1. Extract archive: tar xzf ${ARCHIVE_NAME}.tar.gz"
echo "2. Add to PATH: export PATH=\"\$PATH:\$(pwd)/${ARCHIVE_NAME}/bin\""
echo "3. Verify installation: memory_checker --version"

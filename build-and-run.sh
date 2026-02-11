#!/bin/bash
set -e

# Configuration
APP_NAME="ClaudeChat"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
XCODEPROJ="$PROJECT_DIR/$APP_NAME.xcodeproj"
BUILD_DIR="$PROJECT_DIR/build"
DEST_DIR="/Applications"

echo "=== ClaudeChat Build Script ==="
echo ""

# Step 1: Kill existing process
echo "[1/4] Killing existing $APP_NAME process..."
pkill -x "$APP_NAME" 2>/dev/null && echo "  Killed running instance" || echo "  No running instance found"
sleep 0.5

# Step 2: Build web bundle (tiptap)
echo "[2/4] Building tiptap bundle..."
cd "$PROJECT_DIR/web"
npm run build --silent 2>/dev/null || ./build.sh
echo "  Done"

# Step 3: Build Xcode project
echo "[3/4] Building $APP_NAME..."
cd "$PROJECT_DIR"

# Clean derived data for this project
rm -rf ~/Library/Developer/Xcode/DerivedData/ClaudeChat-* 2>/dev/null || true

# Build using xcodebuild
xcodebuild -project "$XCODEPROJ" \
    -scheme "$APP_NAME" \
    -configuration Debug \
    -derivedDataPath "$BUILD_DIR" \
    clean build \
    ONLY_ACTIVE_ARCH=YES \
    2>&1 | grep -E "(Building|Compiling|Linking|error:|warning:|BUILD|✓)" || true

# Find the built app
BUILT_APP="$BUILD_DIR/Build/Products/Debug/$APP_NAME.app"

if [ ! -d "$BUILT_APP" ]; then
    echo "  ERROR: Build failed - app not found at $BUILT_APP"
    exit 1
fi
echo "  Build succeeded"

# Step 4: Copy to destination
echo "[4/4] Installing to $DEST_DIR..."
rm -rf "$DEST_DIR/$APP_NAME.app" 2>/dev/null || true
cp -R "$BUILT_APP" "$DEST_DIR/"
echo "  Installed to $DEST_DIR/$APP_NAME.app"

echo ""
echo "=== Build Complete ==="
echo ""

# Ask to launch
read -p "Launch $APP_NAME now? [Y/n] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    open "$DEST_DIR/$APP_NAME.app"
    echo "Launched!"
fi

#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_PATH="$SCRIPT_DIR/Recast.xcodeproj"
BUILD_DIR="$SCRIPT_DIR/build"
APP_SOURCE="$BUILD_DIR/Build/Products/Release/Recast.app"
APP_DEST="$REPO_ROOT/Recast.app"
OPEN_XCODE=false

for arg in "$@"; do
    case "$arg" in
        --open-xcode)
            OPEN_XCODE=true
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: ./setup.sh [--open-xcode]"
            exit 1
            ;;
    esac
done

cd "$SCRIPT_DIR"

# Check for Xcode command-line tools
if ! xcode-select -p &>/dev/null; then
    echo "Installing Xcode command-line tools..."
    xcode-select --install
    echo "After installation completes, re-run this script."
    exit 1
fi

# Install XcodeGen if needed
if ! command -v xcodegen &>/dev/null; then
    if command -v brew &>/dev/null; then
        echo "Installing XcodeGen via Homebrew..."
        brew install xcodegen
    else
        echo "XcodeGen is required but Homebrew is not installed."
        echo ""
        echo "Option 1: Install Homebrew first:"
        echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        echo "  Then re-run this script."
        echo ""
        echo "Option 2: Install XcodeGen manually:"
        echo "  https://github.com/yonaskolb/XcodeGen#installing"
        exit 1
    fi
fi

echo "Generating Xcode project..."
xcodegen generate

echo ""
echo "Building Release app bundle..."
xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme Recast \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    build

if [ ! -d "$APP_SOURCE" ]; then
    echo "Build completed but $APP_SOURCE was not found."
    exit 1
fi

echo ""
echo "Copying app bundle to repo root..."
rm -rf "$APP_DEST"
ditto "$APP_SOURCE" "$APP_DEST"

echo ""
echo "Revealing Recast.app in Finder..."
open -R "$APP_DEST"

echo ""
echo "Done! You can now move $APP_DEST into /Applications and double-click it to run."

if [ "$OPEN_XCODE" = true ]; then
    echo ""
    echo "Opening Recast.xcodeproj..."
    open "$PROJECT_PATH"
fi

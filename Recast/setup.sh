#!/bin/bash
set -e

cd "$(dirname "$0")"

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
echo "Opening Recast.xcodeproj..."
open Recast.xcodeproj

echo ""
echo "Done! Press Cmd+R in Xcode to build and run."

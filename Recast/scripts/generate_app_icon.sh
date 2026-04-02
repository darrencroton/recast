#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APPICONSET_DIR="$SCRIPT_DIR/../Recast/Assets.xcassets/AppIcon.appiconset"
MASTER_ICON=""
MASTER_ONLY=false
MASTER_SIZE=1024
OPAQUE_MASTER=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [--master PATH] [--master-only] [--appiconset-dir PATH] [--size PIXELS] [--opaque]

Renders the Recast app icon. By default it installs the rendered icon into
Recast/Recast/Assets.xcassets/AppIcon.appiconset.

Options:
  --master PATH        Write the rendered master PNG to PATH
  --master-only        Only write the master PNG; do not populate an app icon set
  --appiconset-dir DIR Write resized icon assets into DIR instead of the default app icon set
  --size PIXELS        Render the master artwork at the given square size
  --opaque             Render an opaque background instead of transparent margins
  --help               Show this help text
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --master)
            MASTER_ICON="${2:-}"
            shift 2
            ;;
        --master-only)
            MASTER_ONLY=true
            shift
            ;;
        --appiconset-dir)
            APPICONSET_DIR="${2:-}"
            shift 2
            ;;
        --size)
            MASTER_SIZE="${2:-}"
            shift 2
            ;;
        --opaque)
            OPAQUE_MASTER=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

cleanup() {
    if [[ -n "${TEMP_MASTER_ICON:-}" && -f "$TEMP_MASTER_ICON" ]]; then
        rm -f "$TEMP_MASTER_ICON"
    fi
}
trap cleanup EXIT

if [[ -z "$MASTER_ICON" ]]; then
    TEMP_MASTER_ICON="$(mktemp /tmp/recast-app-icon.XXXXXX.png)"
    MASTER_ICON="$TEMP_MASTER_ICON"
fi

mkdir -p "$(dirname "$MASTER_ICON")"
swift_args=(
    "$SCRIPT_DIR/render_app_icon.swift"
    "$MASTER_ICON"
    "--size" "$MASTER_SIZE"
)

if [[ "$OPAQUE_MASTER" == true ]]; then
    swift_args+=("--opaque")
fi

xcrun swift "${swift_args[@]}"

if [[ "$MASTER_ONLY" == false ]]; then
    mkdir -p "$APPICONSET_DIR"
    sips -z 16 16 "$MASTER_ICON" --out "$APPICONSET_DIR/app-icon-16.png" >/dev/null
    sips -z 32 32 "$MASTER_ICON" --out "$APPICONSET_DIR/app-icon-16@2x.png" >/dev/null
    sips -z 32 32 "$MASTER_ICON" --out "$APPICONSET_DIR/app-icon-32.png" >/dev/null
    sips -z 64 64 "$MASTER_ICON" --out "$APPICONSET_DIR/app-icon-32@2x.png" >/dev/null
    sips -z 128 128 "$MASTER_ICON" --out "$APPICONSET_DIR/app-icon-128.png" >/dev/null
    sips -z 256 256 "$MASTER_ICON" --out "$APPICONSET_DIR/app-icon-128@2x.png" >/dev/null
    sips -z 256 256 "$MASTER_ICON" --out "$APPICONSET_DIR/app-icon-256.png" >/dev/null
    sips -z 512 512 "$MASTER_ICON" --out "$APPICONSET_DIR/app-icon-256@2x.png" >/dev/null
    sips -z 512 512 "$MASTER_ICON" --out "$APPICONSET_DIR/app-icon-512.png" >/dev/null
    sips -z 1024 1024 "$MASTER_ICON" --out "$APPICONSET_DIR/app-icon-512@2x.png" >/dev/null
fi

echo "Rendered Recast app icon to $MASTER_ICON"
if [[ "$MASTER_ONLY" == false ]]; then
    echo "Updated app icon set at $APPICONSET_DIR"
fi

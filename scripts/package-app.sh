#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_VARIANT="${FRAME_APP_VARIANT:-production}"
APP_OUTPUT_ROOT="${FRAME_APP_OUTPUT_ROOT:-$ROOT_DIR/.build/app}"
PRINT_CONFIGURATION=false

case "${1:-}" in
    "")
        ;;
    --print-configuration)
        PRINT_CONFIGURATION=true
        ;;
    *)
        echo "Usage: $0 [--print-configuration]" >&2
        exit 64
        ;;
esac

if [[ $# -gt 1 ]]; then
    echo "Usage: $0 [--print-configuration]" >&2
    exit 64
fi

case "$APP_VARIANT" in
    production)
        APP_NAME="Frame"
        BUNDLE_IDENTIFIER="dev.deweyou.frame"
        ;;
    development)
        APP_NAME="Frame Dev"
        BUNDLE_IDENTIFIER="dev.deweyou.frame.dev"
        ;;
    *)
        echo "Unsupported FRAME_APP_VARIANT: $APP_VARIANT (expected production or development)" >&2
        exit 64
        ;;
esac

APP_DIR="$APP_OUTPUT_ROOT/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE_PATH="$ROOT_DIR/.build/release/Frame"
CODESIGN_IDENTITY="${FRAME_CODESIGN_IDENTITY:--}"
VERSION_SOURCE="$ROOT_DIR/Sources/FrameCore/FrameVersion.swift"
APP_RESOURCES_DIR="$ROOT_DIR/Sources/FrameApp/Resources"

if [[ "$PRINT_CONFIGURATION" == true ]]; then
    cat <<CONFIGURATION
FRAME_APP_VARIANT=$APP_VARIANT
FRAME_APP_NAME=$APP_NAME
FRAME_BUNDLE_ID=$BUNDLE_IDENTIFIER
FRAME_APP_PATH=$APP_DIR
CONFIGURATION
    exit 0
fi

cd "$ROOT_DIR"

FRAME_SHORT_VERSION="$(
    sed -n 's/.*public static let shortVersion = "\(.*\)".*/\1/p' "$VERSION_SOURCE"
)"
FRAME_BUILD="$(
    sed -n 's/.*public static let build = "\(.*\)".*/\1/p' "$VERSION_SOURCE"
)"

if [[ -z "$FRAME_SHORT_VERSION" || -z "$FRAME_BUILD" ]]; then
    echo "Unable to read Frame version constants from $VERSION_SOURCE" >&2
    exit 1
fi

swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_IDENTIFIER</string>
    <key>CFBundleExecutable</key>
    <string>Frame</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>Frame</string>
    <key>CFBundleShortVersionString</key>
    <string>$FRAME_SHORT_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$FRAME_BUILD</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

cp "$EXECUTABLE_PATH" "$MACOS_DIR/Frame"
chmod +x "$MACOS_DIR/Frame"

cp "$APP_RESOURCES_DIR/Frame.icns" "$RESOURCES_DIR/Frame.icns"
mkdir -p "$RESOURCES_DIR/menubar"
cp "$APP_RESOURCES_DIR"/menubar/FrameStatusIcon*.png "$RESOURCES_DIR/menubar/"
cp "$APP_RESOURCES_DIR"/menubar/FrameStatusIconTemplate*.png "$RESOURCES_DIR/"

codesign --force --sign "$CODESIGN_IDENTITY" "$APP_DIR"

echo "Packaged $APP_DIR"
echo "Variant: $APP_VARIANT ($BUNDLE_IDENTIFIER)"
if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
    echo "Signed with ad-hoc identity"
else
    echo "Signed with identity: $CODESIGN_IDENTITY"
fi

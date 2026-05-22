#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/app/Frame.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
EXECUTABLE_PATH="$ROOT_DIR/.build/release/Frame"
CODESIGN_IDENTITY="${FRAME_CODESIGN_IDENTITY:--}"

cd "$ROOT_DIR"

swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Frame</string>
    <key>CFBundleIdentifier</key>
    <string>dev.dewey.frame</string>
    <key>CFBundleExecutable</key>
    <string>Frame</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
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

codesign --force --sign "$CODESIGN_IDENTITY" "$APP_DIR"

echo "Packaged $APP_DIR"
if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
    echo "Signed with ad-hoc identity"
else
    echo "Signed with identity: $CODESIGN_IDENTITY"
fi

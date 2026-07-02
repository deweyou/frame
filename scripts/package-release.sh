#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_SOURCE="${FRAME_VERSION_SOURCE:-$ROOT_DIR/Sources/FrameCore/FrameVersion.swift}"
OUTPUT_ROOT="${FRAME_RELEASE_OUTPUT_DIR:-$ROOT_DIR/.build/release}"
PACKAGE_APP_SCRIPT="${FRAME_PACKAGE_APP_SCRIPT:-$ROOT_DIR/scripts/package-app.sh}"

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

ARTIFACT_NAME="Frame-$FRAME_SHORT_VERSION-build.$FRAME_BUILD"
RELEASE_DIR="$OUTPUT_ROOT/$ARTIFACT_NAME"
ZIP_PATH="$RELEASE_DIR/$ARTIFACT_NAME.zip"
DMG_PATH="$RELEASE_DIR/$ARTIFACT_NAME.dmg"
DMG_STAGE_DIR="$RELEASE_DIR/dmg-stage"
APP_DIR="$ROOT_DIR/.build/app/Frame.app"

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR" "$DMG_STAGE_DIR"

PACKAGE_SIGN_IDENTITY="${FRAME_RELEASE_CODESIGN_IDENTITY:-${FRAME_CODESIGN_IDENTITY:-}}"
if [[ -n "$PACKAGE_SIGN_IDENTITY" ]]; then
    FRAME_CODESIGN_IDENTITY="$PACKAGE_SIGN_IDENTITY" "$PACKAGE_APP_SCRIPT"
else
    "$PACKAGE_APP_SCRIPT"
    echo "Warning: release artifacts are ad-hoc signed because no signing identity was provided." >&2
fi

if [[ ! -d "$APP_DIR" ]]; then
    echo "Packaged app not found: $APP_DIR" >&2
    exit 1
fi

ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

ditto "$APP_DIR" "$DMG_STAGE_DIR/Frame.app"
ln -s /Applications "$DMG_STAGE_DIR/Applications"
hdiutil create \
    -volname "Frame $FRAME_SHORT_VERSION" \
    -srcfolder "$DMG_STAGE_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

(
    cd "$RELEASE_DIR"
    shasum -a 256 "$(basename "$ZIP_PATH")" "$(basename "$DMG_PATH")" > SHA256SUMS
)

rm -rf "$DMG_STAGE_DIR"

cat <<SUMMARY
Release artifacts created:
  $ZIP_PATH
  $DMG_PATH
  $RELEASE_DIR/SHA256SUMS
SUMMARY

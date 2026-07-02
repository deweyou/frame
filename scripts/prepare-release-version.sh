#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_SOURCE="${FRAME_VERSION_SOURCE:-$ROOT_DIR/Sources/FrameCore/FrameVersion.swift}"
BUMP_VERSION_SCRIPT="${FRAME_BUMP_VERSION_SCRIPT:-$ROOT_DIR/scripts/bump-version.sh}"

usage() {
    cat <<'USAGE'
Usage: scripts/prepare-release-version.sh patch|minor|major|custom [CUSTOM_VERSION]

Computes the next Frame version, increments the build number by one, and then
runs scripts/bump-version.sh. For custom releases, CUSTOM_VERSION must be a
numeric major.minor.patch version greater than the current version.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage >&2
    exit 64
fi

RELEASE_MODE="$1"
CUSTOM_VERSION="${2:-}"

if [[ ! -f "$VERSION_SOURCE" ]]; then
    echo "Version source not found: $VERSION_SOURCE" >&2
    exit 66
fi

CURRENT_SHORT_VERSION="$(
    sed -n 's/.*public static let shortVersion = "\(.*\)".*/\1/p' "$VERSION_SOURCE"
)"
CURRENT_BUILD="$(
    sed -n 's/.*public static let build = "\(.*\)".*/\1/p' "$VERSION_SOURCE"
)"

if [[ ! "$CURRENT_SHORT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Unable to read semantic version from $VERSION_SOURCE" >&2
    exit 65
fi

if [[ ! "$CURRENT_BUILD" =~ ^[0-9]+$ ]]; then
    echo "Unable to read integer build from $VERSION_SOURCE" >&2
    exit 65
fi

IFS=. read -r CURRENT_MAJOR CURRENT_MINOR CURRENT_PATCH <<< "$CURRENT_SHORT_VERSION"

semver_greater_than_current() {
    local candidate="$1"

    if [[ ! "$candidate" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 1
    fi

    local candidate_major candidate_minor candidate_patch
    IFS=. read -r candidate_major candidate_minor candidate_patch <<< "$candidate"

    if (( candidate_major > CURRENT_MAJOR )); then
        return 0
    fi
    if (( candidate_major < CURRENT_MAJOR )); then
        return 1
    fi
    if (( candidate_minor > CURRENT_MINOR )); then
        return 0
    fi
    if (( candidate_minor < CURRENT_MINOR )); then
        return 1
    fi
    (( candidate_patch > CURRENT_PATCH ))
}

case "$RELEASE_MODE" in
    patch)
        NEXT_SHORT_VERSION="$CURRENT_MAJOR.$CURRENT_MINOR.$((CURRENT_PATCH + 1))"
        ;;
    minor)
        NEXT_SHORT_VERSION="$CURRENT_MAJOR.$((CURRENT_MINOR + 1)).0"
        ;;
    major)
        NEXT_SHORT_VERSION="$((CURRENT_MAJOR + 1)).0.0"
        ;;
    custom)
        if [[ -z "$CUSTOM_VERSION" ]]; then
            echo "Custom release mode requires CUSTOM_VERSION" >&2
            exit 64
        fi
        if ! semver_greater_than_current "$CUSTOM_VERSION"; then
            echo "Custom version must be greater than current version $CURRENT_SHORT_VERSION" >&2
            exit 64
        fi
        NEXT_SHORT_VERSION="$CUSTOM_VERSION"
        ;;
    *)
        echo "Release mode must be one of: patch, minor, major, custom" >&2
        exit 64
        ;;
esac

NEXT_BUILD="$((CURRENT_BUILD + 1))"

"$BUMP_VERSION_SCRIPT" "$NEXT_SHORT_VERSION" "$NEXT_BUILD"

echo "FRAME_RELEASE_VERSION=$NEXT_SHORT_VERSION"
echo "FRAME_RELEASE_BUILD=$NEXT_BUILD"
echo "FRAME_RELEASE_ARTIFACT_NAME=Frame-$NEXT_SHORT_VERSION-build.$NEXT_BUILD"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
        echo "version=$NEXT_SHORT_VERSION"
        echo "build=$NEXT_BUILD"
        echo "artifact_name=Frame-$NEXT_SHORT_VERSION-build.$NEXT_BUILD"
    } >> "$GITHUB_OUTPUT"
fi

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_SOURCE="${FRAME_VERSION_SOURCE:-$ROOT_DIR/Sources/FrameCore/FrameVersion.swift}"
VERSION_TEST_SOURCE="${FRAME_VERSION_TEST_SOURCE:-$ROOT_DIR/Tests/FrameCoreTests/FrameCoreTests.swift}"
CHANGELOG_SOURCE="${FRAME_CHANGELOG_SOURCE:-$ROOT_DIR/CHANGELOG.md}"
RELEASE_DATE="${FRAME_TODAY:-$(date +%F)}"

usage() {
    cat <<'USAGE'
Usage: scripts/bump-version.sh VERSION BUILD

Updates FrameVersion, the matching version test assertions, and CHANGELOG.md.

Arguments:
  VERSION  User-visible version, for example 0.2.0
  BUILD    Monotonically increasing integer build number, for example 2
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ $# -ne 2 ]]; then
    usage >&2
    exit 64
fi

NEW_SHORT_VERSION="$1"
NEW_BUILD="$2"

if [[ ! "$NEW_SHORT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Version must use numeric major.minor.patch format, for example 0.2.0" >&2
    exit 64
fi

if [[ ! "$NEW_BUILD" =~ ^[1-9][0-9]*$ ]]; then
    echo "Build must be a positive integer" >&2
    exit 64
fi

if [[ ! -f "$VERSION_SOURCE" ]]; then
    echo "Version source not found: $VERSION_SOURCE" >&2
    exit 66
fi

CURRENT_BUILD="$(
    sed -n 's/.*public static let build = "\(.*\)".*/\1/p' "$VERSION_SOURCE"
)"

if [[ ! "$CURRENT_BUILD" =~ ^[0-9]+$ ]]; then
    echo "Unable to read current build from $VERSION_SOURCE" >&2
    exit 65
fi

if (( NEW_BUILD <= CURRENT_BUILD )); then
    echo "Build must be greater than current build $CURRENT_BUILD" >&2
    exit 64
fi

if [[ ! -f "$VERSION_TEST_SOURCE" ]]; then
    echo "Version test source not found: $VERSION_TEST_SOURCE" >&2
    exit 66
fi

if [[ ! -f "$CHANGELOG_SOURCE" ]]; then
    cat > "$CHANGELOG_SOURCE" <<'CHANGELOG'
# Changelog

## Unreleased

- Add release notes here before the next version bump.
CHANGELOG
fi

if ! grep -q '^## Unreleased[[:space:]]*$' "$CHANGELOG_SOURCE"; then
    echo "Unable to find CHANGELOG.md Unreleased section" >&2
    exit 65
fi

export NEW_SHORT_VERSION
export NEW_BUILD
export RELEASE_DATE

perl -0pi -e '
    s/public static let shortVersion = "[^"]+"/public static let shortVersion = "$ENV{NEW_SHORT_VERSION}"/;
    s/public static let build = "[^"]+"/public static let build = "$ENV{NEW_BUILD}"/;
' "$VERSION_SOURCE"

perl -0pi -e '
    s/XCTAssert\(FrameVersion\.shortVersion == "[^"]+"\)/XCTAssert(FrameVersion.shortVersion == "$ENV{NEW_SHORT_VERSION}")/;
    s/XCTAssert\(FrameVersion\.build == "[^"]+"\)/XCTAssert(FrameVersion.build == "$ENV{NEW_BUILD}")/;
    s/XCTAssert\(FrameVersion\.displayName == "[^"]+"\)/XCTAssert(FrameVersion.displayName == "$ENV{NEW_SHORT_VERSION} ($ENV{NEW_BUILD})")/;
' "$VERSION_TEST_SOURCE"

perl -0pi -e '
    sub trim {
        my ($value) = @_;
        $value =~ s/\A\s+//;
        $value =~ s/\s+\z//;
        return $value;
    }

    my $version = $ENV{"NEW_SHORT_VERSION"};
    my $date = $ENV{"RELEASE_DATE"};
    my $placeholder = "- Add release notes here before the next version bump.";
    my $matched = s/## Unreleased\s*\n(.*?)(?=\n## |\z)/
        my $notes = trim($1);
        $notes = "- No notable changes recorded." if $notes eq "" || $notes eq $placeholder;
        "## Unreleased\n\n$placeholder\n\n## $version - $date\n\n$notes\n";
    /se;
    die "Unable to find CHANGELOG.md Unreleased section\n" unless $matched;
' "$CHANGELOG_SOURCE"

echo "Updated Frame to version $NEW_SHORT_VERSION build $NEW_BUILD"
echo "Rolled CHANGELOG.md release section for $NEW_SHORT_VERSION - $RELEASE_DATE"

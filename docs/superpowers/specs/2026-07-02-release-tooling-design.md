# Release Tooling Design

Frame needs a repeatable beta release path before automatic updates or Apple
Developer ID signing are available. This design covers version bumps, changelog
maintenance, and local release artifacts for manual web downloads.

## Scope

- Add a script that updates the single source of truth in
  `Sources/FrameCore/FrameVersion.swift`.
- Keep the existing app about footer and bundle metadata behavior: the packaged
  `Info.plist` continues to receive `CFBundleShortVersionString` and
  `CFBundleVersion` from `FrameVersion`.
- Add a changelog that can hold an `Unreleased` section and release sections.
- Add a release packaging script that produces DMG and ZIP artifacts plus
  checksums from the existing packaged app.
- Add a manual GitHub Actions workflow for beta releases.
- Document the manual beta release flow in `docs/development.md`.

## Non-Goals

- No Sparkle integration.
- No appcast feed.
- No in-app self-update.
- No Apple Developer ID signing or notarization automation.
- No website implementation.

## Version Rules

`shortVersion` is the user-visible release version, such as `0.2.0`.
`build` is a monotonically increasing integer string. Every public beta package
must increment `build`, even when the user-visible version does not change.

The version bump script rejects invalid semantic versions, non-integer build
numbers, and build numbers that are not greater than the current build.

`scripts/prepare-release-version.sh` supports `patch`, `minor`, `major`, and
`custom` release modes. Patch increments only the patch version, minor resets
patch to zero, major resets minor and patch to zero, and custom requires a
semantic version greater than the current version. All modes increment `build`
by one and then call `scripts/bump-version.sh`.

## Changelog Rules

`CHANGELOG.md` uses an `Unreleased` section for pending notes. Releasing a
version renames that section to `version - date` and creates a fresh empty
`Unreleased` section above it.

The script should preserve release notes already written under `Unreleased`.
If there are no pending notes, the section still rolls forward so the release has
an explicit placeholder.

## Release Artifact Rules

The release packaging script reads the current version constants, runs
`scripts/package-app.sh`, and writes artifacts under `.build/release/`.

For manual web downloads it creates:

- `Frame-<version>-build.<build>.zip`
- `Frame-<version>-build.<build>.dmg`
- `SHA256SUMS`

The DMG contains `Frame.app` and an `Applications` symlink so users can drag the
app into `/Applications`. The ZIP contains only `Frame.app`.

The script uses the caller-provided signing identity when available and falls
back to the existing ad-hoc package behavior. Without Developer ID signing, the
docs must keep warning that the beta download may require the macOS
`Open Anyway` flow and Screen Recording permission must be granted after copying
the app to `/Applications`.

The GitHub workflow is manually triggered with `workflow_dispatch`. It exposes a
choice input for `patch`, `minor`, `major`, and `custom`, plus a string input for
the custom version. It commits the version/changelog bump, tags `v<version>`,
uploads release artifacts, and can optionally create a GitHub Release.

## Verification

- Unit tests cover the version bump script through temporary files.
- Unit tests cover semantic release-mode preparation through temporary files.
- Shell syntax checks cover release scripts.
- Static tests confirm the manual release workflow exposes the expected version
  choices and runs the release scripts.
- Full readiness remains `swift test`, `swift build`, and `scripts/package-app.sh`.
- Release artifact verification runs `scripts/package-release.sh` and checks the
  generated DMG, ZIP, and checksum file exist.

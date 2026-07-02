# Release Tooling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Frame's first manual beta release toolchain: version bumping, changelog rollover, DMG/ZIP release artifacts, GitHub Actions release dispatch, and documentation.

**Architecture:** Keep release mechanics in shell scripts under `scripts/` so they can compose with the existing SwiftPM package flow and GitHub Actions. Keep version state in `Sources/FrameCore/FrameVersion.swift`; scripts update that source and the matching version assertions. Use temporary-file XCTest coverage for script behavior so the tests do not mutate the working tree.

**Tech Stack:** Bash, SwiftPM XCTest, GitHub Actions `workflow_dispatch`, `hdiutil`, `ditto`, `shasum`, existing `scripts/package-app.sh`.

---

### Task 1: Version Bump Script

**Files:**
- Create: `scripts/bump-version.sh`
- Create: `Tests/FrameCoreTests/ReleaseToolingTests.swift`
- Modify: `CHANGELOG.md`
- Modify: `docs/development.md`

- [ ] **Step 1: Write failing XCTest coverage**

Add `Tests/FrameCoreTests/ReleaseToolingTests.swift` with tests that run
`scripts/bump-version.sh` against temporary copies of `FrameVersion.swift`,
`FrameCoreTests.swift`, and `CHANGELOG.md`.

- [ ] **Step 2: Verify the test fails**

Run:

```sh
swift test --filter ReleaseToolingTests
```

Expected: fail because `scripts/bump-version.sh` does not exist.

- [ ] **Step 3: Implement `scripts/bump-version.sh`**

The script must accept `VERSION BUILD`, validate the inputs, require a
monotonically larger build, update version constants, update version assertions,
and roll `CHANGELOG.md` from `Unreleased` to `VERSION - YYYY-MM-DD`.

- [ ] **Step 4: Verify targeted tests pass**

Run:

```sh
swift test --filter ReleaseToolingTests
```

Expected: pass.

### Task 2: Release Artifact Script

**Files:**
- Create: `scripts/package-release.sh`
- Modify: `Tests/FrameCoreTests/ReleaseToolingTests.swift`
- Modify: `docs/development.md`

- [ ] **Step 1: Write failing shell syntax coverage**

Extend `ReleaseToolingTests` to run `bash -n scripts/package-release.sh`.

- [ ] **Step 2: Verify the test fails**

Run:

```sh
swift test --filter ReleaseToolingTests
```

Expected: fail because `scripts/package-release.sh` does not exist.

- [ ] **Step 3: Implement `scripts/package-release.sh`**

The script must read `FrameVersion`, call `scripts/package-app.sh`, stage
`Frame.app`, create ZIP and DMG artifacts under `.build/release/`, and write
`SHA256SUMS`.

- [ ] **Step 4: Verify targeted tests pass**

Run:

```sh
swift test --filter ReleaseToolingTests
```

Expected: pass.

### Task 3: Documentation And Full Verification

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `docs/development.md`

- [ ] **Step 1: Document the manual release workflow**

Update `docs/development.md` with the command sequence for editing
`CHANGELOG.md`, bumping version/build, creating release artifacts, and warning
about non-notarized beta distribution.

- [ ] **Step 2: Run full verification**

Run:

```sh
swift test
swift build
scripts/package-app.sh
scripts/package-release.sh
```

Expected: all commands pass and `.build/release/Frame-<version>-build.<build>/`
contains DMG, ZIP, and `SHA256SUMS`.

### Task 4: Manual GitHub Actions Release Workflow

**Files:**
- Create: `.github/workflows/release.yml`
- Create: `scripts/prepare-release-version.sh`
- Modify: `Tests/FrameCoreTests/ReleaseToolingTests.swift`
- Modify: `docs/development.md`

- [ ] **Step 1: Write failing tests for release-mode preparation and workflow choices**

Extend `ReleaseToolingTests` to verify `patch`, `minor`, `major`, and `custom`
version preparation and to assert that `.github/workflows/release.yml` exposes
the expected `workflow_dispatch` choice inputs.

- [ ] **Step 2: Verify the tests fail**

Run:

```sh
swift test --filter ReleaseToolingTests
```

Expected: fail because `scripts/prepare-release-version.sh` and
`.github/workflows/release.yml` do not exist.

- [ ] **Step 3: Implement the helper and workflow**

Add `scripts/prepare-release-version.sh` to compute the next semantic version,
increment build by one, and call `scripts/bump-version.sh`. Add a manual
`Manual Release` GitHub workflow that prepares the version, runs tests and
packaging, commits the bump, tags `v<version>`, uploads artifacts, and can
optionally create a GitHub Release.

- [ ] **Step 4: Verify targeted tests pass**

Run:

```sh
swift test --filter ReleaseToolingTests
```

Expected: pass.

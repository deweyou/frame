# macOS Permissions

Frame needs macOS Screen Recording permission because it captures pixels directly from the display instead of using the system screenshot picker.

On recent macOS versions, the permission prompt may mention bypassing the system private window picker or directly accessing screen and audio. That wording is expected for apps that request Screen Recording or Screen & System Audio Recording access.

Frame's Settings permission section also reports two feature-specific permissions:

- Accessibility allows Frame to post automatic scroll events for scrolling screenshots.
- Input Monitoring allows live keyboard hints during recordings.

Screenshot and recording capture only require Screen Recording. The other two permissions are optional until their related feature is used. Each row provides a request action and a direct System Settings action, and the displayed state refreshes when Frame becomes active again.

## Development Signing

TCC authorization is tied to app identity, path, and code signature. Ad-hoc signing is useful for CI and first-time setup, but it can make macOS treat rebuilt bundles as new apps.

For repeat local testing, use a stable local Code Signing certificate and a stable app path:

```sh
export FRAME_CODESIGN_IDENTITY="Frame Local Dev CLI"
FRAME_APP_VARIANT=development scripts/package-app.sh
mkdir -p ~/Applications
rm -rf ~/Applications/Frame\ Dev.app
ditto ".build/app/Frame Dev.app" ~/Applications/Frame\ Dev.app
open ~/Applications/Frame\ Dev.app
```

The certificate can be a local self-signed Keychain certificate. It does not require an Apple Developer account. It only makes the local app identity stable enough for development.

This should remain the default local development path even after real Apple certificates are available. Real Apple certificates are reserved for explicit Apple Development, Developer ID, notarization, or release distribution testing. Mixing release identities into normal local rebuilds makes it harder to reason about TCC state and can cause avoidable permission churn.

## Recommended Local Test Flow

Use a stable signing identity and app path:

```sh
FRAME_APP_VARIANT=development \
FRAME_CODESIGN_IDENTITY="Frame Local Dev CLI" \
scripts/package-app.sh
mkdir -p ~/Applications
rm -rf ~/Applications/Frame\ Dev.app
ditto ".build/app/Frame Dev.app" ~/Applications/Frame\ Dev.app
open ~/Applications/Frame\ Dev.app
```

Authorize `Frame Dev`, quit it, reopen the same `~/Applications/Frame Dev.app`, then test screenshot capture. Avoid switching between `.build/app/Frame Dev.app` and `~/Applications/Frame Dev.app` during permission testing.

## Reset Permission

If macOS keeps a stale entry for a previous local build:

```sh
tccutil reset ScreenCapture dev.deweyou.frame.dev
```

Then reopen the current app bundle and request permission again.

## Distribution Note

Local self-signing is only for development. Public ZIP or DMG distribution must use Developer ID Application signing and Apple notarization before it is presented as production-ready.

When distribution signing is introduced, keep separate commands or environment presets for:

- local development: `FRAME_APP_VARIANT=development FRAME_CODESIGN_IDENTITY="Frame Local Dev CLI"`
- Apple development testing: `FRAME_APP_VARIANT=development` plus an Apple Development identity
- public distribution: Developer ID identity plus notarization

The production and development bundle identifiers have separate TCC records:

- `dev.deweyou.frame` for Frame
- `dev.deweyou.frame.dev` for Frame Dev

See [Signing and development-device migration](signing-and-device-migration.md) before setting up or replacing a development Mac.

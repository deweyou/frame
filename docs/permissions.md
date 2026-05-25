# macOS Permissions

Frame needs macOS Screen Recording permission because it captures pixels directly from the display instead of using the system screenshot picker.

On recent macOS versions, the permission prompt may mention bypassing the system private window picker or directly accessing screen and audio. That wording is expected for apps that request Screen Recording or Screen & System Audio Recording access.

## Development Signing

TCC authorization is tied to app identity, path, and code signature. Ad-hoc signing is useful for CI and first-time setup, but it can make macOS treat rebuilt bundles as new apps.

For repeat local testing, use a stable local Code Signing certificate and a stable app path:

```sh
export FRAME_CODESIGN_IDENTITY="Frame Local Dev CLI"
scripts/package-app.sh
mkdir -p ~/Applications
rm -rf ~/Applications/Frame.app
cp -R .build/app/Frame.app ~/Applications/Frame.app
open ~/Applications/Frame.app
```

The certificate can be a local self-signed Keychain certificate. It does not require an Apple Developer account. It only makes the local app identity stable enough for development.

This should remain the default local development path even after real Apple certificates are available. Real Apple certificates are reserved for explicit Apple Development, Developer ID, notarization, or release distribution testing. Mixing release identities into normal local rebuilds makes it harder to reason about TCC state and can cause avoidable permission churn.

## Recommended Local Test Flow

Use a stable signing identity and app path:

```sh
FRAME_CODESIGN_IDENTITY="Frame Local Dev CLI" scripts/package-app.sh
mkdir -p ~/Applications
rm -rf ~/Applications/Frame.app
ditto .build/app/Frame.app ~/Applications/Frame.app
open ~/Applications/Frame.app
```

Authorize `Frame`, quit it, reopen the same `~/Applications/Frame.app`, then test screenshot capture. Avoid switching between `.build/app/Frame.app` and `~/Applications/Frame.app` during permission testing.

## Reset Permission

If macOS keeps a stale entry for a previous local build:

```sh
tccutil reset ScreenCapture dev.dewey.frame
```

Then reopen the current app bundle and request permission again.

## Distribution Note

Local self-signing is only for development. Public zip or DMG distribution without a paid Apple Developer account can still work, but users will see Gatekeeper friction and must grant Screen Recording permission themselves. Developer ID signing plus notarization is the future distribution path when an Apple Developer account is available.

When distribution signing is introduced, keep separate commands or environment presets for:

- local development: `FRAME_CODESIGN_IDENTITY="Frame Local Dev CLI"`
- Apple development testing: Apple Development identity
- public distribution: Developer ID identity plus notarization

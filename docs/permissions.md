# macOS Permissions

Frame needs macOS Screen Recording permission because it captures pixels directly from the display instead of using the system screenshot picker.

On recent macOS versions, the permission prompt may mention bypassing the system private window picker or directly accessing screen and audio. That wording is expected for apps that request Screen Recording or Screen & System Audio Recording access.

## Development Caveat

TCC authorization is tied to app identity, path, and code signature. This repository currently packages Frame with ad-hoc signing because no valid local code-signing identity is available.

That means rebuilding can change the binary signature and make macOS treat the new build as a different app. If permission appears to disappear after a rebuild, that is expected in development mode.

## Recommended Local Test Flow

Use a stable app path and do not rebuild between authorization and smoke testing:

```sh
scripts/package-app.sh
mkdir -p ~/Applications
rm -rf ~/Applications/Frame.app
cp -R .build/app/Frame.app ~/Applications/Frame.app
open ~/Applications/Frame.app
```

Authorize `Frame`, quit it, reopen the same `~/Applications/Frame.app`, then test screenshot capture.

## Reset Permission

If macOS keeps a stale entry for a previous local build:

```sh
tccutil reset ScreenCapture dev.dewey.frame
```

Then reopen the current app bundle and request permission again.

## Future Improvement

Use a stable Apple Development or Developer ID signing identity for local and CI packaging. Stable signing should reduce repeated TCC authorization churn during development.


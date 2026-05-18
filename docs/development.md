# Development

## Requirements

- macOS
- Swift 6.2 toolchain
- Xcode command line tools

## Verify

Run these before merging or opening a PR:

```sh
swift test
swift build
scripts/package-app.sh
```

`scripts/package-app.sh` creates `.build/app/Frame.app`, writes `Info.plist`, copies the release executable, and ad-hoc signs the bundle.

## Manual Smoke Test

1. Build and package:

   ```sh
   scripts/package-app.sh
   ```

2. Copy to a stable local path for permission testing:

   ```sh
   mkdir -p ~/Applications
   rm -rf ~/Applications/Frame.app
   cp -R .build/app/Frame.app ~/Applications/Frame.app
   open ~/Applications/Frame.app
   ```

3. Grant Screen Recording permission when prompted.
4. Quit and reopen `~/Applications/Frame.app`.
5. Use `Frame -> 截图` or `Command+Shift+A`.
6. Drag a region.
7. Confirm Quick Access appears with `复制`, `保存`, and `关闭`.
8. Confirm copy places an image on the pasteboard.
9. Confirm save writes `Frame yyyy-MM-dd HH.mm.ss.png` to Desktop.

## CI

GitHub Actions runs on macOS and verifies:

- `swift test`
- `swift build`
- `scripts/package-app.sh`
- generated app bundle existence
- generated `Info.plist` validity
- generated app bundle signature metadata

CI does not grant Screen Recording permission or run GUI smoke tests.

## Local Permission Reset

When testing repeated local builds, reset the app permission entry:

```sh
tccutil reset ScreenCapture dev.dewey.frame
```

Then reopen the exact app bundle you want to authorize.


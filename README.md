# Frame

Frame is a macOS screenshot utility for quickly selecting an area, then copying or saving the captured PNG.

## Knowledge Base

- [Architecture](docs/architecture.md)
- [Development](docs/development.md)
- [macOS Permissions](docs/permissions.md)
- [Design](DESIGN.md)
- [Local Screenshot Loop Spec](docs/superpowers/specs/2026-05-18-local-screenshot-loop-design.md)
- [Local Screenshot Loop Implementation Plan](docs/superpowers/plans/2026-05-18-local-screenshot-loop.md)

## Development

Run the test suite:

```sh
swift test
```

Build a debug binary:

```sh
swift build
```

Package a local app bundle:

```sh
scripts/package-app.sh
```

Open the packaged app:

```sh
open .build/app/Frame.app
```

For manual permission testing, prefer a stable app path:

```sh
mkdir -p ~/Applications
rm -rf ~/Applications/Frame.app
cp -R .build/app/Frame.app ~/Applications/Frame.app
open ~/Applications/Frame.app
```

## Screen Recording Permission

Frame uses macOS screen capture APIs, so it needs Screen Recording permission.

If capture does not start or the app shows the permission alert, grant Screen Recording access to the exact packaged app you are testing. After changing the permission, quit and reopen Frame so macOS applies the new authorization. See [macOS Permissions](docs/permissions.md) for development caveats.

## Manual Smoke Checks

1. Run `open .build/app/Frame.app`.
2. Confirm the Frame menu bar item appears.
3. Choose the capture action or press `Command+Shift+A`.
4. Select a visible screen region.
5. Confirm the Quick Access panel appears with `复制`, `保存`, and `关闭`.
6. Click `复制`, then paste into an app that accepts images.
7. Capture again, click `保存`, and confirm a file named like `Frame yyyy-MM-dd HH.mm.ss.png` appears on the Desktop.
8. Capture again, click `关闭`, and confirm no file is created automatically.

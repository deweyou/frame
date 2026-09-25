# Signing and Development-Device Migration

This runbook records the durable Apple signing setup for Frame. Use it when onboarding a new development Mac, recovering a signing environment, or checking which credential belongs to which build lane.

## Stable Project Identities

The Explicit App IDs are registered in the Apple Developer account and do not need to be recreated for each Mac:

| Purpose | App name | Bundle identifier |
| --- | --- | --- |
| Public production app | Frame | `dev.deweyou.frame` |
| Development and signing checks | Frame Dev | `dev.deweyou.frame.dev` |

The Apple Developer Team ID is `6JKX7TG2AN`, verified from the signed development bundle on 2026-09-02. This value is not a private key, but it should change only if Frame deliberately moves to another Apple Developer team.

Do not create another App ID for a replacement Mac. A Bundle ID identifies the app; it is not a certificate, private key, or provisioning profile.

The two variants have separate `UserDefaults`, TCC permission records, and capture-history caches. Production retains `Application Support/Frame/History`; development uses `Application Support/Frame Dev/History`.

## Build and Signing Lanes

| Lane | Variant | Signing identity | Stable app path | Purpose |
| --- | --- | --- | --- | --- |
| CI package check | `production` | Ad hoc | CI workspace only | Compile and validate bundle structure |
| Daily local GUI work | `development` | `Frame Local Dev CLI` | `~/Applications/Frame Dev.app` | Stable local TCC permissions without using account credentials |
| Apple integration check | `development` | Apple Development | `~/Applications/Frame Dev.app` | Validate Team ID, Launch at Login, and Apple-backed signing behavior |
| Public release | `production` | Developer ID Application | `/Applications/Frame.app` | Hardened, notarized distribution outside the Mac App Store |

Developer ID must never be used for ordinary local iteration. Public artifacts must never fall back to ad-hoc or Apple Development signing.

## Set Up a New Development Mac

1. Install Xcode and select its command-line tools. Confirm `xcode-select -p` and `swift --version` succeed.
2. In `Xcode -> Settings -> Accounts`, sign in with the Apple Account and select the paid developer team.
3. Open `Manage Certificates`, create an `Apple Development` identity for this Mac, and wait for it to appear in the login keychain with a private key.
4. Run `security find-identity -v -p codesigning`. The output must list `Apple Development: ...` and at least one valid identity.
5. If Keychain Access reports that the Apple Development certificate is not trusted, inspect its issuer. Frame's current development identity uses `Apple Worldwide Developer Relations Certification Authority`, organizational unit `G3`. Download and import [Worldwide Developer Relations - G3](https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer), then verify again. Keep Apple certificates on system-default trust settings; do not mark the leaf certificate as Always Trust.
6. Create a machine-local `Frame Local Dev CLI` identity by following [Local Signing Identity Setup](development.md#local-signing-identity-setup). Each Mac may create its own; it is not a distribution credential.
7. Clone Frame, run the normal verification commands, and inspect both package identities:

   ```sh
   swift test
   swift build
   scripts/package-app.sh --print-configuration
   FRAME_APP_VARIANT=development scripts/package-app.sh --print-configuration
   ```

8. Package the daily development app:

   ```sh
   FRAME_APP_VARIANT=development \
   FRAME_CODESIGN_IDENTITY="Frame Local Dev CLI" \
   scripts/package-app.sh
   ```

9. Install `Frame Dev.app` at one stable path, grant Screen Recording and any optional Accessibility or Input Monitoring permissions, and keep using that exact path and signing identity.
10. Run one Apple-backed integration package before relying on Launch at Login or other Team-sensitive behavior:

    ```sh
    FRAME_APP_VARIANT=development \
    FRAME_CODESIGN_IDENTITY="Apple Development: Your Name (IDENTIFIER)" \
    scripts/package-app.sh
    codesign -dv --verbose=4 ".build/app/Frame Dev.app"
    ```

    Confirm the output contains the Apple Development authority and a non-empty `TeamIdentifier`. Install that exact bundle at `~/Applications/Frame Dev.app`, enable Launch at Login in Frame Settings, and confirm macOS lists Frame Dev under Login Items & Extensions.

## What Moves to a Replacement Mac

| Asset | Migration policy |
| --- | --- |
| Explicit App IDs | Nothing to copy. They remain in the Apple Developer account. |
| Apple Development identity | Prefer creating a new identity from Xcode on the new Mac. Keep the old identity until the new one signs successfully. |
| `Frame Local Dev CLI` | Recreate locally. Re-grant TCC permissions because the machine and signature changed. |
| WWDR G3 intermediate | Let Xcode install it or download it again from Apple PKI if the trust chain is incomplete. |
| Developer ID Application identity | Export the certificate together with its private key as a password-protected `.p12`, keep it in approved secure storage, and import it only on an authorized release machine. |
| Notarization keychain profile | Recreate it on the new release machine. Do not copy credentials into the repository or shell scripts. |
| TCC permissions | Grant them again on the new Mac. They are local security decisions, not developer-account assets. |
| Launch at Login | Enable it again in Frame Settings. Service Management registration is local to the Mac and is not stored in the repository or Apple Developer account. |

Apple documents the supported `.p12` export/import flow in [Synchronizing code signing identities with your developer account](https://developer.apple.com/documentation/xcode/sharing-your-teams-signing-certificates). Anyone with the `.p12` and its password can sign as the team, so transfer and store them separately.

## Developer ID and Notarization Recovery

Developer ID Application is the production identity for direct Mac distribution. Apple currently requires the Account Holder role to create it. Follow [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/) when the release lane is set up.

On every authorized release machine:

1. Import the password-protected Developer ID `.p12` into the login keychain.
2. Confirm `security find-identity -v -p codesigning` lists `Developer ID Application: ...`.
3. Recreate a notarization profile in the local keychain with `xcrun notarytool store-credentials`. Do not place the Apple ID, app-specific password, App Store Connect API private key, or profile contents in Git.
4. Verify production artifacts with Developer ID signing, Hardened Runtime, timestamping, notarization, stapling, and Gatekeeper before publishing.

Use Apple's [custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) as the source of truth for `notarytool` credentials and submission behavior.

## Verification and Troubleshooting

List usable signing identities:

```sh
security find-identity -v -p codesigning
```

Inspect the resolved app mapping without building:

```sh
scripts/package-app.sh --print-configuration
FRAME_APP_VARIANT=development scripts/package-app.sh --print-configuration
```

Inspect an Apple-signed development bundle:

```sh
codesign --verify --deep --strict --verbose=2 ".build/app/Frame Dev.app"
codesign -dv --verbose=4 ".build/app/Frame Dev.app"
```

Expected trust chain for the current Apple Development setup:

```text
Apple Development: ...
Apple Worldwide Developer Relations Certification Authority
Apple Root CA
```

If `security find-identity` reports `0 valid identities found`:

1. Confirm the certificate is under `login -> My Certificates` and expands to a private key.
2. Confirm it has not expired or been revoked and the Mac's clock is correct.
3. Install the matching Apple intermediate certificate, currently WWDR G3 for Apple Development.
4. Return any manual trust override to system defaults.
5. Restart Xcode and verify again before recreating or revoking certificates.

## Security Boundaries

Never commit or attach these assets to an issue, pull request, or chat transcript:

- `.p12`, `.cer`, or private-key files intended for distribution
- App Store Connect API `.p8` keys
- app-specific passwords or Apple Account credentials
- notarization keychain exports
- temporary keychains used by CI

Bundle identifiers, Team IDs, certificate fingerprints, and certificate expiry dates are identifiers rather than private keys, but only record them where they are operationally necessary.

---
*Last updated: 2026-09-02 | Reason: register production/development App IDs and document Apple signing recovery for replacement Macs*

---
name: frame-gui-verification
description: Verify user-facing Frame macOS GUI changes with the correct local signing identity, stable app path, Screen Recording permission handling, focused AppKit tests, and bounded manual smoke evidence. Use for local GUI verification, repeat test-app preparation, or diagnosing signing and TCC verification gaps; do not use for ordinary Swift-only changes or production release and notarization.
---

# Frame GUI Verification

Produce trustworthy local evidence for a user-facing Frame change. Do not treat a successful build, package, or launch as proof that the changed interaction works.

## Establish The Verification Scope

Work in the assignment's current Harness workspace. Do not switch to another checkout or reuse an app bundle whose source revision is unknown.

Before acting, read:

- `AGENTS.md` for the current packaging, replacement, and handoff contract.
- `docs/testing.md` for the automated-versus-manual test boundary.
- `docs/permissions.md` when Screen Recording, TCC, signing identity, or app-path stability matters.
- `docs/development.md` for the applicable manual smoke flow.
- `DESIGN.md` and `docs/overlay-interactions.md` when the change affects HUD, overlay, Quick Access, or workspace interaction behavior.

Identify the smallest set of user-visible claims that need live proof. Reuse current test, build, and package Evidence from upstream nodes when it matches the same source revision; rerun only checks needed to close a gap or verify the live bundle.

## Preserve Authority Boundaries

Building or packaging inside the workspace does not authorize replacing or launching the user's installed test app.

Before running the stable-sign-and-replace flow from `AGENTS.md`, confirm that the current user request or Harness Commitment explicitly authorizes all of the following actions:

- replacing `~/Applications/Frame.app`;
- launching that app;
- interacting with the macOS desktop for the requested verification.

If that authority is absent, stop before the first external mutation. Return a blocked result that names the missing authorization and the exact verification it prevents.

Treat `tccutil reset`, permission changes, Keychain identity creation, Apple signing, notarization, release publication, and edits outside the task workspace as separate actions. Never infer authority for them from a request to verify the GUI.

## Prepare The Live Test App

Use the exact stable-signing and replacement flow currently recorded in `AGENTS.md`; do not substitute an ad-hoc build for repeat GUI testing.

After replacement:

1. Verify the installed bundle's code signature and require the expected local signing authority.
2. Confirm the running executable belongs to the stable installed app path, not `.build/app/Frame.app` or another checkout.
3. Keep Screen Recording authorization bound to that exact path and identity. If permission state is ambiguous, diagnose identity, path, and current TCC behavior before proposing a reset.

Do not claim the app is ready when signature, path, or process evidence points to a different bundle.

## Verify The Changed Behavior

Choose evidence by claim:

- Use focused XCTest coverage for deterministic FrameCore behavior and AppKit component interactions supported by `docs/testing.md`.
- Use a real installed app for permissions, global shortcuts, ScreenCaptureKit flows, multi-display behavior, and full desktop interaction.
- Use the smallest relevant section of the manual smoke flow. Do not repeat the complete checklist when the change affects only one bounded surface.
- Capture screenshots, process details, signature output, or concise observations when they materially prove the claim.

When GUI control is unavailable, provide an exact bounded manual check and mark the live claim unverified. A handoff checklist is not live Evidence.

## Report The Result

Return a structured result containing:

- `status`: `verified`, `partial`, `blocked`, or `failed`;
- `scope`: the user-visible claims checked;
- `automated`: commands run or reused, revision identity, and outcomes;
- `bundle`: package path, installed path, signing authority, and running executable evidence;
- `live`: actions performed and observed results;
- `permissions`: relevant Screen Recording or TCC state without unrelated system data;
- `gaps`: every skipped, unavailable, or inconclusive check and its impact.

Use `verified` only when every scoped live claim has current Evidence. Keep raw or large logs out of the summary and attach them as Harness Evidence when available.

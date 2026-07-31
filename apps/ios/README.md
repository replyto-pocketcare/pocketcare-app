# PocketCare — iOS (native, rev 3)

Pure Swift 6 + SwiftUI. No cross-platform layer — see
`docs/plans/native-mobile-apps.md` for the why and the full plan.

## First-time setup

The `.xcodeproj` is generated, not committed (`project.yml` is the source
of truth — see its header comment for why). This scaffold was written by an
agent in a sandbox with no Xcode, so it has never actually been generated
or built — that's on you as the first real verification pass.

```bash
brew install xcodegen   # if you don't already have it
cd apps/ios
xcodegen generate
open PocketCare.xcodeproj
```

## Build & test

```bash
# Fast path — pure-Swift Domain package, no simulator needed:
swift test --package-path Domain

# Full path — App target + a placeholder App-level test, on a simulator:
xcodegen generate
xcodebuild test -project PocketCare.xcodeproj -scheme PocketCare \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

(`iPhone 17 Pro` is what recent Xcode 26.x ships as a default-provisioned
simulator (verified via search 2026-07-31 — Xcode 26.x's default lineup is
iPhone 17 Pro / 17 Pro Max / iPhone Air, not iPhone 16). If that name
doesn't exist on your machine, list what you actually have and swap it in:
`xcrun simctl list devices`.)

## Structure

```
Domain/        Pure SwiftPM package, vector-tested against tools/golden-vectors/vectors/*.json (P1.x)
App/           SwiftUI app shell, depends on Domain, App Group group.care.pocket configured
AppTests/      Placeholder XCTest proving App -> Domain wiring on-device/simulator
```

`Data`, Widgets, and the Live Activity target are added in later phases
(plan §3 target layout) — not created yet, to keep this task's diff
reviewable.

## Open items (plan §10 — need a human "yes")

- `PRODUCT_BUNDLE_IDENTIFIER "care.pocket.ios"`, the App Group id
  `"group.care.pocket"`, and `deploymentTarget iOS 17.0` are proposals, not
  decisions.
- Real code signing (a team/provisioning profile) isn't configured —
  simulator builds don't need it, but a device build or TestFlight upload
  will need your Apple Developer team wired in Xcode.

# Direct clone verification

Wall Pics is now staged as a direct upstream Prism Flutter app, not a SwiftUI-inspired rewrite.

## Source of truth

- Upstream source: `Hash-Studios/Prism`
- Local upstream baseline copied from: `/root/prism-ios/upstream/Prism`
- Local direct-clone workspace: `/root/wall-pics-direct-prism`

## What must stay upstream-owned

These paths are copied from Prism and should not be rewritten unless we are intentionally porting a Prism feature:

- `lib/`
- `assets/`
- `android/`
- `ios/Runner/AppDelegate.swift`
- `ios/Runner/SceneDelegate.swift`
- `ios/Runner/PrismMediaHostApiImpl.swift`
- `ios/Runner/Pigeon/`
- `pigeons/`

## Wall Pics deltas allowed before push

Only these changes are expected in the direct clone candidate:

- iOS display name: `Wall Pics`
- Bundle ID: `com.nightvibes.prism`
- Apple Team ID: `39A8Q3T3TR`
- GitHub Actions rewritten for the existing Wall Pics App Store Connect secrets and `macos-26-intel`
- `ExportOptions.plist` for App Store Connect export
- This verification document

## Current blocker for TestFlight-ready production build

The app expects Prism dart-defines for GitHub, RevenueCat, Pexels, Sentry, Mixpanel, and optional AI client-token values.

The unsigned CI workflow builds without signing or App Store Connect material. The TestFlight workflow uses only App Store Connect signing/upload secrets plus Prism dart-defines.

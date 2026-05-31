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
- `packages/cloud_functions/`
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

The upstream Prism app expects runtime configuration that is not in the public repo:

- `lib/firebase_options.dart`
- `ios/Runner/GoogleService-Info.plist`
- Prism dart-defines for GitHub, RevenueCat, Pexels, Sentry, and Mixpanel values

The unsigned CI workflow can build with Firebase stubs and `SKIP_FIREBASE_INIT=true` for install testing. The TestFlight workflow intentionally fails until production Firebase files and Prism dart-defines are provided as GitHub secrets.

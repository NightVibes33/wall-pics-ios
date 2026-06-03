# Prism verification notes

Prism is maintained as the iOS-first Flutter app in this repository.

## Source of truth

- Public app repo: `NightVibes33/prism-ios`
- App name: `Přism` in App Store Connect and `Prism` in code-facing identifiers
- Bundle ID: `com.nightvibes.prism`
- Apple Team ID: `39A8Q3T3TR`

## Current app boundary

The mobile app should use only the Prism API worker for user storage, catalog JSON, image delivery, and video delivery. The app build env should expose the public Worker URL only. Private GitHub tokens, catalog tokens, App Store Connect keys, and upstream media allowlists stay in GitHub Actions or Worker secrets.

## Required runtime catalog files

The app expects the Worker catalog endpoint to provide the bootstrap, category, item-location, search, and paged catalog JSON files. If `PRISM_CATALOG_BASE_URL` or `USER_STORE_API_BASE_URL` is missing from the build env, the app can launch but the catalog will be empty.

## Validation rule

Do not call the app TestFlight-ready until Flutter analysis/build, Worker typecheck, catalog endpoint validation, and a real-device smoke test all pass. Live Photo wallpaper compatibility must be confirmed on an actual iPhone because static code review cannot prove Photos accepts the paired resources as motion wallpaper media.

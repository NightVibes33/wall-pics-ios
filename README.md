# Wall Pics

Wall Pics is an iOS wallpaper app for browsing, saving, and organizing high-quality phone wallpapers and Live Photos.

## Features

- Phone-first wallpaper catalog with curated categories
- Live Photos section with ready-to-save motion wallpapers
- Wallpaper previews tuned for iPhone screen sizes
- Save wallpapers and Live Photos to Photos
- Favorites library for saved picks
- Wallpaper detail pages with metadata and color palette tools
- Search, category browsing, and collection views
- Optional account features for syncing favorites and profile data
- Premium-ready flows for subscriptions, rewards, and gated downloads
- App Store and TestFlight build workflows

## iOS

The iOS app is built with Flutter and native iOS bridges for media saving, photo library access, and release packaging.

Supported build outputs:

- TestFlight/App Store builds through Xcode and App Store Connect
- Unsigned device IPA builds for SideStore/AltStore style testing
- GitHub Actions release artifacts

## Catalog Updates

Wall Pics supports a remote catalog endpoint configured at build time with:

```sh
--dart-define=WALL_PICS_CATALOG_BASE_URL=https://example.com/catalog
```

When the endpoint is configured, the app loads the newest catalog JSON at launch and falls back to the bundled catalog if the network is unavailable.

Expected files:

- `wallpics_regular.json`
- `wallpics_live.json`

## Development

```sh
flutter pub get
flutter analyze
flutter build ios --release --no-codesign
```

For CI builds, set `WALL_PICS_CATALOG_BASE_URL` as a repository secret if a remote catalog endpoint is available.

## Privacy

Wall Pics only requests photo library access when saving wallpapers or Live Photos. Account, analytics, purchases, and notification behavior must match the privacy disclosures configured in App Store Connect.

## License

See the license files and third-party notices included in this repository.

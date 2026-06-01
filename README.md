# Prism

Prism is an iOS wallpaper app for browsing, saving, and organizing high-quality phone wallpapers and Live Photos.

## Features

- Phone-first wallpaper catalog with curated categories
- Live Photos section with ready-to-save motion wallpapers
- Wallpaper previews tuned for iPhone screen sizes
- Save wallpapers and Live Photos to Photos
- Favorites library for saved picks
- Wallpaper detail pages with metadata and color palette tools
- Search, category browsing, and collection views
- Optional account login for syncing app data through the server API
- App Store and TestFlight build workflows

## iOS

The iOS app is built with Flutter and native iOS bridges for media saving, photo library access, and release packaging.

Supported build outputs:

- TestFlight/App Store builds through Xcode and App Store Connect
- Unsigned device IPA builds for SideStore/AltStore style testing
- GitHub Actions release artifacts

## Catalog Updates

Prism supports a remote catalog endpoint configured at build time with:

```sh
--dart-define=PRISM_CATALOG_BASE_URL=https://example.com/catalog
```

Catalog files are served by the Worker at `/v1/catalog` from the private catalog repository. Set `PRISM_CATALOG_BASE_URL` directly, or set `USER_STORE_API_BASE_URL` and the app will use `<USER_STORE_API_BASE_URL>/v1/catalog`. Large catalog files stay outside the IPA and are fetched at runtime.

Expected files include regular, live, matching, double, parallax, profile picture, charging animation, DIY template, live DIY template, sticker, filters, category tree, popular search, and search suggestion JSON.

## Development

```sh
flutter pub get
flutter analyze
flutter build ios --release --no-codesign
```

For CI builds, set `USER_STORE_API_BASE_URL` and/or `PRISM_CATALOG_BASE_URL` in `PRISM_ENV`. Do not put GitHub tokens in mobile dart-defines.

## Privacy

Prism only requests photo library access when saving wallpapers or Live Photos. Account, analytics, and notification behavior must match the privacy disclosures configured in App Store Connect. GitHub tokens and other server secrets must stay on the server side and are filtered from CI dart-defines.

## License

See the license files and third-party notices included in this repository.

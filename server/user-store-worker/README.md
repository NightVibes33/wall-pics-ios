# Prism API Worker

Production auth, user storage, and private catalog boundary for the mobile app.

The app never receives `GITHUB_TOKEN`. It sends Google or Apple identity tokens to this Worker, the Worker verifies them, then the Worker writes `users/<user-id>.json` into the private GitHub repo using a server-side token. Catalog JSON is read from a private repository through `/v1/catalog`.

## Required Worker secrets

```sh
wrangler secret put GITHUB_TOKEN
wrangler secret put GITHUB_OWNER
wrangler secret put GITHUB_REPO
wrangler secret put SESSION_SECRET
wrangler secret put GOOGLE_CLIENT_ID
wrangler secret put APPLE_BUNDLE_ID
wrangler secret put CATALOG_GITHUB_OWNER
wrangler secret put CATALOG_GITHUB_REPO
wrangler secret put CATALOG_GITHUB_TOKEN
wrangler secret put ALLOWED_MEDIA_HOSTS
```

`GITHUB_TOKEN` should be a fine-grained token scoped only to the private user repo contents it must write. `CATALOG_GITHUB_TOKEN` can be read-only and scoped only to the private catalog repo. If catalog owner/repo/token are omitted, the Worker falls back to the user repo settings. `ALLOWED_MEDIA_HOSTS` is a comma-separated allowlist for the private media hosts the catalog points at; keep it in Worker secrets, not in the public app repo.

## App env

Set only the public Worker URL in the app build env:

```env
USER_STORE_API_BASE_URL=https://prism-user-store.<account>.workers.dev
PRISM_CATALOG_BASE_URL=https://prism-user-store.<account>.workers.dev/v1/catalog
```

The same Worker serves cached media through `/v1/media/image` and `/v1/media/video.<ext>`, so the app can load catalog thumbnails, full images, and live previews through the public Worker URL while the upstream media host allowlist stays private.

Do not include `GH_TOKEN` or catalog repository tokens in `PRISM_ENV`; the iOS workflows filter known server-only keys as defense in depth.


## Apple subscriptions and free download quota

The app uses Apple's StoreKit path directly through Flutter `in_app_purchase`; payments are processed by Apple.

Create these products in App Store Connect for the Přism app:

| Product ID | Type | Suggested price |
| --- | --- | --- |
| `prism_pro_monthly` | Auto-renewable subscription | $4.99/month |
| `prism_pro_yearly` | Auto-renewable subscription | $24.99/year |
| `prism_pro_lifetime` | Non-consumable | $39.99 launch / $49.99 later |

The app sends successful Apple purchase details to:

```http
POST /v1/users/:userId/subscription/apple-sync
```

The Worker stores `premium: true`, `subscriptionTier: "pro"` or `"lifetime"`, and an `appleSubscription` object in `users/<user-id>.json` in the private user repo.

Free users are limited to three downloads per UTC day through:

```http
GET  /v1/users/:userId/downloads/quota
POST /v1/users/:userId/downloads/claim
```

The user document stores:

```json
{
  "freeDownloadDay": "2026-06-03",
  "freeDownloadsToday": 2,
  "freeDownloadsLimit": 3
}
```

The app must claim a quota slot before saving media. Pro/lifetime users bypass the free quota.

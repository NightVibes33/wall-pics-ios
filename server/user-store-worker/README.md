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
```

`GITHUB_TOKEN` should be a fine-grained token scoped only to the private user repo contents it must write. `CATALOG_GITHUB_TOKEN` can be read-only and scoped only to the private catalog repo. If catalog owner/repo/token are omitted, the Worker falls back to the user repo settings.

## App env

Set only the public Worker URL in the app build env:

```env
USER_STORE_API_BASE_URL=https://prism-user-store.<account>.workers.dev
PRISM_CATALOG_BASE_URL=https://prism-user-store.<account>.workers.dev/v1/catalog
```

Do not include `GH_TOKEN` or catalog repository tokens in `PRISM_ENV`; the iOS workflows filter known server-only keys as defense in depth.

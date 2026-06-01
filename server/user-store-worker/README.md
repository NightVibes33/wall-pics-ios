# Wall Pics User Store Worker

Production auth/user storage boundary for the mobile app.

The app never receives `GITHUB_TOKEN`. It sends Google or Apple identity tokens to this Worker, the Worker verifies them, then the Worker writes `users/<user-id>.json` into the private GitHub repo using a server-side token.

## Required Worker secrets

```sh
wrangler secret put GITHUB_TOKEN
wrangler secret put GITHUB_OWNER
wrangler secret put GITHUB_REPO
wrangler secret put SESSION_SECRET
wrangler secret put GOOGLE_CLIENT_ID
wrangler secret put APPLE_BUNDLE_ID
```

`GITHUB_TOKEN` should be a fine-grained token scoped only to the private repo contents it must write.

## App env

Set only the public Worker URL in the app build env:

```env
USER_STORE_API_BASE_URL=https://wall-pics-user-store.<account>.workers.dev
```

Do not include `GH_TOKEN` in `WALLPICS_ENV`; the iOS workflows filter it out as a defense-in-depth measure.

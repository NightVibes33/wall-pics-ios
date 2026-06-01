#!/usr/bin/env sh
# Writes .env from GitHub Actions env vars and validates the Prism catalog URL.
set -eu

: > .env

if [ -n "${PRISM_ENV:-}" ]; then
  printf '%s\n' "$PRISM_ENV" | awk -F= '$1 !~ /^(GH_TOKEN|RC_API_KEY|RC_ANDROID_API_KEY|RC_IOS_API_KEY|PEXELS_API_KEY|AI_CLIENT_TOKEN)$/ { print }' > .env
fi

if ! grep -q '^USER_STORE_API_BASE_URL=' .env && [ -n "${USER_STORE_API_BASE_URL:-}" ]; then
  printf '%s\n' "USER_STORE_API_BASE_URL=$USER_STORE_API_BASE_URL" >> .env
fi

if ! grep -q '^PRISM_CATALOG_BASE_URL=' .env && [ -n "${CATALOG_BASE_URL:-}" ]; then
  printf '%s\n' "PRISM_CATALOG_BASE_URL=$CATALOG_BASE_URL" >> .env
fi

if ! grep -q '^PRISM_CATALOG_BASE_URL=' .env; then
  API_BASE="$(awk -F= '$1 == "USER_STORE_API_BASE_URL" { sub(/^[^=]*=/, ""); print }' .env | tail -n 1)"
  if [ -n "$API_BASE" ]; then
    API_BASE="${API_BASE%/}"
    printf '%s\n' "PRISM_CATALOG_BASE_URL=$API_BASE/v1/catalog" >> .env
  fi
fi

CATALOG_BASE="$(awk -F= '$1 == "PRISM_CATALOG_BASE_URL" { sub(/^[^=]*=/, ""); print }' .env | tail -n 1)"
if [ -z "$CATALOG_BASE" ]; then
  echo "Missing PRISM_CATALOG_BASE_URL, WALL_PICS_CATALOG_BASE_URL, or USER_STORE_API_BASE_URL"
  exit 1
fi
CATALOG_BASE="${CATALOG_BASE%/}"

echo "Validating Prism catalog endpoint"
curl -fsSL --retry 3 --retry-delay 2 "$CATALOG_BASE/prism_index.json" | python3 -c 'import json,sys; json.load(sys.stdin)'
curl -fsSIL --retry 3 --retry-delay 2 "$CATALOG_BASE/prism_category_trees.json" >/dev/null
curl -fsSIL --retry 3 --retry-delay 2 "$CATALOG_BASE/prism_regular.json" >/dev/null

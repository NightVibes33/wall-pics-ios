#!/usr/bin/env python3
"""Build an encrypted local seed media pack for Prism first-screen images."""

from __future__ import annotations

import base64
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


MAGIC = b"PSMEDIA1\n"
KEY = b"prism-catalog-seed-media-v1"
OUT_PATH = Path("assets/catalog/prism_seed_media.dbx")
DEFAULT_LIMIT = 96
DEFAULT_MAX_BYTES = 24_000_000
PER_FILE_MAX_BYTES = 1_200_000

STATIC_FILES = (
    "prism_bootstrap_home.json",
    "prism_regular_page_001.json",
    "prism_live_page_001.json",
    "prism_matching_page_001.json",
    "prism_double_page_001.json",
    "prism_parallax_page_001.json",
    "prism_profile_pictures_page_001.json",
)

API_ENDPOINTS = (
    "/api/wallpaper-list",
    "/api/wallpapers/live",
    "/api/wallpapers/matching",
    "/api/wallpapers/double",
    "/api/wallpapers/parallax",
    "/api/profile-pictures",
)

IMAGE_KEYS = (
    "original_photo_url",
    "original_photo",
    "original_still_url",
    "original_still",
    "still_image_url",
    "still_image",
    "still_url",
    "still",
    "photo_url",
    "photo",
    "download_url",
    "app_download_url",
    "full_url",
    "wallpaper_url",
    "wallpaper",
    "image_url",
    "image",
    "url",
)

PREVIEW_MARKERS = (
    "/preview",
    "/previews",
    "/thumbnail",
    "/thumbnails",
    "/thumb",
    "first_frame",
    "app_display",
    "display_url",
    "poster",
    "watermark",
    "brand",
    "logo",
    "wallpics",
)


def _env(name: str) -> str:
    return os.environ.get(name, "").strip()


def _load_dotenv(path: Path) -> None:
    if not path.exists():
        return
    for raw_line in path.read_text(errors="ignore").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if not key or key in os.environ:
            continue
        value = value.strip().strip("\"'")
        os.environ[key] = value


def _crypt(data: bytes) -> bytes:
    out = bytearray(len(data))
    offset = 0
    counter = 0
    while offset < len(data):
        block = hashlib.sha256(KEY + f":{counter}".encode()).digest()
        for byte in block:
            if offset >= len(data):
                break
            out[offset] = data[offset] ^ byte
            offset += 1
        counter += 1
    return bytes(out)


def _write_pack(media: dict[str, str]) -> None:
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "version": 1,
        "generated_at": int(time.time()),
        "count": len(media),
        "media": media,
    }
    plain = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()
    OUT_PATH.write_bytes(MAGIC + _crypt(plain))


def _request_json(url: str, headers: dict[str, str]) -> Any | None:
    data = _request_bytes(url, headers, max_bytes=8_000_000, expect_image=False)
    if not data:
        return None
    try:
        return json.loads(data.decode("utf-8"))
    except Exception:
        return None


def _request_bytes(
    url: str,
    headers: dict[str, str],
    *,
    max_bytes: int = PER_FILE_MAX_BYTES,
    expect_image: bool = True,
) -> bytes | None:
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=8) as response:
            content_type = response.headers.get("content-type", "").lower()
            if expect_image and ("json" in content_type or content_type.startswith("text/")):
                return None
            if not expect_image and "json" not in content_type and not url.endswith(".json"):
                return None
            return response.read(max_bytes + 1)[:max_bytes]
    except (OSError, urllib.error.HTTPError, urllib.error.URLError):
        return None


def _looks_like_image(data: bytes) -> bool:
    return (
        data.startswith(b"\xff\xd8\xff")
        or data.startswith(b"\x89PNG\r\n\x1a\n")
        or data.startswith(b"GIF87a")
        or data.startswith(b"GIF89a")
        or (len(data) > 12 and data[0:4] == b"RIFF" and data[8:12] == b"WEBP")
    )


def _url_join(base: str, path: str) -> str:
    if not base:
        return ""
    return urllib.parse.urljoin(base.rstrip("/") + "/", path.lstrip("/"))


def _wallpics_headers() -> dict[str, str]:
    headers: dict[str, str] = {
        "Accept": "application/json",
        "User-Agent": "PrismSeedMediaBuilder/1.0",
    }
    auth_header = _env("WALLPICS_AUTH_HEADER")
    bearer = _env("WALLPICS_BEARER_TOKEN")
    if auth_header:
        headers["Authorization"] = auth_header
    elif bearer:
        headers["Authorization"] = f"Bearer {bearer}"
    for name, header_name in (
        ("WALLPICS_X_TOKEN", "X-Token"),
        ("WALLPICS_X_AUTH", "X-Auth"),
        ("WALLPICS_HHAA", "hhaa"),
    ):
        value = _env(name)
        if value:
            headers[header_name] = value
    extra = _env("WALLPICS_EXTRA_HEADERS_JSON")
    if extra:
        try:
            decoded = json.loads(extra)
            if isinstance(decoded, dict):
                for key, value in decoded.items():
                    if str(key).strip() and str(value).strip():
                        headers[str(key).strip()] = str(value).strip()
        except Exception:
            pass
    return headers


def _walk(value: Any) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    if isinstance(value, dict):
        rows.append(value)
        for child in value.values():
            rows.extend(_walk(child))
    elif isinstance(value, list):
        for child in value:
            rows.extend(_walk(child))
    return rows


def _is_image_url(raw_url: str) -> bool:
    url = raw_url.strip()
    if not url.startswith(("http://", "https://")):
        return False
    parsed = urllib.parse.urlparse(url)
    lowered = urllib.parse.unquote((parsed.path + "?" + parsed.query).lower())
    if any(marker in lowered for marker in PREVIEW_MARKERS):
        return False
    if lowered.endswith((".mp4", ".mov", ".zip", ".heic", ".heif", ".json")):
        return False
    return True


def _candidate_urls(row: dict[str, Any]) -> list[str]:
    urls: list[str] = []

    def add(value: Any) -> None:
        if isinstance(value, str) and _is_image_url(value):
            urls.append(value.strip())

    for key in IMAGE_KEYS:
        add(row.get(key))
    for nested_key in ("paired_wallpapers", "wallpapers", "matching_sides", "thumbnail_config"):
        nested = row.get(nested_key)
        if nested is None:
            continue
        for nested_row in _walk(nested):
            for key in IMAGE_KEYS:
                add(nested_row.get(key))
            layers = nested_row.get("layers")
            if isinstance(layers, list):
                for layer in layers:
                    if isinstance(layer, dict):
                        for key in IMAGE_KEYS:
                            add(layer.get(key))
    seen: set[str] = set()
    unique: list[str] = []
    for url in urls:
        if url not in seen:
            seen.add(url)
            unique.append(url)
    return unique


def _catalog_payloads() -> list[Any]:
    headers = _wallpics_headers()
    payloads: list[Any] = []
    bases = [
        _env("PRISM_CATALOG_BASE_URL"),
        _env("CATALOG_BASE_URL"),
        _env("WALL_PICS_CATALOG_BASE_URL"),
    ]
    user_store = _env("USER_STORE_API_BASE_URL")
    if user_store:
        bases.append(_url_join(user_store, "/v1/catalog"))
    for base in [base for base in bases if base]:
        for name in STATIC_FILES:
            payload = _request_json(_url_join(base, name), headers)
            if payload is not None:
                payloads.append(payload)
    api_base = _env("WALLPICS_API_BASE_URL") or _env("PRISM_SCRAPER_API_BASE_URL")
    if api_base:
        for endpoint in API_ENDPOINTS:
            query = urllib.parse.urlencode(
                {
                    "paginated": "1",
                    "page": "1",
                    "per_page": "60",
                    "sortBy": "recommended",
                    "nsfwContent": "1",
                }
            )
            payload = _request_json(f"{_url_join(api_base, endpoint)}?{query}", headers)
            if payload is not None:
                payloads.append(payload)
    return payloads


def _media_proxy_url(source_url: str) -> str:
    user_store = _env("USER_STORE_API_BASE_URL")
    if not user_store:
        return source_url
    query = urllib.parse.urlencode({"src": source_url, "w": "420", "q": "76"})
    return f"{_url_join(user_store, '/v1/media/image')}?{query}"


def _sha_url(raw_url: str) -> str:
    return hashlib.sha256(raw_url.strip().encode("utf-8")).hexdigest()


def main() -> int:
    _load_dotenv(Path(".env"))
    limit = int(_env("PRISM_SEED_MEDIA_LIMIT") or DEFAULT_LIMIT)
    max_bytes = int(_env("PRISM_SEED_MEDIA_MAX_BYTES") or DEFAULT_MAX_BYTES)
    payloads = _catalog_payloads()
    selected: list[str] = []
    seen: set[str] = set()
    for payload in payloads:
        for row in _walk(payload):
            for url in _candidate_urls(row):
                if url not in seen:
                    seen.add(url)
                    selected.append(url)
                if len(selected) >= limit:
                    break
            if len(selected) >= limit:
                break
        if len(selected) >= limit:
            break

    media: dict[str, str] = {}
    total_bytes = 0
    image_headers = {"Accept": "image/*", "User-Agent": "PrismSeedMediaBuilder/1.0"}
    for original_url in selected:
        if total_bytes >= max_bytes:
            break
        fetch_url = _media_proxy_url(original_url)
        data = _request_bytes(fetch_url, image_headers)
        if not data:
            continue
        if len(data) < 128 or not _looks_like_image(data):
            continue
        total_bytes += len(data)
        if total_bytes > max_bytes:
            break
        media[_sha_url(original_url)] = base64.b64encode(data).decode("ascii")

    _write_pack(media)
    print(f"Prism seed media pack: {len(media)} images, {total_bytes} bytes, output={OUT_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

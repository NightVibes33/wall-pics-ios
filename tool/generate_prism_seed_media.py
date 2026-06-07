#!/usr/bin/env python3
"""Build encrypted bundled media resources for Prism catalog content."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from dataclasses import dataclass
from pathlib import Path
from typing import Any


MAGIC = b"PSMEDIA1\n"
KEY = b"prism-catalog-seed-media-v1"
LEGACY_OUT_PATH = Path("assets/catalog/prism_seed_media.dbx")
MANIFEST_PATH = Path("assets/catalog/prism_seed_media_manifest.json")
MEDIA_DIR = Path("assets/catalog/prism_seed_media")
DEFAULT_LIMIT = 20_000
DEFAULT_MAX_BYTES = 1_800_000_000
PER_FILE_MAX_BYTES = 180_000_000
DEFAULT_API_MAX_PAGES = 80
DEFAULT_CATALOG_MAX_PAGES = 80
DEFAULT_PAGE_SIZE = 100

BASE_CATALOG_FILES = (
    "prism_index.json",
    "prism_category_lite.json",
    "prism_category_trees.json",
    "prism_category_ids.json",
    "prism_item_locations.json",
    "prism_popular_searches.json",
    "prism_search_suggestions.json",
    "prism_search_index.json",
    "prism_bootstrap_home.json",
)

CATALOG_PREFIXES = (
    "prism_regular",
    "prism_live",
    "prism_matching",
    "prism_double",
    "prism_parallax",
    "prism_profile_pictures",
    "prism_charging_animations",
    "prism_diy_templates",
    "prism_live_diy_templates",
    "prism_stickers",
)

API_ENDPOINTS = (
    "/api/wallpaper-list",
    "/api/wallpapers/live",
    "/api/wallpapers/matching",
    "/api/wallpapers/double",
    "/api/wallpapers/parallax",
    "/api/profile-pictures",
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

IMAGE_EXTENSIONS = (".jpg", ".jpeg", ".png", ".webp", ".gif")
VIDEO_EXTENSIONS = (".mp4", ".mov")
ARCHIVE_EXTENSIONS = (".zip",)
UNSUPPORTED_EXTENSIONS = (".heic", ".heif", ".json")


@dataclass(frozen=True)
class ResourceCandidate:
    lookup_url: str
    fetch_url: str
    kind: str


def _env(name: str) -> str:
    return os.environ.get(name, "").strip()


def _int_env(name: str, fallback: int) -> int:
    value = _env(name)
    if not value:
        return fallback
    try:
        return int(value)
    except ValueError:
        return fallback


def _bool_env(name: str, fallback: bool = False) -> bool:
    value = _env(name).lower()
    if not value:
        return fallback
    return value in {"1", "true", "yes", "on"}


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
        os.environ[key] = value.strip().strip("\"'")


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


def _write_legacy_pack(media: dict[str, bytes]) -> int:
    LEGACY_OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    entries: list[dict[str, Any]] = []
    blobs = bytearray()
    for key, data in media.items():
        offset = len(blobs)
        blobs.extend(data)
        entries.append({"key": key, "offset": offset, "length": len(data)})
    index = {"version": 2, "generated_at": int(time.time()), "count": len(entries), "entries": entries}
    index_bytes = json.dumps(index, separators=(",", ":"), sort_keys=True).encode()
    plain = b"PSMBIN2\n" + len(index_bytes).to_bytes(4, "big") + index_bytes + bytes(blobs)
    LEGACY_OUT_PATH.write_bytes(MAGIC + _crypt(plain))
    return len(plain)


def _request_json(url: str, headers: dict[str, str]) -> Any | None:
    response = _request_bytes(url, headers, max_bytes=12_000_000, expect_json=True, timeout=18)
    if response is None:
        return None
    data, _ = response
    try:
        return json.loads(data.decode("utf-8"))
    except Exception:
        return None


def _request_bytes(
    url: str,
    headers: dict[str, str],
    *,
    max_bytes: int,
    expect_json: bool = False,
    timeout: int = 45,
) -> tuple[bytes, str] | None:
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            content_type = response.headers.get("content-type", "").lower()
            if expect_json and "json" not in content_type and not url.endswith(".json"):
                return None
            if not expect_json and ("json" in content_type or content_type.startswith("text/")):
                return None
            data = response.read(max_bytes + 1)
            if len(data) > max_bytes:
                return None
            return data, content_type
    except (OSError, urllib.error.HTTPError, urllib.error.URLError):
        return None


def _detect_kind(data: bytes, content_type: str, url: str, expected: str) -> str | None:
    content_type = content_type.lower()
    path = urllib.parse.urlparse(url).path.lower()
    if data.startswith(b"\xff\xd8\xff") or data.startswith(b"\x89PNG\r\n\x1a\n") or data.startswith(b"GIF87a") or data.startswith(b"GIF89a"):
        return "image"
    if len(data) > 12 and data[0:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image"
    if data.startswith(b"PK\x03\x04") or "zip" in content_type:
        return "archive"
    if len(data) > 12 and data[4:8] == b"ftyp":
        return "video"
    if content_type.startswith("image/"):
        return "image"
    if content_type.startswith("video/"):
        return "video"
    if path.endswith(IMAGE_EXTENSIONS):
        return "image"
    if path.endswith(VIDEO_EXTENSIONS):
        return "video"
    if path.endswith(ARCHIVE_EXTENSIONS):
        return "archive"
    return expected if expected in {"image", "video", "archive"} and len(data) > 512 else None


def _extension_for(kind: str, content_type: str, url: str) -> str:
    path = urllib.parse.urlparse(url).path.lower()
    for ext in (*IMAGE_EXTENSIONS, *VIDEO_EXTENSIONS, *ARCHIVE_EXTENSIONS):
        if path.endswith(ext):
            return ext
    content_type = content_type.lower().split(";", 1)[0].strip()
    return {
        "image/jpeg": ".jpg",
        "image/jpg": ".jpg",
        "image/png": ".png",
        "image/webp": ".webp",
        "image/gif": ".gif",
        "video/mp4": ".mp4",
        "video/quicktime": ".mov",
        "application/zip": ".zip",
    }.get(content_type, {"image": ".jpg", "video": ".mp4", "archive": ".zip"}.get(kind, ".bin"))


def _url_join(base: str, path: str) -> str:
    if not base:
        return ""
    return urllib.parse.urljoin(base.rstrip("/") + "/", path.lstrip("/"))


def _wallpics_headers() -> dict[str, str]:
    headers: dict[str, str] = {"Accept": "application/json", "User-Agent": "PrismBundledMediaBuilder/2.0"}
    auth_header = _env("WALLPICS_AUTH_HEADER")
    bearer = _env("WALLPICS_BEARER_TOKEN")
    if auth_header:
        headers["Authorization"] = auth_header
    elif bearer:
        headers["Authorization"] = f"Bearer {bearer}"
    for name, header_name in (("WALLPICS_X_TOKEN", "X-Token"), ("WALLPICS_X_AUTH", "X-Auth"), ("WALLPICS_HHAA", "hhaa")):
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


def _walk(value: Any) -> list[Any]:
    rows: list[Any] = []
    if isinstance(value, dict):
        rows.append(value)
        for child in value.values():
            rows.extend(_walk(child))
    elif isinstance(value, list):
        for child in value:
            rows.extend(_walk(child))
    else:
        rows.append(value)
    return rows


def _payload_items(payload: Any) -> list[Any]:
    if isinstance(payload, list):
        return payload
    if not isinstance(payload, dict):
        return []
    for key in ("wallpapers", "items", "data", "results", "profile_pictures"):
        value = payload.get(key)
        if isinstance(value, list):
            return value
        if isinstance(value, dict):
            nested = _payload_items(value)
            if nested:
                return nested
    return []


def _catalog_payloads() -> list[Any]:
    headers = _wallpics_headers()
    payloads: list[Any] = []
    catalog_max_pages = _int_env("PRISM_SEED_MEDIA_CATALOG_MAX_PAGES", DEFAULT_CATALOG_MAX_PAGES)
    api_max_pages = _int_env("PRISM_SEED_MEDIA_API_MAX_PAGES", DEFAULT_API_MAX_PAGES)
    page_size = _int_env("PRISM_SEED_MEDIA_PAGE_SIZE", DEFAULT_PAGE_SIZE)
    bases = [_env("PRISM_CATALOG_BASE_URL"), _env("CATALOG_BASE_URL"), _env("WALL_PICS_CATALOG_BASE_URL")]
    user_store = _env("USER_STORE_API_BASE_URL")
    if user_store:
        bases.append(_url_join(user_store, "/v1/catalog"))
    seen_catalog_urls: set[str] = set()
    for base in [base for base in bases if base]:
        for name in BASE_CATALOG_FILES:
            url = _url_join(base, name)
            if url in seen_catalog_urls:
                continue
            seen_catalog_urls.add(url)
            payload = _request_json(url, headers)
            if payload is not None:
                payloads.append(payload)
        for prefix in CATALOG_PREFIXES:
            for page in range(1, catalog_max_pages + 1):
                name = f"{prefix}_page_{page:03d}.json"
                url = _url_join(base, name)
                if url in seen_catalog_urls:
                    continue
                seen_catalog_urls.add(url)
                payload = _request_json(url, headers)
                if payload is None:
                    if page == 1:
                        break
                    break
                payloads.append(payload)
                items = _payload_items(payload)
                has_more = isinstance(payload, dict) and payload.get("has_more", False) is True
                if not has_more and len(items) < page_size:
                    break
    api_base = _env("WALLPICS_API_BASE_URL") or _env("PRISM_SCRAPER_API_BASE_URL")
    if api_base:
        for endpoint in API_ENDPOINTS:
            seen_ids: set[str] = set()
            for page in range(1, api_max_pages + 1):
                query = urllib.parse.urlencode(
                    {
                        "paginated": "1",
                        "page": str(page),
                        "per_page": str(page_size),
                        "sortBy": "recommended",
                        "nsfwContent": "1",
                    }
                )
                payload = _request_json(f"{_url_join(api_base, endpoint)}?{query}", headers)
                if payload is None:
                    break
                items = _payload_items(payload)
                if not items:
                    break
                payloads.append(payload)
                new_ids = {str(item.get("id", "")) for item in items if isinstance(item, dict) and item.get("id") is not None}
                if new_ids and new_ids.issubset(seen_ids):
                    break
                seen_ids.update(new_ids)
                if len(items) < page_size:
                    break
    return payloads


def _preview_probe(url: str) -> str:
    parsed = urllib.parse.urlparse(url)
    decoded = urllib.parse.unquote((parsed.path + "?" + parsed.query).lower())
    return (
        decoded.replace("/thumbnail_config", "/spatial_config")
        .replace("thumbnail_config", "spatial_config")
        .replace("/thumbnail-config", "/spatial-config")
        .replace("thumbnail-config", "spatial-config")
    )


def _is_catalog_preview_url(raw_url: str) -> bool:
    probe = _preview_probe(raw_url)
    return any(marker in probe for marker in PREVIEW_MARKERS)


def _resource_kind_from_url(raw_url: str, *, allow_preview: bool = False) -> str | None:
    url = raw_url.strip()
    if not url.startswith(("http://", "https://")):
        return None
    parsed = urllib.parse.urlparse(url)
    lowered = urllib.parse.unquote((parsed.path + "?" + parsed.query).lower())
    if lowered.endswith(UNSUPPORTED_EXTENSIONS):
        return None
    if not allow_preview and _is_catalog_preview_url(url):
        return None
    if lowered.endswith(VIDEO_EXTENSIONS):
        return "video"
    if lowered.endswith(ARCHIVE_EXTENSIONS):
        return "archive"
    if lowered.endswith(IMAGE_EXTENSIONS):
        return "image"
    if parsed.scheme == "https" and parsed.netloc:
        return "image"
    return None


def _is_parallax_item(item: Any, payload: Any) -> bool:
    if not isinstance(item, dict):
        return False
    payload_type = payload.get("content_type") if isinstance(payload, dict) else ""
    content_type = str(item.get("content_type") or payload_type or item.get("source_section") or "").strip().lower()
    numeric_type = str(item.get("type") or "").strip()
    return content_type in {"parallax_wallpaper", "parallax"} or numeric_type == "4"


def _parallax_preview_urls(item: dict[str, Any]) -> list[str]:
    urls: list[str] = []
    for key in ("app_display_url", "preview_image", "static_thumbnail", "hq_thumbnail", "thumbnail", "first_frame_thumbnail"):
        value = item.get(key)
        if isinstance(value, str) and value.strip():
            urls.append(value.strip())
    config = item.get("thumbnail_config")
    if isinstance(config, dict):
        for layer in config.get("layers") or []:
            if isinstance(layer, dict):
                value = layer.get("url")
                if isinstance(value, str) and value.strip():
                    urls.append(value.strip())
    return urls


def _all_resource_urls(payloads: list[Any]) -> tuple[list[str], set[str]]:
    seen: set[str] = set()
    allow_preview_urls: set[str] = set()
    urls: list[str] = []

    def add(raw_url: str, *, allow_preview: bool = False) -> None:
        url = raw_url.strip()
        if _resource_kind_from_url(url, allow_preview=allow_preview) is None:
            return
        if url not in seen:
            seen.add(url)
            urls.append(url)
        if allow_preview:
            allow_preview_urls.add(url)

    for payload in payloads:
        for item in _payload_items(payload):
            if _is_parallax_item(item, payload):
                for url in _parallax_preview_urls(item):
                    add(url, allow_preview=True)
        for value in _walk(payload):
            if isinstance(value, str):
                add(value)
    return urls, allow_preview_urls


def _worker_base_url() -> str:
    user_store = _env("USER_STORE_API_BASE_URL").rstrip("/")
    if user_store:
        return user_store
    catalog_base = (_env("PRISM_CATALOG_BASE_URL") or _env("CATALOG_BASE_URL") or _env("WALL_PICS_CATALOG_BASE_URL")).rstrip("/")
    suffix = "/v1/catalog"
    if catalog_base.endswith(suffix):
        return catalog_base[: -len(suffix)]
    return ""


def _media_image_proxy_url(source_url: str, width: int, quality: int) -> str:
    base = _worker_base_url()
    if not base:
        return source_url
    query = urllib.parse.urlencode({"src": source_url, "w": str(width), "q": str(quality)})
    return f"{_url_join(base, '/v1/media/image')}?{query}"


def _media_video_proxy_url(source_url: str) -> str:
    base = _worker_base_url()
    if not base:
        return source_url
    path = urllib.parse.urlparse(source_url).path.lower()
    ext = "mov" if path.endswith(".mov") else "mp4"
    query = urllib.parse.urlencode({"src": source_url})
    return f"{_url_join(base, f'/v1/media/video.{ext}')}?{query}"


def _resource_candidates(source_urls: list[str], *, allow_preview_urls: set[str] | None = None) -> list[ResourceCandidate]:
    include_video_proxy = _bool_env("PRISM_SEED_MEDIA_INCLUDE_VIDEO_PROXY", True)
    include_image_proxy_variants = _bool_env("PRISM_SEED_MEDIA_INCLUDE_IMAGE_PROXY_VARIANTS", True)
    allowed_previews = allow_preview_urls or set()
    seen: set[tuple[str, str]] = set()
    candidates: list[ResourceCandidate] = []

    def add(lookup_url: str, fetch_url: str, kind: str) -> None:
        key = (lookup_url.strip(), kind)
        if not key[0] or key in seen:
            return
        seen.add(key)
        candidates.append(ResourceCandidate(lookup_url=key[0], fetch_url=fetch_url.strip() or key[0], kind=kind))

    for source_url in source_urls:
        kind = _resource_kind_from_url(source_url, allow_preview=source_url in allowed_previews)
        if kind is None:
            continue
        if kind == "image":
            full_proxy = _media_image_proxy_url(source_url, 3840, 98)
            if include_image_proxy_variants:
                for width, quality in ((1080, 90), (1920, 94)):
                    proxy = _media_image_proxy_url(source_url, width, quality)
                    add(proxy, proxy, "image")
            add(source_url, full_proxy, "image")
            if include_image_proxy_variants:
                add(full_proxy, full_proxy, "image")
        elif kind == "video":
            add(source_url, source_url, "video")
            if include_video_proxy:
                proxy = _media_video_proxy_url(source_url)
                if proxy != source_url:
                    add(proxy, proxy, "video")
        elif kind == "archive":
            add(source_url, source_url, "archive")
    return candidates


def _sha_url(raw_url: str) -> str:
    return hashlib.sha256(raw_url.strip().encode("utf-8")).hexdigest()


def _download_asset(
    fetch_url: str,
    fallback_urls: list[str],
    expected_kind: str,
    per_file_max_bytes: int,
) -> tuple[str, bytes, str, str] | None:
    headers = {"Accept": "*/*", "User-Agent": "PrismBundledMediaBuilder/2.0"}
    urls = [fetch_url, *[url for url in fallback_urls if url != fetch_url]]
    for url in urls:
        response = _request_bytes(
            url,
            headers,
            max_bytes=per_file_max_bytes,
            timeout=90 if expected_kind != "image" else 45,
        )
        if response is None:
            continue
        data, content_type = response
        detected = _detect_kind(data, content_type, url, expected_kind)
        if detected == expected_kind and data:
            return url, data, content_type, detected
    return None


def _write_manifest_pack(candidates: list[ResourceCandidate], *, limit: int, max_bytes: int, per_file_max_bytes: int) -> tuple[int, int, int]:
    if MEDIA_DIR.exists():
        shutil.rmtree(MEDIA_DIR)
    MEDIA_DIR.mkdir(parents=True, exist_ok=True)
    MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)

    grouped: dict[str, list[ResourceCandidate]] = {}
    for candidate in candidates:
        grouped.setdefault(candidate.fetch_url, []).append(candidate)
    groups = list(grouped.items())

    workers = max(1, _int_env("PRISM_SEED_MEDIA_DOWNLOAD_WORKERS", 6))
    entries: list[dict[str, Any]] = []
    entry_keys: set[str] = set()
    fetch_assets: dict[str, dict[str, Any]] = {}
    total_bytes = 0
    failures = 0
    next_group = 0

    def submit_next(executor: ThreadPoolExecutor, pending: dict[Any, tuple[str, list[ResourceCandidate]]]) -> None:
        nonlocal next_group
        while next_group < len(groups) and len(pending) < workers:
            fetch_url, group = groups[next_group]
            next_group += 1
            kind = group[0].kind
            fallback_urls = [candidate.lookup_url for candidate in group]
            future = executor.submit(_download_asset, fetch_url, fallback_urls, kind, per_file_max_bytes)
            pending[future] = (fetch_url, group)

    with ThreadPoolExecutor(max_workers=workers) as executor:
        pending: dict[Any, tuple[str, list[ResourceCandidate]]] = {}
        submit_next(executor, pending)
        while pending and len(entries) < limit and total_bytes < max_bytes:
            done, _ = wait(pending.keys(), return_when=FIRST_COMPLETED)
            for future in done:
                fetch_url, group = pending.pop(future)
                try:
                    result = future.result()
                except Exception:
                    result = None
                if result is None:
                    failures += 1
                    continue
                used_url, data, content_type, detected = result
                if total_bytes + len(data) > max_bytes:
                    for other in pending:
                        other.cancel()
                    pending.clear()
                    break
                asset_key = _sha_url(used_url)
                asset = MEDIA_DIR / f"{asset_key}.bin"
                asset.write_bytes(_crypt(data))
                asset_record = {
                    "asset": asset.as_posix(),
                    "length": len(data),
                    "extension": _extension_for(detected, content_type, used_url),
                    "kind": detected,
                }
                fetch_assets[fetch_url] = asset_record
                total_bytes += len(data)
                for candidate in group:
                    key = _sha_url(candidate.lookup_url)
                    if key in entry_keys or len(entries) >= limit:
                        continue
                    entry_keys.add(key)
                    entries.append(
                        {
                            "key": key,
                            "asset": asset_record["asset"],
                            "length": asset_record["length"],
                            "extension": asset_record["extension"],
                            "kind": asset_record["kind"],
                        }
                    )
                if len(fetch_assets) % 25 == 0:
                    print(
                        f"Bundled media progress: {len(fetch_assets)} assets, {len(entries)} entries, {total_bytes} bytes",
                        flush=True,
                    )
            submit_next(executor, pending)

    manifest = {
        "version": 3,
        "generated_at": int(time.time()),
        "count": len(entries),
        "asset_count": len(fetch_assets),
        "media_bytes": total_bytes,
        "entries": entries,
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, separators=(",", ":"), sort_keys=True))
    return len(entries), len(fetch_assets), failures


def main() -> int:
    _load_dotenv(Path(".env"))
    limit = _int_env("PRISM_SEED_MEDIA_LIMIT", DEFAULT_LIMIT)
    max_bytes = _int_env("PRISM_SEED_MEDIA_MAX_BYTES", DEFAULT_MAX_BYTES)
    per_file_max_bytes = _int_env("PRISM_SEED_MEDIA_PER_FILE_MAX_BYTES", PER_FILE_MAX_BYTES)
    layout = (_env("PRISM_SEED_MEDIA_LAYOUT") or "files").lower()

    payloads = _catalog_payloads()
    urls, allow_preview_urls = _all_resource_urls(payloads)
    candidates = _resource_candidates(urls, allow_preview_urls=allow_preview_urls)

    if layout == "legacy":
        media: dict[str, bytes] = {}
        total = 0
        for candidate in candidates:
            if len(media) >= limit or total >= max_bytes:
                break
            response = _request_bytes(candidate.fetch_url, {"Accept": "*/*", "User-Agent": "PrismBundledMediaBuilder/2.0"}, max_bytes=per_file_max_bytes)
            if response is None:
                continue
            data, content_type = response
            if _detect_kind(data, content_type, candidate.fetch_url, candidate.kind) != "image":
                continue
            if total + len(data) > max_bytes:
                break
            media[_sha_url(candidate.lookup_url)] = data
            total += len(data)
        packed = _write_legacy_pack(media)
        MANIFEST_PATH.write_text(json.dumps({"version": 3, "generated_at": int(time.time()), "count": 0, "entries": []}))
        print(f"Prism legacy media pack: {len(media)} images, {total} media bytes, {packed} packed bytes")
        return 0

    entries, assets, failures = _write_manifest_pack(candidates, limit=limit, max_bytes=max_bytes, per_file_max_bytes=per_file_max_bytes)
    _write_legacy_pack({})
    manifest = json.loads(MANIFEST_PATH.read_text())
    print(
        "Prism bundled media pack: "
        f"{entries} lookup entries, {assets} asset files, {manifest.get('media_bytes', 0)} media bytes, "
        f"{len(payloads)} payloads, {len(urls)} source urls, {failures} failed resources, "
        f"manifest={MANIFEST_PATH}, media_dir={MEDIA_DIR}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

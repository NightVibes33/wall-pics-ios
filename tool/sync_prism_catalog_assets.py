#!/usr/bin/env python3
"""Download Prism catalog JSON pages into Flutter assets for offline listing."""

from __future__ import annotations

import json
import os
import pathlib
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from typing import Any


OUT_DIR = pathlib.Path("assets/catalog")
BASE_CATALOG_FILES = (
    "prism_index.json",
    "prism_categories.json",
    "prism_category_lite.json",
    "prism_category_trees.json",
    "prism_category_ids.json",
    "prism_item_locations.json",
    "prism_popular_searches.json",
    "prism_search_suggestions.json",
    "prism_search_index.json",
    "prism_bootstrap_home.json",
)
PAGE_CATALOG_PREFIXES = {
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
}


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


def _load_dotenv(path: pathlib.Path) -> None:
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


def _catalog_base_url() -> str:
    for name in ("PRISM_CATALOG_BASE_URL", "CATALOG_BASE_URL", "WALL_PICS_CATALOG_BASE_URL"):
        value = _env(name).rstrip("/")
        if value:
            return value
    user_store = _env("USER_STORE_API_BASE_URL").rstrip("/")
    if user_store:
        return f"{user_store}/v1/catalog"
    raise SystemExit("Missing PRISM_CATALOG_BASE_URL or USER_STORE_API_BASE_URL")


def _url_join(base: str, path: str) -> str:
    return urllib.parse.urljoin(base.rstrip("/") + "/", path.lstrip("/"))


def _request_json(base: str, file_name: str) -> Any:
    url = _url_join(base, file_name)
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json",
            "User-Agent": "PrismCatalogAssetSync/1.0",
        },
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        body = response.read()
    return json.loads(body.decode("utf-8"))


def _catalog_asset_path_probe(raw_url: str) -> str:
    parsed = urllib.parse.urlparse(raw_url)
    probes = [parsed.path]
    query = urllib.parse.parse_qs(parsed.query)
    src = (query.get("src") or [""])[0]
    if src:
        probes.append(urllib.parse.urlparse(src).path)
    return urllib.parse.unquote("?".join(probes).lower())


def _has_wallpics_brand_path_marker(raw_url: str) -> bool:
    probe = _catalog_asset_path_probe(raw_url)
    return any(token in probe for token in ("/wallpics/", "wallpics_", "wallpics-", "wallpics."))


def _is_branded_asset_string(value: str) -> bool:
    raw = value.strip()
    if not raw.startswith(("http://", "https://")):
        return False
    parsed = urllib.parse.urlparse(raw)
    decoded = urllib.parse.unquote((parsed.path + "?" + parsed.query).lower())
    return any(marker in decoded for marker in ("watermark", "brand", "logo")) or _has_wallpics_brand_path_marker(raw)


def _normalize_label(value: Any) -> str:
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9]+", " ", str(value or "").lower())).strip()


def _is_blocked_catalog_label(value: Any) -> bool:
    normalized = _normalize_label(value)
    if not normalized:
        return False
    compact = normalized.replace(" ", "")
    tokens = set(normalized.split())
    blocked_terms = {"wallpics", "wallpic", "desktop", "macbook", "computer", "monitor", "tablet", "ipad", "widescreen"}
    return any(term in tokens or compact == term for term in blocked_terms)


def _is_blocked_category(row: Any) -> bool:
    if not isinstance(row, dict):
        return False
    return any(_is_blocked_catalog_label(row.get(key)) for key in ("name", "slug", "description", "extended_name", "parent_slug"))


def _is_blocked_catalog_item(item: Any) -> bool:
    if not isinstance(item, dict):
        return False
    if any(_is_blocked_catalog_label(item.get(key)) for key in ("name", "slug", "description")):
        return True
    for category in item.get("categories") or []:
        if not isinstance(category, dict):
            continue
        if _is_blocked_category(category):
            return True
        child = category.get("child")
        while isinstance(child, dict):
            if _is_blocked_category(child):
                return True
            child = child.get("child")
    for tag in item.get("tags") or []:
        if isinstance(tag, dict) and _is_blocked_catalog_label(tag.get("name")):
            return True
        if isinstance(tag, str) and _is_blocked_catalog_label(tag):
            return True
    return False


def _sanitize_payload(value: Any) -> Any:
    if isinstance(value, dict):
        sanitized: dict[str, Any] = {}
        for key, entry in value.items():
            if key in {"wallpapers", "items", "data", "results", "profile_pictures"} and isinstance(entry, list):
                sanitized[key] = [_sanitize_payload(row) for row in entry if not _is_blocked_catalog_item(row)]
            elif key == "categories" and isinstance(entry, list):
                sanitized[key] = [_sanitize_payload(row) for row in entry if not _is_blocked_category(row)]
            else:
                sanitized[key] = _sanitize_payload(entry)
        return sanitized
    if isinstance(value, list):
        sanitized = [_sanitize_payload(entry) for entry in value]
        return [entry for entry in sanitized if not (isinstance(entry, str) and entry == "")]
    if isinstance(value, str) and _is_branded_asset_string(value):
        return ""
    return value


def _write_json(file_name: str, payload: Any) -> int:
    target = OUT_DIR / file_name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(_sanitize_payload(payload), separators=(",", ":"), sort_keys=True), encoding="utf-8")
    return target.stat().st_size


def _clean_old_catalog_json() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for path in OUT_DIR.glob("prism_*.json"):
        path.unlink()


def _section_page_prefix(section: dict[str, Any]) -> str:
    file_name = pathlib.PurePosixPath(str(section.get("file", ""))).name
    if file_name.endswith(".json"):
        return file_name[:-5]
    return ""


def main() -> int:
    _load_dotenv(pathlib.Path(".env"))
    base = _catalog_base_url()
    max_pages = _int_env("PRISM_BUNDLE_CATALOG_MAX_PAGES", 500)
    _clean_old_catalog_json()

    downloaded: list[tuple[str, int]] = []

    def fetch_write(file_name: str) -> Any:
        payload = _request_json(base, file_name)
        size = _write_json(file_name, payload)
        downloaded.append((file_name, size))
        return payload

    index = fetch_write("prism_index.json")
    for file_name in BASE_CATALOG_FILES:
        if file_name == "prism_index.json":
            continue
        try:
            fetch_write(file_name)
        except (OSError, urllib.error.HTTPError, urllib.error.URLError, json.JSONDecodeError) as error:
            print(f"Skipping optional catalog file {file_name}: {error}", flush=True)

    sections = index.get("sections") if isinstance(index, dict) else None
    if not isinstance(sections, dict):
        raise SystemExit("Catalog index does not contain sections")

    page_files = 0
    for section in sections.values():
        if not isinstance(section, dict):
            continue
        prefix = _section_page_prefix(section)
        last_page = section.get("last_page") or section.get("page_count")
        try:
            last_page_int = int(last_page)
        except (TypeError, ValueError):
            continue
        if not prefix or prefix not in PAGE_CATALOG_PREFIXES or last_page_int <= 0:
            continue
        for page in range(1, min(last_page_int, max_pages) + 1):
            file_name = f"{prefix}_page_{page:03d}.json"
            try:
                fetch_write(file_name)
            except (OSError, urllib.error.HTTPError, urllib.error.URLError, json.JSONDecodeError) as error:
                print(f"Stopping {prefix} catalog sync at missing page {file_name}: {error}", flush=True)
                break
            page_files += 1

    total_bytes = sum(size for _, size in downloaded)
    print(
        "Prism catalog assets: "
        f"{len(downloaded)} json files, {page_files} page files, {total_bytes} bytes, base={base}",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Remove Firebase plugin registrations from Flutter's generated iOS registrant.

Unsigned/sideload builds run without Firebase. Flutter's native Firebase plugins can
configure themselves during plugin registration before Dart main() runs, so skipping
Firebase in Dart is not enough.
"""

from __future__ import annotations

import re
import sys
import json
from pathlib import Path

FIREBASE_MODULES = {
    "cloud_firestore",
    "cloud_functions",
    "firebase_analytics",
    "firebase_auth",
    "firebase_core",
    "firebase_messaging",
    "firebase_remote_config",
}

FIREBASE_CLASS_MARKERS = (
    "CloudFirestore",
    "CloudFunctions",
    "FirebaseAnalytics",
    "FirebaseFirestore",
    "FirebaseFunctions",
    "FirebaseAuth",
    "FLTFirebase",
    "FirebaseMessaging",
    "FirebaseRemoteConfig",
)


def strip_import_block(text: str, module: str) -> str:
    pattern = re.compile(
        rf"#if __has_include\(<{re.escape(module)}/[^>]+>\)\n"
        rf"#import <{re.escape(module)}/[^>]+>\n"
        rf"#else\n"
        rf"@import {re.escape(module)};\n"
        rf"#endif\n",
        re.MULTILINE,
    )
    return pattern.sub("", text)


def should_drop_line(line: str) -> bool:
    lowered = line.lower()
    if any(module in lowered for module in FIREBASE_MODULES):
        return True
    return any(marker in line for marker in FIREBASE_CLASS_MARKERS)


def strip_plugin_dependencies(project_root: Path) -> int:
    dependencies_path = project_root / ".flutter-plugins-dependencies"
    if not dependencies_path.exists():
        print(f"plugin dependencies not found: {dependencies_path}")
        return 0

    payload = json.loads(dependencies_path.read_text(encoding="utf-8"))
    plugins = payload.get("plugins")
    if not isinstance(plugins, dict):
        return 0

    ios_plugins = plugins.get("ios")
    if not isinstance(ios_plugins, list):
        return 0

    retained = []
    removed = 0
    for plugin in ios_plugins:
        if isinstance(plugin, dict) and plugin.get("name") in FIREBASE_MODULES:
            removed += 1
            continue
        retained.append(plugin)

    if removed:
        plugins["ios"] = retained
        dependencies_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    return removed


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: strip_ios_firebase_registrant.py <GeneratedPluginRegistrant.m>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    project_root = path.resolve().parents[2]
    dependency_removed = strip_plugin_dependencies(project_root)
    if dependency_removed:
        print(f"Removed {dependency_removed} Firebase iOS plugins from {project_root / '.flutter-plugins-dependencies'}")

    if not path.exists():
        print(f"registrant not found: {path}", file=sys.stderr)
        return 1

    original = path.read_text(encoding="utf-8")
    stripped = original
    for module in FIREBASE_MODULES:
        stripped = strip_import_block(stripped, module)

    stripped_lines = [line for line in stripped.splitlines() if not should_drop_line(line)]
    stripped = "\n".join(stripped_lines).rstrip() + "\n"

    removed = len(original.splitlines()) - len(stripped.splitlines())
    path.write_text(stripped, encoding="utf-8")
    print(f"Removed {removed} Firebase registrant lines from {path}")

    remaining = [line for line in stripped.splitlines() if should_drop_line(line)]
    if remaining:
        print("Firebase registrant references remain:", file=sys.stderr)
        for line in remaining:
            print(line, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

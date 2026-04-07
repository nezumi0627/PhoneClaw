#!/usr/bin/env python3
"""
bump_version.py - PhoneClaw バージョン管理スクリプト
使い方:
    python3 scripts/bump_version.py patch    # 1.0.0 → 1.0.1
    python3 scripts/bump_version.py minor    # 1.0.0 → 1.1.0
    python3 scripts/bump_version.py major    # 1.0.0 → 2.0.0
    python3 scripts/bump_version.py build    # ビルド番号だけインクリメント
"""

import sys
import subprocess
import plistlib
import re
from pathlib import Path

PLIST_PATH = Path(__file__).parent.parent / "Info.plist"


def read_plist():
    with open(PLIST_PATH, "rb") as f:
        return plistlib.load(f)


def write_plist(data):
    with open(PLIST_PATH, "wb") as f:
        plistlib.dump(data, f, fmt=plistlib.FMT_XML, sort_keys=False)


def bump(kind: str):
    data = read_plist()

    version_str = data.get("CFBundleShortVersionString", "1.0.0")
    build_str = data.get("CFBundleVersion", "1")

    # バージョン文字列が Xcode 変数参照 ($(MARKETING_VERSION)) の場合はスキップ
    if version_str.startswith("$("):
        print(
            f"⚠️  CFBundleShortVersionString が Xcode 変数 ({version_str}) のため直接書き換えできません。"
        )
        print("   project.pbxproj の MARKETING_VERSION を手動で変更してください。")
        return

    major, minor, patch = map(int, version_str.split("."))
    build = int(build_str)

    if kind == "major":
        major += 1
        minor = 0
        patch = 0
        build += 1
    elif kind == "minor":
        minor += 1
        patch = 0
        build += 1
    elif kind == "patch":
        patch += 1
        build += 1
    elif kind == "build":
        build += 1
    else:
        print(f"Unknown bump type: {kind}")
        sys.exit(1)

    new_version = f"{major}.{minor}.{patch}"
    data["CFBundleShortVersionString"] = new_version
    data["CFBundleVersion"] = str(build)

    write_plist(data)
    print(f"✅ Bumped: {version_str} ({build_str}) → {new_version} ({build})")


if __name__ == "__main__":
    kind = sys.argv[1] if len(sys.argv) > 1 else "patch"
    bump(kind)

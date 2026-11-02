#!/usr/bin/env python3
# =============================================================================
# EH3D-IOS-CONTROL - tools/check_ios_build.py
# Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
# GPL-3.0-or-later - see LICENSE
# =============================================================================
"""Checks the versions of the iPhone app, before the app is built and in the app that was built.

Before (any machine):   python tools/check_ios_build.py
    the version of the manifest is the marketing version of project.yml, the number of the build is a whole number that follows the last part of the version (0.0.6 is
    build 6), and the app takes both from those settings instead of a literal.
After (a Mac, once the app target is built):   python tools/check_ios_build.py path/to/EH3D.app
    the Info.plist inside the built app shows that same version and that same build number.

Prints IOS_BUILD=PASS or FAIL with the reasons.
"""
import json
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ["en", "es", "de", "fr", "it", "ja", "zh-Hans", "pt-PT"]


def setting(text: str, name: str):
    found = re.search(rf'{name}:\s*"([^"]*)"', text)
    return found.group(1) if found else None


def source_problems(root: Path) -> list[str]:
    """What the project description says about the version, against the manifest."""
    problems = []
    version = json.loads((root / "eh3d.project.json").read_text(encoding="utf-8")).get("version", "?")
    text = (root / "project.yml").read_text(encoding="utf-8")
    marketing, build = setting(text, "MARKETING_VERSION"), setting(text, "CURRENT_PROJECT_VERSION")
    if marketing != version:
        problems.append(f"project.yml MARKETING_VERSION ({marketing}) is not the version of the manifest ({version})")
    if build is None or not build.isdigit() or int(build) < 1:
        problems.append(f"project.yml CURRENT_PROJECT_VERSION ({build}) is not a whole number from 1")
    else:
        parts = version.split(".")
        if len(parts) == 3 and parts[2].isdigit() and int(build) != int(parts[2]):
            problems.append(f"project.yml CURRENT_PROJECT_VERSION ({build}) does not follow the last part of the version {version}")
    if 'CFBundleShortVersionString: "$(MARKETING_VERSION)"' not in text or 'CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"' not in text:
        problems.append("project.yml must give CFBundleShortVersionString and CFBundleVersion from the settings, not as literals")
    declared = re.search(r"CFBundleLocalizations:\s*\[([^\]]*)\]", text)
    if not declared or [x.strip() for x in declared.group(1).split(",")] != LANGUAGES:
        problems.append(f"project.yml must declare the eight languages {', '.join(LANGUAGES)} in CFBundleLocalizations")
    return problems


def built_problems(root: Path, app: Path) -> list[str]:
    """What the built app says about itself, against the same settings."""
    plist = app / "Info.plist"
    if not plist.is_file():
        return [f"there is no Info.plist in {app}: build the app target first"]
    info = plistlib.loads(plist.read_bytes())
    text = (root / "project.yml").read_text(encoding="utf-8")
    problems = []
    for key, name in (("CFBundleShortVersionString", "MARKETING_VERSION"), ("CFBundleVersion", "CURRENT_PROJECT_VERSION")):
        if info.get(key) != setting(text, name):
            problems.append(f"the built app shows {key} {info.get(key)}, project.yml says {setting(text, name)}")
    return problems


def main(argv: list[str]) -> int:
    problems = source_problems(ROOT)
    if len(argv) > 1:
        problems += built_problems(ROOT, Path(argv[1]))
    for problem in problems:
        print("  FAIL", problem)
    print(f"IOS_BUILD={'FAIL' if problems else 'PASS'}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

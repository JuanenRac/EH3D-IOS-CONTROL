#!/usr/bin/env python3
# =============================================================================
# EH3D-IOS-CONTROL - tools/check_ios_build.py
# Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
# GPL-3.0-or-later - see LICENSE
# =============================================================================
"""Checks the versions and the languages of the iPhone app, before the app is built and in the app that was built.

Before (any machine):   python tools/check_ios_build.py
    the version of the manifest is the marketing version of project.yml, the number of the build is a whole number that follows the version like an odometer (major x 100 + minor x 10 + patch: 0.1.0 is build 10, so it never goes down; 0.0.6 is
    build 6), and the app takes both from those settings instead of a literal. The app has the eight languages and no other: CFBundleLocalizations lists exactly them and App holds one .lproj folder for each.
After (a Mac, once the app target is built):   python tools/check_ios_build.py path/to/EH3D.app
    the Info.plist inside the built app shows that same version and that same build number, and the app carries the eight languages and no other.

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


def language_problems(where: str, found: list[str]) -> list[str]:
    """A language that is missing, one too many or one said twice, in a list that has to be the eight languages."""
    problems = []
    extra = sorted(set(found) - set(LANGUAGES))
    missing = [x for x in LANGUAGES if x not in found]
    if extra:
        problems.append(f"{where}: not among the eight languages: {', '.join(extra)}")
    if missing:
        problems.append(f"{where}: lacks some of the eight languages: {', '.join(missing)}")
    if len(found) != len(set(found)):
        problems.append(f"{where}: names a language twice")
    return problems


def folder_languages(folder: Path) -> list[str]:
    """The languages of the .lproj folders anywhere under a folder (Base is not a language)."""
    return sorted({p.stem for p in folder.rglob("*.lproj") if p.is_dir() and p.stem != "Base"})


def source_problems(root: Path) -> list[str]:
    """What the project description says about the version, against the manifest, and about the languages."""
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
        if len(parts) == 3 and all(p.isdigit() for p in parts):
            expected = int(parts[0]) * 100 + int(parts[1]) * 10 + int(parts[2])
            if int(build) != expected:
                problems.append(f"project.yml CURRENT_PROJECT_VERSION ({build}) does not follow the version {version} (it should be {expected})")
    if 'CFBundleShortVersionString: "$(MARKETING_VERSION)"' not in text or 'CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"' not in text:
        problems.append("project.yml must give CFBundleShortVersionString and CFBundleVersion from the settings, not as literals")
    declared = re.search(r"CFBundleLocalizations:\s*\[([^\]]*)\]", text)
    if not declared:
        problems.append(f"project.yml must declare the eight languages {', '.join(LANGUAGES)} in CFBundleLocalizations, as one list in brackets")
    else:
        listed = [x.strip().strip("\"'") for x in declared.group(1).split(",") if x.strip()]
        problems += language_problems("CFBundleLocalizations of project.yml", listed)
    problems += language_problems("the .lproj folders of App", folder_languages(root / "App"))
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
    problems += language_problems("CFBundleLocalizations of the built app", list(info.get("CFBundleLocalizations", [])))
    problems += language_problems("the .lproj folders of the built app", sorted(p.stem for p in app.glob("*.lproj") if p.stem != "Base"))
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

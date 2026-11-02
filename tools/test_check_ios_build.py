# EH3D-IOS-CONTROL - tools/test_check_ios_build.py: the check of the versions of the app, with small project descriptions made for the test.   python -I tools/test_check_ios_build.py
import importlib.util
import json
import plistlib
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("check_ios_build", Path(__file__).resolve().parent / "check_ios_build.py")
C = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(C)

PROJECT = """targets:
  EH3D:
    info:
      properties:
        CFBundleShortVersionString: "$(MARKETING_VERSION)"
        CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"
        CFBundleLocalizations: [en, es, de, fr, it, ja, zh-Hans, pt-PT]
    settings:
      base:
        MARKETING_VERSION: "{marketing}"
        CURRENT_PROJECT_VERSION: "{build}"
"""


class Versions(unittest.TestCase):
    def make(self, version="0.0.6", marketing="0.0.6", build="6", project=None) -> Path:
        root = Path(self._tmp.name)
        (root / "eh3d.project.json").write_text(json.dumps({"version": version}), encoding="utf-8")
        (root / "project.yml").write_text((project or PROJECT).format(marketing=marketing, build=build), encoding="utf-8")
        return root

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()

    def tearDown(self):
        self._tmp.cleanup()

    def test_a_project_that_follows_its_manifest_passes(self):
        self.assertEqual(C.source_problems(self.make()), [])

    def test_another_marketing_version_or_build_is_a_problem(self):
        self.assertTrue(any("MARKETING_VERSION" in p for p in C.source_problems(self.make(marketing="0.0.5"))))
        self.assertTrue(any("last part" in p for p in C.source_problems(self.make(build="5"))))
        self.assertTrue(any("whole number" in p for p in C.source_problems(self.make(build="x"))))
        self.assertTrue(any("whole number" in p for p in C.source_problems(self.make(build="0"))))

    def test_a_literal_version_in_the_bundle_or_a_language_missing_is_a_problem(self):
        literal = PROJECT.replace('CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"', 'CFBundleVersion: "6"')
        self.assertTrue(any("literals" in p for p in C.source_problems(self.make(project=literal))))
        short = PROJECT.replace(", pt-PT", "")
        self.assertTrue(any("eight languages" in p for p in C.source_problems(self.make(project=short))))

    def test_the_built_app_must_show_the_version_and_the_build_of_the_project(self):
        root = self.make()
        app = root / "EH3D.app"
        app.mkdir()
        self.assertTrue(any("Info.plist" in p for p in C.built_problems(root, app)))
        (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleShortVersionString": "0.0.6", "CFBundleVersion": "6"}))
        self.assertEqual(C.built_problems(root, app), [])
        (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleShortVersionString": "0.0.5", "CFBundleVersion": "6"}))
        self.assertEqual(len(C.built_problems(root, app)), 1)

    def test_the_project_of_this_repository_passes(self):
        self.assertEqual(C.source_problems(C.ROOT), [])


if __name__ == "__main__":
    unittest.main()

# EH3D-IOS-CONTROL - tools/test_check_ios_build.py: the check of the versions and the languages of the app, with small project descriptions made for the test.   python -I tools/test_check_ios_build.py
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
        for language in C.LANGUAGES:
            (root / "App" / "Resources" / f"{language}.lproj").mkdir(parents=True, exist_ok=True)
        return root

    def bundle(self, root: Path, name="EH3D.app", languages=None, listed=None, version="0.0.6") -> Path:
        app = root / name
        app.mkdir()
        for language in C.LANGUAGES if languages is None else languages:
            (app / f"{language}.lproj").mkdir()
        info = {"CFBundleShortVersionString": version, "CFBundleVersion": "6", "CFBundleLocalizations": C.LANGUAGES if listed is None else listed}
        (app / "Info.plist").write_bytes(plistlib.dumps(info))
        return app

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()

    def tearDown(self):
        self._tmp.cleanup()

    def test_a_project_that_follows_its_manifest_passes(self):
        self.assertEqual(C.source_problems(self.make()), [])

    def test_the_build_number_follows_the_version_like_an_odometer(self):
        self.assertEqual(C.source_problems(self.make(version="0.0.9", marketing="0.0.9", build="9")), [])
        self.assertEqual(C.source_problems(self.make(version="0.1.0", marketing="0.1.0", build="10")), [])
        self.assertEqual(C.source_problems(self.make(version="0.1.1", marketing="0.1.1", build="11")), [])
        self.assertTrue(any("should be 10" in p for p in C.source_problems(self.make(version="0.1.0", marketing="0.1.0", build="1"))))
        self.assertTrue(any("whole number" in p for p in C.source_problems(self.make(version="0.1.0", marketing="0.1.0", build="0"))))

    def test_another_marketing_version_or_build_is_a_problem(self):
        self.assertTrue(any("MARKETING_VERSION" in p for p in C.source_problems(self.make(marketing="0.0.5"))))
        self.assertTrue(any("does not follow" in p for p in C.source_problems(self.make(build="5"))))
        self.assertTrue(any("whole number" in p for p in C.source_problems(self.make(build="x"))))
        self.assertTrue(any("whole number" in p for p in C.source_problems(self.make(build="0"))))

    def test_a_literal_version_in_the_bundle_or_a_language_missing_is_a_problem(self):
        literal = PROJECT.replace('CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"', 'CFBundleVersion: "6"')
        self.assertTrue(any("literals" in p for p in C.source_problems(self.make(project=literal))))
        short = PROJECT.replace(", pt-PT", "")
        self.assertTrue(any("eight languages" in p for p in C.source_problems(self.make(project=short))))

    def test_a_language_too_many_in_the_description_is_a_problem(self):
        for extra in ("pl", "pt-BR", "fr-CA"):
            found = C.source_problems(self.make(project=PROJECT.replace("pt-PT]", f"pt-PT, {extra}]")))
            self.assertEqual(len(found), 1, found)
            self.assertIn(extra, found[0])
        self.assertTrue(any("twice" in p for p in C.source_problems(self.make(project=PROJECT.replace("pt-PT]", "pt-PT, en]")))))
        none = PROJECT.replace("CFBundleLocalizations: [en, es, de, fr, it, ja, zh-Hans, pt-PT]", "UILaunchScreen: x")
        self.assertTrue(any("eight languages" in p for p in C.source_problems(self.make(project=none))))

    def test_a_language_folder_too_many_or_missing_is_a_problem(self):
        root = self.make()
        resources = root / "App" / "Resources"
        (resources / "Base.lproj").mkdir()
        self.assertEqual(C.source_problems(root), [])
        (root / "App" / "Other" / "ca.lproj").mkdir(parents=True)
        found = C.source_problems(root)
        self.assertEqual(len(found), 1, found)
        self.assertIn("ca", found[0])
        (root / "App" / "Other" / "ca.lproj").rmdir()
        (resources / "ja.lproj").rmdir()
        self.assertTrue(any("lacks" in p and "ja" in p for p in C.source_problems(root)))

    def test_the_built_app_must_show_the_version_and_the_build_of_the_project(self):
        root = self.make()
        empty = root / "Empty.app"
        empty.mkdir()
        self.assertTrue(any("Info.plist" in p for p in C.built_problems(root, empty)))
        self.assertEqual(C.built_problems(root, self.bundle(root)), [])
        self.assertEqual(len(C.built_problems(root, self.bundle(root, name="Old.app", version="0.0.5"))), 1)

    def test_the_built_app_must_carry_the_eight_languages_and_no_other(self):
        root = self.make()
        self.assertEqual(len(C.built_problems(root, self.bundle(root, name="Listed.app", listed=C.LANGUAGES + ["pl"]))), 1)
        more = C.built_problems(root, self.bundle(root, name="More.app", languages=C.LANGUAGES + ["pt-BR"]))
        self.assertTrue(any("pt-BR" in p for p in more))
        less = C.built_problems(root, self.bundle(root, name="Less.app", languages=[x for x in C.LANGUAGES if x != "de"]))
        self.assertTrue(any("lacks" in p and "de" in p for p in less))

    def test_the_project_of_this_repository_passes(self):
        self.assertEqual(C.source_problems(C.ROOT), [])


if __name__ == "__main__":
    unittest.main()

# EH3D-IOS-CONTROL - tools/test_check_coverage_floor.py: the reading of the coverage of the package and the floor, with small reports made for the test.   python -I tools/test_check_coverage_floor.py
import contextlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("check_coverage_floor", Path(__file__).resolve().parent / "check_coverage_floor.py")
C = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(C)


def report(files):
    """A report of llvm-cov: `files` is a list of (path, covered, count)."""
    return {"data": [{"files": [{"filename": name, "summary": {"lines": {"count": count, "covered": done, "percent": 0}}} for name, done, count in files], "totals": {}}], "type": "llvm.coverage.json.export"}


class Measuring(unittest.TestCase):
    def test_only_the_files_of_the_package_count(self):
        pair, files = C.measure(report([("/w/Sources/Eh3dCore/Models.swift", 8, 10), ("/w/Tests/Eh3dCoreTests/ModelsTests.swift", 50, 50), ("/w/App/HomeView.swift", 0, 100)]))
        self.assertEqual(pair, (8, 10))
        self.assertEqual(files, [("Models.swift", 8, 10)])

    def test_the_lines_of_all_the_files_are_added_up(self):
        pair, files = C.measure(report([("/w/Sources/Eh3dCore/B.swift", 1, 4), ("/w/Sources/Eh3dCore/A.swift", 3, 6)]))
        self.assertEqual(pair, (4, 10))
        self.assertEqual([name for name, _, _ in files], ["A.swift", "B.swift"])

    def test_a_windows_path_is_read_the_same(self):
        pair, _ = C.measure(report([("C:\\w\\Sources\\Eh3dCore\\Models.swift", 2, 4)]))
        self.assertEqual(pair, (2, 4))

    def test_a_report_without_data_or_files_has_no_lines(self):
        self.assertEqual(C.measure({})[0], (0, 0))
        self.assertEqual(C.measure({"data": [{}]})[0], (0, 0))
        self.assertEqual(C.measure({"data": [{"files": [{"filename": "/w/Sources/Eh3dCore/X.swift"}]}]})[0], (0, 0))

    def test_the_percent_of_nothing_is_zero(self):
        self.assertEqual(C.percent((0, 0)), 0.0)
        self.assertEqual(C.percent((1, 4)), 25.0)

    def test_a_package_of_another_name_is_not_counted(self):
        pair, _ = C.measure(report([("/w/Sources/Other/Models.swift", 5, 5)]))
        self.assertEqual(pair, (0, 0))


class Command(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def write(self, files, name="Eh3dCore.json"):
        path = self.root / name
        path.write_text(json.dumps(report(files)), encoding="utf-8")
        return path

    def run_tool(self, argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = C.main(argv)
        return code, out.getvalue(), err.getvalue()

    def test_a_report_above_the_floor_passes(self):
        path = self.write([("/w/Sources/Eh3dCore/Models.swift", 8, 10)])
        code, out, err = self.run_tool([str(path), "--floor", "70"])
        self.assertEqual(code, 0)
        self.assertIn("package 80.0 % (8/10 lines)", out)
        self.assertIn("COVERAGE=PASS", out)
        self.assertEqual(err, "")

    def test_a_report_below_the_floor_fails(self):
        path = self.write([("/w/Sources/Eh3dCore/Models.swift", 5, 10)])
        code, _, err = self.run_tool([str(path), "--floor", "70"])
        self.assertEqual(code, 1)
        self.assertIn("below the floor of 70 %", err)

    def test_exactly_the_floor_passes_and_no_floor_only_prints(self):
        path = self.write([("/w/Sources/Eh3dCore/Models.swift", 7, 10)])
        self.assertEqual(self.run_tool([str(path), "--floor", "70"])[0], 0)
        self.assertEqual(self.run_tool([str(path)])[0], 0)

    def test_the_list_gives_each_file(self):
        path = self.write([("/w/Sources/Eh3dCore/A.swift", 1, 2), ("/w/Sources/Eh3dCore/B.swift", 0, 0)])
        code, out, _ = self.run_tool([str(path), "--list"])
        self.assertEqual(code, 0)
        self.assertIn("A.swift: 50.0 % (1/2)", out)
        self.assertIn("B.swift: 100.0 % (0/0)", out)

    def test_no_report_is_an_error_of_the_check_and_not_a_pass(self):
        code, _, err = self.run_tool([str(self.root / "none.json"), "--floor", "1"])
        self.assertEqual(code, 2)
        self.assertIn("COVERAGE=ERROR", err)

    def test_a_report_that_is_not_json_is_an_error_of_the_check(self):
        path = self.root / "bad.json"
        path.write_text("{", encoding="utf-8")
        code, _, err = self.run_tool([str(path)])
        self.assertEqual(code, 2)
        self.assertIn("cannot be read", err)

    def test_a_report_with_no_lines_of_the_package_fails_because_something_was_renamed(self):
        path = self.write([("/w/App/HomeView.swift", 5, 5)])
        code, _, err = self.run_tool([str(path), "--floor", "1"])
        self.assertEqual(code, 1)
        self.assertIn("renamed", err)


if __name__ == "__main__":
    unittest.main()

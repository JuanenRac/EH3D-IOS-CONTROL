# EH3D-IOS-CONTROL - tools/check_coverage_floor.py: reads the coverage that `swift test --enable-code-coverage` writes (the JSON of llvm-cov) and fails when the lines of the package of rules are less covered than a floor.
#   python -I tools/check_coverage_floor.py CODECOV_JSON --floor 70
# Only the files of Sources/Eh3dCore count: that is the package with no screen in it. The screens of the app (App/) are built with Xcode and cannot be run by `swift test`.
# Exit code: 0 the floor holds, 1 the floor does not hold or the report has no lines of the package, 2 the report cannot be found or read.
import argparse
import json
import sys
from pathlib import Path

PACKAGE = "Sources/Eh3dCore/"


def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def measure(report: dict, package: str = PACKAGE):
    """((covered, total) lines of the files of the package, the list of (file, covered, total) of each one)."""
    covered = total = 0
    files = []
    for entry in report.get("data", []):
        for item in entry.get("files", []):
            name = str(item.get("filename", "")).replace("\\", "/")
            if package not in name:
                continue
            lines = item.get("summary", {}).get("lines", {})
            count, done = int(lines.get("count", 0)), int(lines.get("covered", 0))
            files.append((name.split(package, 1)[1], done, count))
            covered += done
            total += count
    return (covered, total), sorted(files)


def percent(pair) -> float:
    return 100.0 * pair[0] / pair[1] if pair[1] else 0.0


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Fails when the lines of the package of rules are less covered than a floor.")
    parser.add_argument("report", type=Path, help="the JSON of the coverage (the path that `swift test --show-codecov-path` prints)")
    parser.add_argument("--floor", type=float, default=0.0, help="least percent of lines covered (default 0: only print)")
    parser.add_argument("--list", action="store_true", help="also print the coverage of each file")
    args = parser.parse_args(argv)
    if not args.report.is_file():
        print(f"COVERAGE=ERROR no report at {args.report}", file=sys.stderr)
        return 2
    try:
        pair, files = measure(read(args.report))
    except (OSError, ValueError, AttributeError) as error:
        print(f"COVERAGE=ERROR {args.report} cannot be read: {error}", file=sys.stderr)
        return 2
    if pair[1] == 0:
        print("COVERAGE=FAIL the report has no lines of Sources/Eh3dCore (the package was renamed?)", file=sys.stderr)
        return 1
    if args.list:
        for name, done, count in files:
            print(f"  {name}: {100.0 * done / count if count else 100.0:.1f} % ({done}/{count})")
    print(f"COVERAGE package {percent(pair):.1f} % ({pair[0]}/{pair[1]} lines)")
    if percent(pair) < args.floor:
        print(f"COVERAGE=FAIL the package is covered {percent(pair):.1f} %, below the floor of {args.floor:g} %", file=sys.stderr)
        return 1
    print("COVERAGE=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

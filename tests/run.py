"""Run the original mod code with pinned GUT; using an autonomous Godot CLI environment."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import sys
import uuid
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
MOD = ROOT.parent
GUT_COMMIT = "c11ba9daf49b2ec127d6113be89534dc9ee21873"
DEFAULT_GODOT = MOD.parents[1] / "Godot/Godot_v3.4-stable_win64.exe"


def git_at(path, *args):
    return subprocess.check_output(
        ["git", "-c", f"safe.directory={path.as_posix()}", "-C", str(path), *args],
        text=True, timeout=15,
    ).strip()


def setup():
    source = MOD.parents[1] / "ExternalMods/Gut"
    if not source.exists():
        raise ValueError("Provide the local upstream GUT v7.4.3 checkout at ExternalMods/Gut")
    if git_at(source, "rev-parse", "HEAD") != GUT_COMMIT:
        raise ValueError("GUT source must be the pinned v7.4.3 commit")
    if git_at(source, "status", "--porcelain", "--", "addons/gut"):
        raise ValueError("GUT addon has local changes; refusing to copy it")
    shutil.copytree(source / "addons/gut", ROOT / "addons/gut", dirs_exist_ok=True)
    (ROOT / "addons/gut-revision.txt").write_text(GUT_COMMIT + "\n", encoding="utf-8")


def execute(godot, test_dir, test_filter="", timeout=30):
    test_dir = test_dir.resolve()
    relative_dir = test_dir.relative_to(ROOT).as_posix()
    # ponytail: flat, non-parameterized test_* methods only; use GUT's collector
    # when inner classes or parameterized cases are introduced.
    expected = {
        ("res://" + path.relative_to(ROOT).as_posix(), name)
        for path in test_dir.glob("test_*.gd")
        for name in re.findall(r"^func (test_\w+)\(", path.read_text(encoding="utf-8"), re.M)
        if test_filter in name
    }
    run_id = uuid.uuid4().hex
    output = ROOT / "results" / run_id
    output.mkdir(parents=True)
    report = output / "junit.xml"
    state = {
        "run_id": run_id, "status": "running", "expected_tests": len(expected),
        "started_at": datetime.now(timezone.utc).isoformat(),
        "godot": str(godot), "gut_commit": GUT_COMMIT,
        "target_revision": git_at(MOD, "rev-parse", "HEAD"),
        "target_worktree": git_at(MOD, "status", "--porcelain"),
        "geometry_sha256": hashlib.sha256(
            (MOD / "scripts/utils/GeometryUtils.gd").read_bytes()).hexdigest(),
        "source_sha256": {
            path.relative_to(MOD).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted([*MOD.glob("*.gd"), *(MOD / "scripts").rglob("*.gd")])
        },
        "runtime_policy_sha256": hashlib.sha256(
            (ROOT / "runtime_files.json").read_bytes()).hexdigest(),
    }
    state_file = output / "run.json"
    state_file.write_text(json.dumps(state, indent=2), encoding="utf-8")
    command = [
        str(godot), "--no-window", "--audio-driver", "Dummy", "--path", str(ROOT),
        "-s", "res://addons/gut/gut_cmdln.gd", f"-gdir=res://{relative_dir}",
        f"-gjunit_xml_file={report.as_posix()}", "-gexit",
    ]
    if test_filter:
        command.append(f"-gunit_test_name={test_filter}")
    errors = []
    log = ""
    try:
        process = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                                 encoding="utf-8", errors="replace", timeout=timeout)
        log = process.stdout + process.stderr
        version = re.search(r"Godot Engine v([^\r\n]+)", log)
        state["godot_version"] = version.group(1) if version else "unknown"
        state["exit_code"] = process.returncode
        if process.returncode != 0:
            errors.append(f"Godot exited with code {process.returncode}")
        if re.search(r"(?:SCRIPT ERROR|ERROR):", log):
            errors.append("Godot reported a script or engine error")
        cases = ET.parse(report).getroot().findall(".//testcase")
        actual = [(case.get("classname"), case.get("name")) for case in cases]
        if not expected or set(actual) != expected or len(actual) != len(expected):
            errors.append("Executed tests do not match the non-empty expected set")
        if any(case.get("status") != "pass" or int(case.get("assertions", "0")) == 0
               for case in cases):
            errors.append("A test failed, was skipped, or made no assertions")
        state["status"] = "failed" if errors else "passed"
    except subprocess.TimeoutExpired as error:
        log = "".join(part.decode("utf-8", errors="replace") if isinstance(part, bytes)
                      else part or "" for part in (error.stdout, error.stderr))
        state["status"] = "timeout"
        errors.append(f"Godot exceeded {timeout} seconds")
    except (OSError, ET.ParseError, ValueError) as error:
        state["status"] = "aborted"
        errors.append(str(error))
    (output / "output.log").write_text(log, encoding="utf-8")
    state["errors"] = errors
    state["finished_at"] = datetime.now(timezone.utc).isoformat()
    state_file.write_text(json.dumps(state, indent=2), encoding="utf-8")
    print(log)
    print(f"{state['status'].upper()}: {state_file}")
    return state


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=DEFAULT_GODOT)
    parser.add_argument("--setup", action="store_true", help="Install the pinned GUT addon")
    parser.add_argument("--test", default="", help="GUT method-name substring filter")
    parser.add_argument("--timeout", type=float, default=30)
    args = parser.parse_args()
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("--timeout must be finite and positive")
    if args.setup:
        setup()
    marker = ROOT / "addons/gut-revision.txt"
    if not marker.exists() or marker.read_text().strip() != GUT_COMMIT:
        parser.error("Run with --setup first to prepare GUT 7.4.3")
    state = execute(args.godot.resolve(), ROOT / "unit", args.test, args.timeout)
    return 0 if state["status"] == "passed" else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        sys.exit(str(error))

"""Check the reusable smoke suite against broken, disposable source copies."""

import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import uuid
import xml.etree.ElementTree as ET

from run import DEFAULT_GODOT, MOD, ROOT


def main():
    output = ROOT / "results" / ("runtime-check-" + uuid.uuid4().hex)
    output.mkdir(parents=True)
    cache = ROOT / ".cache"
    cache.mkdir(exist_ok=True)
    sources = [*MOD.glob("*.gd"), *(MOD / "scripts").rglob("*.gd")]
    policy = json.loads((ROOT / "runtime_files.json").read_text(encoding="utf-8"))
    expected_names = {"test_all_runtime_scripts_compile", "test_allowed_runtime_objects_construct",
                      "test_runtime_entry_sources_match_policy", "test_runtime_manifest_and_required_resources_exist"}
    outcomes = {}
    with tempfile.TemporaryDirectory(prefix="runtime_", dir=cache) as directory:
        mod = Path(directory)
        tests = mod / "tests"
        shutil.copytree(ROOT / "addons/gut", tests / "addons/gut")
        (tests / "unit").mkdir()
        shutil.copy2(ROOT / "unit/test_runtime_files.gd", tests / "unit")
        for name in (".gutconfig.json", "strict_results.gd"):
            shutil.copy2(ROOT / name, tests / name)
        shutil.copy2(MOD / policy["manifest"], mod / policy["manifest"])
        shutil.copytree(MOD / "icons", mod / "icons")
        for probe in ("passed", "syntax", "constructor", "unclassified", "missing_root", "empty", "escape", "loader", "manifest", "resource"):
            for source in sources:
                target = mod / source.relative_to(MOD)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
            config = json.loads(json.dumps(policy))
            shutil.copy2(MOD / policy["manifest"], mod / policy["manifest"])
            for resource in policy["required_resources"]:
                shutil.copy2(MOD / resource, mod / resource)
            extra = mod / "scripts/unclassified_probe.gd"
            extra.unlink(missing_ok=True)
            if probe == "syntax":
                (mod / "scripts/utils/GeometryUtils.gd").write_text("invalid gdscript\n", encoding="utf-8")
            elif probe == "constructor":
                path = mod / "scripts/guides/FillMarker.gd"
                path.write_text(path.read_text(encoding="utf-8").replace(
                    "func _init():\n\tpass", "func _init():\n\tvar value = null\n\tvalue.missing()"), encoding="utf-8")
            elif probe == "unclassified":
                extra.write_text("extends Reference\n", encoding="utf-8")
            elif probe == "missing_root":
                config["roots"].append("missing.gd")
            elif probe == "empty":
                config["roots"] = []
                config["construct"] = []
                config["load_only"] = {}
                config["root_scripts"] = False
            elif probe == "escape":
                config["roots"].append("../outside.gd")
            elif probe == "loader":
                path = mod / "scripts/guides/FillMarker.gd"
                path.write_text("# Violates the configured entry source policy\n" + path.read_text(encoding="utf-8"), encoding="utf-8")
            elif probe == "manifest":
                (mod / policy["manifest"]).write_text("invalid json", encoding="utf-8")
            elif probe == "resource":
                (mod / policy["required_resources"][0]).unlink()
            (tests / "runtime_files.json").write_text(json.dumps(config), encoding="utf-8")
            report = output / (probe + ".xml")
            result = subprocess.run([
                str(DEFAULT_GODOT), "--no-window", "--audio-driver", "Dummy",
                "--path", str(tests), "-s", "res://addons/gut/gut_cmdln.gd",
                "-gjunit_xml_file=" + report.as_posix(), "-gexit",
            ], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=30)
            log = result.stdout + result.stderr
            (output / (probe + ".log")).write_text(log, encoding="utf-8")
            try:
                cases = ET.parse(report).getroot().findall(".//testcase") if report.exists() else []
            except ET.ParseError:
                cases = []  # Malformed failure output must never count as success.
            passed = (result.returncode == 0 and not re.search(r"(?:SCRIPT ERROR|ERROR):", log)
                      and len(cases) == len(expected_names) and {case.get("name") for case in cases} == expected_names
                      and all(case.get("status") == "pass" and int(case.get("assertions", "0")) > 0 for case in cases))
            outcomes[probe] = "passed" if passed else "rejected"
            (output / "summary.json").write_text(json.dumps(outcomes, indent=2), encoding="utf-8")
            assert passed == (probe == "passed"), (probe, output)
    print(f"Runtime smoke checks passed: {len(outcomes)} real Godot scenarios; reports: {output}")


if __name__ == "__main__":
    main()

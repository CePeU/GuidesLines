"""Exercise real GUT failure modes; run after run.py --setup."""

import tempfile
from pathlib import Path

from run import DEFAULT_GODOT, ROOT, execute


def main():
    cache = ROOT / ".cache"
    cache.mkdir(exist_ok=True)
    probes = {
        "passed": ('assert_eq(1, 1)', "passed"),
        "failed": ('assert_eq(1, 2)', "failed"),
        "pending": ('pending("required test")', "failed"),
        "risky": ('pass', "failed"),
        "parse": ('this is invalid gdscript', "failed"),
        "runtime": ('assert_true(true)\n\tvar value = null\n\tvalue.missing()', "failed"),
        "empty": (None, "failed"),
        "timeout": ('while true:\n\t\tpass', "timeout"),
    }
    for name, (body, expected) in probes.items():
        with tempfile.TemporaryDirectory(prefix="probe_", dir=cache) as directory:
            if body is not None:
                Path(directory, "test_probe.gd").write_text(
                    'extends "res://addons/gut/test.gd"\nfunc test_probe():\n\t' + body + '\n',
                    encoding="utf-8",
                )
            state = execute(DEFAULT_GODOT, Path(directory), timeout=3 if name == "timeout" else 30)
            assert state["status"] == expected, (name, state)
    print(f"Runner checks passed: {len(probes)} real GUT scenarios")


if __name__ == "__main__":
    main()

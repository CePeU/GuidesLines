# GuidesLines standalone tests

This separate test solution runs original runtime scripts autonomously with
Godot CLI and GUT. Dependencies needed by individual scenarios are explicit test
inputs. No `project.godot` or executable reference stubs are needed.

## Project passport

| Field | Value |
| --- | --- |
| Target | `Choson.GuidesLines`, current checkout including uncommitted changes |
| Purpose | Catch script loading, constructor, data-model and geometry regressions |
| Scope | Runtime inventory, source layout, manifest/resources, reviewed constructors, model serialization/cache, early initialization, API failures and render width |
| Environment | Godot `3.4.stable.official.206ba70f4`; GUT `7.4.3` (`c11ba9daf49b2ec127d6113be89534dc9ee21873`) |
| Dependencies | Godot 3.4, Python standard library, Git for setup/provenance; no runtime mod dependencies |
| Location | `tests/`, versioned with the mod |
| Runner | GUT CLI plus Python completion, timeout, error and JUnit checks |
| Isolation | Original sources remain unchanged; broken probes use disposable copies |
| Acceptance | Every selected test executes, passes and asserts; no pending or engine errors |

## Prepare and run

From the workspace root:

```powershell
python Mods/GuidesLines/tests/run.py --setup
python Mods/GuidesLines/tests/run.py
python Mods/GuidesLines/tests/run.py --test test_square_vertices
python Mods/GuidesLines/tests/run.py --test runtime
python Mods/GuidesLines/tests/check_runner.py
python Mods/GuidesLines/tests/check_runtime.py
```

Setup checks the pinned upstream revision and copies unchanged `addons/gut`,
including its MIT license, into the ignored `tests/addons/`. It uses
`ExternalMods/Gut` or clones that release if absent. It rejects a different
revision or modified addon and never updates an existing checkout or runtime
dependency pins.

The default engine is `Godot/Godot_v3.4-stable_win64.exe` in the workspace.
Use `--godot PATH` for another compatible executable and `--timeout SECONDS`
(default 30) for the process limit.

Each main invocation creates `results/<run-id>/run.json`, `junit.xml` and
`output.log`. Provenance includes timestamps, target revision/working-tree state,
runtime source hashes, runtime policy hash, actual engine version and expected
test count. Timeout, engine/script errors, missing/malformed XML, incomplete
cases, skipped tests and assertion-free tests fail acceptance. Results cannot
reuse an earlier successful report.

## Runtime inventory and isolated contracts

`runtime_files.json` defines source roots and constructor policy.
`unit/test_runtime_files.gd` discovers all `.gd` files directly at the mod root
and recursively under `scripts/`, loads them with Godot and checks
`can_instance()`. Every discovered file needs exactly one reviewed `construct`
entry or `load_only` reason. Unclassified new sources fail.

The inventory contains 14 scripts; 13 constructors execute off-tree. Owned Nodes
are freed. `GuidesLinesTool` remains load-only because its constructor creates
mutually referencing collaborators and needs a dedicated isolated cleanup test.
Constructing the outer history script does not exercise nested record classes.

For entries listed in `injected_globals`, the suite prepends `var Global = {}`
and `var Script=null` in memory. The adapter supports entries without `extends`;
other insertion forms are rejected. Scenarios supply any required dependency
values explicitly. Original files remain unchanged.

The source-layout test requires ordinary modules to begin with `extends` and
configured entries to omit it. It also checks the entry's `script_class`, manifest
JSON/required fields and listed icon files. Resource existence does not prove
rendering or asset decoding.

`test_marker_lifecycle.gd` exercises creation, Save, JSON encoding/decoding, Load
and opacity updates. It verifies Line/Shape/Path round trips and preservation of
modified Shape primitives until `clear_clip()`.

`test_runtime_contracts.gd` checks API placement failures before tool initialization,
adaptive width and original `start()` without `_Lib`, followed by `update()` with
unavailable dependencies. All seven dynamic classes load without premature tool
construction. The assertions cover precisely these controlled inputs.

## Verify the verification tools

`check_runner.py` exercises eight real GUT scenarios: success, failed assertion,
pending, assertion-free test, parse error, runtime error after a passing assertion,
empty suite and timeout.

`check_runtime.py` exercises ten real Godot scenarios on disposable copies:
success, syntax error, constructor runtime error, unclassified source, missing
root, empty policy, escaping root, wrong entry-source classification, invalid
manifest and missing resource. Every broken variant must be rejected.
Reports are retained under `results/`; runtime probe summaries use
`results/runtime-check-<id>/summary.json`. Deliberately failing reports are
self-check diagnostics, separate from the main suite result.

## VS Code and adding tests

Run setup once. `GuidesLines: verify GUT tests` runs the acceptance wrapper;
`GuidesLines: check runtime smoke failure modes` runs the smoke self-check.
The default test task includes smoke and behavior tests together.

`gut-extension` provides optional direct runs. `GUT: Run All` and
`GUT: Run Current Script` use the configured root. Their generated terminal
commands were checked with a simulated VS Code API and actual Godot execution;
real extension activation and debugger use were not exercised. Cursor commands
need language-server symbols; otherwise use `--test` from the CLI.

Direct GUT runs use `results/junit.xml` and the strict post-run hook, but GUT 7
can still report success after a runtime error following a passing assertion.
Use the Python wrapper for acceptance. Update local executable/resource paths
when moving the workspace.

Add flat `unit/test_*.gd` scripts extending `res://addons/gut/test.gd`, with
nonparameterized `func test_*()` methods. Derive original-code paths from the
test root; Godot clamps `res://..` preload paths. Use independently known
expectations, numeric tolerances and deep dictionary assertions. Parameterized
tests or inner classes require updated expected-case discovery in `run.py`.

The suite contains 22 tests / 444 assertions. Keep generated dependencies and
reports out of source control and test files out of runtime distribution archives.

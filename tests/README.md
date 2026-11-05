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
an existing `ExternalMods/Gut` checkout and fails explicitly if it is absent. It rejects a different
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

The inventory contains 15 scripts; 14 constructors execute off-tree. Owned Nodes
are freed. `GuidesLinesTool` remains load-only in this generic inventory because
its constructor creates mutually referencing collaborators. `test_tool_history.gd`
constructs the real tool and explicitly breaks those cycles after each test.
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
and opacity updates. It verifies Line/Shape/Path round trips, JSON preservation of
modified and explicitly empty Shape outlines, rejection of malformed saved
primitives without replacing existing state, and reset through `clear_clip()`.

`test_persistence.gd` exercises the real `GuidesLinesPersistence` class with the
real tool/models/history and an explicit host signal source. It checks full JSON
round trips for all marker types, fills and templates; exact version rejection
and complete replacement on the next save; atomic malformed-data rejection;
integer ID lookup/counter repair; independent save snapshots; native
`OnSaveBegin(path, is_backup)` handling; late WorldUI, map changes and connection
cleanup; and delete undo/redo plus template placement after loading. This verifies
the signal contract in isolation, not Dungeondraft's save UI or disk I/O.

`test_tool_history.gd` exercises original tool/history/API code for delete undo,
delete-all undo, rotated template redo, conforming redo after UI settings change,
Cut/Merge metadata restoration, merge deletion signals, distant Shape/Path edges,
the wrapping result contract, hex side sizing callbacks and tool-state fields.
Host collaborators are dictionaries; these tests do not validate Dungeondraft's
HistoryApi, map persistence, rendering or the installed Snappy mod.

`test_aabb.gd` compares clipping and merge outputs against the same source with
broad-phase additions removed in memory. Cases include separated, tangent,
contained, degenerate, large-coordinate and near-tolerance shapes. Diagnostic
64-sided clipping timings compare both implementations without timing-based
acceptance thresholds. Tool tests also cover UI-independent parameter actions,
per-type memory, missing-field defaults and actual panel signals.

`test_audit_regressions.gd` checks original entry/tool/UI/API code with real Godot
controls for setting synchronization, event counts, panel replacement and shared
icon textures. Canvas gating uses actual Control transforms with a controlled
pointer at four scales; input tests cover UI wheel/click rejection and drag
release outside the canvas. These tests do not exercise OS pointer routing in
Dungeondraft. It also
covers shared clipping, Shape/Template mode equivalence, polygon-cache transitions,
snapshot wrappers, epsilon boundaries, nearest vertices, coordinate-axis generation
and redraw invalidation. `helpers/draw_probe.gd` records original render commands
and supplies controlled square snapping. A separate two-Viewport test compares
the actual rendered pixels of old and optimized text outlines. These renderer
checks require a working Godot graphics backend; they do not exercise the embedded
Dungeondraft renderer or its installed mods.

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

The suite contains 80 tests / 1663 assertions. The latest regressions cover map persistence, partial
merge failures, restored ID reservation, UI picking at distant outlines before API
registration, preview lifetime across repeated draws, actual-geometry query bounds
and their invalidation, clipped Line sampling, canonical placement flags and the
shared SpinBox rows. Two obsolete circle/ray helper tests
were retired with their unused implementations; active ray clipping is covered
by the map/preview checks. Keep generated dependencies and
reports out of source control and test files out of runtime distribution archives.

Dungeondraft runtime testing was confirmed successful by the user on 2026-11-04.

See [AUDIT.md](AUDIT.md) for the reviewed findings and remaining work.

Refactoring coverage checks explicit placement policy during UI callbacks and replay,
shape-only state snapshot independence, and reuse of preview storage. Existing tests
still exercise preview expiry and repeated draw passes, exact boolean geometry,
map guards, native history ordering and saved template placement.

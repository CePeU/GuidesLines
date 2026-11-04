# Changelog

All notable changes to the Guides Lines mod will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.4.1] — 2026-11-04

### Changed

- Technical maintenance: simplified internal code, fixed geometry and marker lifecycle issues, improved rendering and spatial queries, and expanded regression tests.

### Added

- Markers, fill regions and marker templates are now saved and restored with the map. The save format is versioned; incompatible data is skipped and replaced with the current format on the next save.

---

## [2.4.0] — 2026-05-03

### Added — Template Mode

A new **Template** tool type is available in the type selector (alongside Line, Shape, Path, Fill).

**Capturing templates:**
- Click **Add Template** to enter capture mode ("Click a marker…"), then click any existing marker on the map to snapshot its configuration as a named template.
- The template stores the full marker state, including modified Shape geometry (Merge / Conforming / Difference / Cut primitives) and Path point layouts.

**Placing templates:**
- Select a template from the list and click anywhere on the map to place a copy.
- **Mouse wheel** rotates the template in 1° steps (Line) / 5° steps (Shape, Path); **RMB** rotates by 45°. The rotation offset resets each time a different template is selected.
- A semi-transparent preview follows the cursor, reflecting the current rotation.

**Shape Overlap Modes:**
- When the selected template is a Shape, an **Overlap Mode** panel appears (identical to the Shape tool row: Normal, Merge, Conforming, Wrapping, Difference, Cut).
- All six modes apply correctly during template placement, including proper geometry propagation for primitive-based (modified) shapes.

Templates are stored in-session and are not persisted across map reloads.

---

## [2.3.5] — 2026-05-03

### Added — Move Mode

A new **Move Markers Mode** toggle is available in the tool panel (below Delete Mode).

**Behaviour:**
- While Move Mode is active, the standard placement preview is hidden.
- Clicking on an existing marker's centre and holding LMB picks it up; a semi-transparent preview follows the cursor.
- Releasing LMB drops the marker at the new position (grid snapping is respected).
- All marker types are supported: **Line**, **Shape**, and **Path**. Shape primitives and Path points are translated in world-space so the full visual geometry moves with the marker.
- The move is fully **undoable/redoable** via the history system.
- Move Mode and Delete Mode are **mutually exclusive** — enabling one disables the other.
- Hotkey: **Ctrl+M** (configurable in mod settings).

---

## [2.3.4] — 2026-05-03

### Added — Cut overlap mode for Shape markers

A new **Cut** mode is available in the Shape **Overlap Mode** row (alongside Normal, Merge, Conforming, Wrapping, Difference).

**Behaviour:** When Cut mode is active and the user places a Shape, no new marker is created. Instead, every existing Shape marker whose outline **intersects** the placed shape is clipped:
- Segments that fall inside the cut area are removed.
- The remaining segments are split into disconnected chains; each chain becomes a **Path** marker (the original Shape marker is converted in-place for the first chain, extra chains spawn new markers).
- A Shape that lies **fully inside** the cut area is deleted entirely.
- A Shape that fully **contains** the cut area without any edge intersection is left untouched.

The operation is fully **undoable/redoable** via the history system.

---

## [2.3.3] — 2026-05-02

### Added — "Side" size mode for non-circle shapes

Shape markers now support a second size input — **Side** — as an alternative to Radius. When enabled, the shape is sized so that its **edge length** equals the given value in grid cells, rather than its circumradius.

Practical alignment guarantees:
- **Square / any 4-sided shape** with Side = 1 → edges exactly match one square grid cell.
- **Hexagon** with Side = 1 → edges exactly match one hexagonal grid cell (both Corner and Edge radial modes are handled automatically).

**UI changes** (`GuidesLinesToolUI`):
- A new **"Size by: Radius / Side"** `OptionButton` appears in the Shape settings panel for all non-circle presets.
- While in Side mode the **Radius** row is hidden and replaced by a **Side** spinbox. Switching back to Radius mode restores the radius row.
- The Circle preset always uses Radius mode (the toggle is hidden for it).
- Mouse-wheel scroll adjusts the Side value (and updates Radius accordingly) when Side mode is active.

**Hex Edge-mode correction** (`GuidesLinesTool`):
- When Custom Snap mod is active with a hex geometry in **Edge** (apothem) mode, the circumradius is automatically scaled by `2/√3 ≈ 1.1547` so the shape still aligns with the hex grid cell.
- The correction is re-evaluated every frame in `Update()`, so switching Corner↔Edge in Custom Snap takes effect immediately without re-entering the Side value.

---

## [2.3.2] — 2026-05-02

### Fixed — Octagon and Custom shape presets defaulted to wrong angle

Selecting the **Octagon** preset set the angle to `22.5°` instead of `0°`, which appeared as `23` in the SpinBox (step = 1). Selecting **Custom** inherited whatever angle was previously active instead of resetting to `0°`.

**Fix** (`GuidesLinesToolUI._on_shape_subtype_changed`): Octagon default angle changed from `22.5` to `0.0`; Custom preset now explicitly resets the angle to `0.0`.

### Changed — "Delete All Markers" button disabled until Delete Mode is active

The **Delete All Markers** button is now disabled by default and becomes enabled only when **Delete Markers Mode** is turned on. This prevents accidental deletion of all markers with a misclick.

### Added — Configurable hotkey to toggle Delete Mode

A new shortcut **"Toggle Delete Mode"** (default: `Ctrl+D`) is now available in **Edit → Preferences → Shortcuts → Guides Lines**. Pressing it toggles Delete Mode on/off without touching the mouse. The existing tool-activation shortcut default was also updated from `9` to `Ctrl+G`.

---

## [2.3.1] — 2026-05-02

### Fixed — Shape markers 4× too large in Conforming / Wrapping / Difference modes when Custom Snap is active

When Custom Snap mod was enabled and any non-Normal shape interaction mode (Conforming, Wrapping, Difference, Merge) was used, newly placed Shape markers were rendered at the wrong size — up to 4× larger than in Normal mode.

**Fix — single source of truth for `cell_size`:**
- `GuidesLinesTool._get_grid_cell_size()` — replaced the `.has()` guard with a direct property access (`cached_snappy_mod.custom_snap_enabled`), consistent with how the overlay always read it.
- `MarkerOverlay._get_grid_cell_size()` — removed the duplicated implementation; now delegates to `tool._get_grid_cell_size()` so all code paths use identical logic.

---

## [2.3.0] — 2026-05-01

### Changed
- **Release packaging** — the ZIP archive now contains a `GuidesLines/` subfolder
  instead of placing files at the archive root.  
  Files `.gitignore` and `.gitmodules` are excluded from the release.

---

## [2.2.10] - 2026-03-01

### Fixed — Merge mode produced no result when two squares intersected along shared boundary edges

When placing a square marker (Shape, 4 sides, 45° rotation) such that it intersected an existing square **exactly along two full boundary edges** (i.e. the top and bottom sides of both squares were collinear), the Merge operation silently failed and left the map unchanged.

**Root cause:** Godot 3's `Geometry.is_point_in_polygon()` returns `true` for points that lie exactly on a polygon's boundary edge. When two polygon edges are collinear, `clip_polygon_against_shapes` split both polygons along the shared boundary, but evaluated the midpoint of the connector sub-segment as "inside the other shape" and discarded it. Both polygons lost the connecting bridge segment, leaving 6 open-ended segments instead of a closed ring. `chain_segments_to_polygon` could only chain 2 of them, the degenerate-polygon guard (`< 3 vertices`) fired, and the operation was aborted with no changes.

**Fix** (`GeometryUtils.merge_polygons_outline`): after collecting the outer segments from both polygons, a two-pass repair is applied:

- **Pass 1 — de-duplicate reverse-direction segments:** handles the complementary boundary case where `is_point_in_polygon()` returns `false` for boundary midpoints, causing the same shared-boundary segment to survive in both `segs_a` and `segs_b` in opposite directions. The reverse duplicate is removed from `segs_b`.
- **Pass 2 — gap bridging:** builds a vertex-valence map over all collected segments. In a valid closed-polygon edge-set every vertex has even valence; vertices with odd valence are open ends left by the discarded connector(s). Open ends are greedily paired by nearest distance and synthetic bridge segments are added to close the boundary.

#### Files changed
- **`scripts/utils/GeometryUtils.gd`** — `merge_polygons_outline()` extended with Pass 1 (de-dup) and Pass 2 (gap-bridging) after the `clip_polygon_against_shapes` calls.

---

### Fixed — Left-click input no longer fires through open Dungeondraft windows or UI bars

Clicks were being processed by `MarkerOverlay` even when a Dungeondraft popup/window was visible on screen (e.g. the Map Settings dialog), occasionally placing or deleting markers accidentally.

**Root cause:** `_input` fires before `Control._gui_input`, so `is_input_handled()` is not yet set when `MarkerOverlay` receives the event. There was no explicit check for open windows.

**Fix** (`scripts/overlays/MarkerOverlay.gd`):
- Before processing any left click, the handler now iterates `editor.Windows.values()` and returns early if any window is `visible`.
- The viewport boundary guard was extended to also reject clicks within **100 px of the top and bottom edges** of the viewport (in addition to the existing 450 px left-panel guard), preventing accidental interaction with the top and bottom UI bars.

#### Files changed
- **`scripts/overlays/MarkerOverlay.gd`** — added visible-window check and top/bottom viewport margin guards to the left-click handler.

---

### Fixed — Merging two tangentially touching circles produced only one circle with a shifted center

When two identical circular Shape markers (e.g. 50 sides, radius 1 cell) were placed so that only their outermost points touched (tangent contact, zero-area intersection), the Merge operation:
1. Wrote only the outline of the **second** (newly placed) circle to the primary marker.
2. Moved the primary marker's center to the **midpoint** between both circles, despite the shape being a single circle.

**Root cause — `chain_segments_to_polygon`:** The tangent point T is a shared vertex of both circle polygons. After `merge_polygons_outline` collected all outer segments, the chaining loop started on a segment of circle B, traversed all 50 edges of B, and returned to B[0]. At that point the tail no longer matched any unused edge of circle A (none of A's edges share B[0]), so the loop exited with all A-edges unconsumed. The result was only circle B's outline.

**Root cause — centroid skew:** `center_sum += marker.position` was executed unconditionally before checking whether the geometry step (`chain_segments_to_polygon`) actually succeeded, so the centroid was shifted even when only B's shape was written.

**Fix 1** (`GeometryUtils.chain_segments_to_polygon`): After the primary chaining loop, a **figure-8 / tangent-touch continuation** pass checks for unused edges. If any unused edge connects to a vertex already present in `poly` (the tangent point T), the function traces the remaining sub-loop from T back to T and splices it into `poly` as an in-and-out detour: `[…, T, A₁, …, Aₙ, T, …]`. This produces a single continuous figure-8 outline that correctly draws both circles.

**Fix 2** (`GuidesLinesTool._do_apply_merge`): `center_sum += marker.position` and `center_count += 1` are now accumulated **only after** `chain_segments_to_polygon` returns a non-empty result, ensuring the centroid is not shifted when the geometry step fails or produces no usable polygon.

#### Files changed
- **`scripts/utils/GeometryUtils.gd`** — `chain_segments_to_polygon()` extended with figure-8 continuation block.
- **`scripts/tool/GuidesLinesTool.gd`** — `_do_apply_merge()` centroid accumulation moved after successful geometry step.

---

## [2.2.9] - 2026-02-26

### Changed — Shape interaction modes UI redesigned with icon-only buttons

The Shape interaction mode controls (Merge, Conforming, Wrapping, Difference) have been replaced from checkboxes to toggle buttons with icons arranged in a horizontal row. A new **Normal Mode** button has been added as the default state when no interaction mode is active.

- All 5 mode buttons (Normal, Merge, Conforming, Wrapping, Difference) are now displayed in a single row
- Buttons use icon-only display with tooltips for mode descriptions
- Icons are scaled to 50% (32×32) for better visual fit in the panel
- Only one mode can be active at a time; clicking a button automatically deactivates others
- New icon added: `icons/normal64.png`

### Fixed — `place_shape_merge` no longer produces degenerate polygons with identical shapes

`place_shape_merge` previously created corrupted/degenerate polygons when attempting to merge a virtual shape with identical parameters (position, radius, angle, sides) onto an existing marker.

- Added early detection: when the virtual shape is nearly identical to a single existing marker (same vertex count, position within 1px), the merge is skipped and the existing marker remains unchanged.
- Added validation: if the merge result has fewer than 3 vertices (degenerate polygon), the operation is aborted and the original marker is preserved.
- Returns `{"affected_markers": [], "absorbed_marker_ids": []}` when no actual merge is performed.

#### Files changed
- **`scripts/tool/GuidesLinesToolUI.gd`** — `_create_shape_settings_ui()` redesigned with icon buttons; `_load_icon()` now supports scaling parameter.
- **`scripts/tool/GuidesLinesTool.gd`** — `_do_apply_merge()` validates shape identity before merging; validates vertex count after merging.
- **`scripts/api/guides_lines_api.gd`** — `place_shape_merge()` docstring updated to clarify behavior with identical shapes.

---

## [2.2.8] - 2026-02-26

### Fixed — `place_shape_conforming` and `place_shape_wrapping` now return full polygon data

Both methods previously returned incomplete data for the new marker and the markers affected during placement.

- **`place_shape_conforming`** — response now includes `marker_polygon: Array[Vector2]`, the final outline of the newly placed marker.
- **`place_shape_wrapping`** — `dented_by: Array[int]` (IDs only) replaced by `affected_markers: Array[{marker_id, new_polygon}]`, matching the structure used by all other shape interaction methods. The legacy `dented_by` field is removed.

Both methods now return a consistent structure:
```gdscript
{
  "marker_id":        int,
  "marker_polygon":   Array[Vector2],
  "affected_markers": [ { "marker_id": int, "new_polygon": Array[Vector2] }, ... ]
}
```

### Changed — Merge mode falls back to normal placement when no shapes overlap

Previously, clicking in Merge mode with no overlapping Shape markers did nothing. Now the marker is placed normally (as if no interaction mode were active), matching the intuitive expectation that a click always produces a marker.

### Added — Icons for Shape interaction mode checkboxes

Four 64×64 PNG icons are now displayed on the Merge, Conforming, Wrapping, and Difference `CheckButton` controls in the Shape settings panel.

- `icons/merge64.png`
- `icons/conforming64.png`
- `icons/wrapping64.png`
- `icons/difference64.png`

#### Files changed
- **`scripts/tool/GuidesLinesTool.gd`** — `api_place_shape_conforming` reads the placed marker's descriptor and adds `marker_polygon` to the return dict; `api_place_shape_wrapping` snapshots overlapping marker polygons before placement and returns them as `affected_markers`; Merge branch in `place_marker()` falls through to normal placement when no targets are found.
- **`scripts/api/guides_lines_api.gd`** — error-return dicts, docstrings, and logger messages updated for both methods.
- **`scripts/tool/GuidesLinesToolUI.gd`** — `_create_shape_settings_ui()` loads and applies icons to the four mode checkboxes via `add_icon_override`; added `_load_icon(filename)` helper.

---

## [2.2.7] - 2026-02-25

### Fixed — `place_shape_merge` now reports absorbed marker IDs

`api_place_shape_merge` (and the public `GuidesLinesApi.place_shape_merge`) previously silently discarded the IDs of markers that were deleted during a multi-marker merge. External mods had no way to know which IDs were removed.

The response dictionary now includes `absorbed_marker_ids: Array[int]`:

```gdscript
{
  "affected_markers":    [ { "marker_id": 1, "new_polygon": [...], ... } ],
  "absorbed_marker_ids": [ 2, 3 ]   # IDs of markers deleted during merge
}
```

`absorbed_marker_ids` is empty when only one Shape marker overlapped (no deletion occurred). The `{}` failure case and the no-overlap early-return now also consistently carry `absorbed_marker_ids: []`.

---

## [2.2.6] - 2026-02-25

### Fixed — Merge mode now produces a single unified marker

Previously, when a Merge placement overlapped multiple existing Shape markers, each marker was merged independently with the virtual shape — resulting in several separately updated markers instead of one combined outline.

**New behaviour:** all overlapping Shape markers are folded into a single union polygon in one pass. Only the first overlapping marker is kept (the *primary*); all others are removed. The primary receives the full union outline and a position averaged across all participants. Undo correctly restores every absorbed marker.

- `_do_apply_merge` rebuilt to iterate all overlapping markers and chain their polygons via `GeometryUtils.chain_segments_to_polygon`, then write the result to the primary marker only.
- Absorbed marker IDs are now passed to `MergeShapeRecord` and stored as `absorbed_ids`.
- `MergeShapeRecord.undo()` re-creates every absorbed marker from its snapshot (`primitives`, `position`, `color`).
- `_snapshot_potential_merge_targets` now includes `color` in each snapshot entry.
- `api_place_shape_merge` updated accordingly; `affected_markers` in the response now contains only the surviving primary marker.

---

## [2.2.5] - 2026-02-25

### Added — Shape interaction mode API methods

Four new methods in `GuidesLinesApi` expose all four Shape interaction modes programmatically, each with full undo/redo support.

#### `place_shape_merge(position, radius, angle, sides) → Dictionary`
Merges a virtual shape into every overlapping existing Shape marker (union of outlines). No new marker is created. Returns `{"affected_markers": [{marker_id, new_polygon, old_position, new_position}, …]}`. Returns `{}` on failure, `{"affected_markers": []}` if nothing overlapped.

#### `place_shape_conforming(position, radius, angle, sides, color) → Dictionary`
Places a new Shape marker normally while denting every overlapping existing Shape to accommodate it. Returns `{"marker_id": int, "affected_markers": [{marker_id, new_polygon}, …]}`. `marker_id` is `-1` on failure.

#### `place_shape_wrapping(position, radius, angle, sides, color) → Dictionary`
Places a new Shape marker whose own outline is dented by all overlapping existing shapes. Existing markers are left unchanged. Returns `{"marker_id": int, "dented_by": [int, …], "marker_polygon": [Vector2, …]}`. `marker_id` is `-1` on failure.

#### `apply_shape_difference(position, radius, angle, sides) → Dictionary`
Punches a hole into every overlapping existing Shape marker using a virtual cutter shape. No new marker is created. Returns `{"affected_markers": [{marker_id, new_polygon}, …]}`. Returns `{}` on failure, `{"affected_markers": []}` if nothing overlapped.

---

## [2.2.4] - 2026-02-24

### Added — Shape preview API and tool-state query

Two new methods in `GuidesLinesApi` allow external mods to render a live shape preview on the map and inspect the full current tool configuration.

#### `set_shape_preview(coords, radius, angle, sides, color)`
Queues a one-frame Shape preview rendered directly on the map overlay at `coords`.

- The preview is drawn by `MarkerOverlay` on the next paint pass and cleared automatically. To keep it alive call this method every frame (e.g. from `_process`).
- Parameters match `place_shape_marker`: `coords: Vector2`, `radius: float` (grid cells, default `1.0`), `angle: float` (degrees, default `0.0`), `sides: int` (default `6`), `color: Color` (default semi-transparent active color).
- Uses the same `GeometryUtils.calculate_shape_vertices` + `GuidesLinesRender.draw_polygon_outline` pipeline as the built-in cursor preview, so the result is visually identical to the normal Shape hover.

#### `clear_shape_preview()`
Explicitly clears any pending API preview immediately, triggering an overlay redraw. Useful when the external mod hides its UI or the cursor leaves the map.

#### `get_tool_state() → Dictionary`
Returns a snapshot of the full current tool state. All fields:

| Key | Type | Description |
|---|---|---|
| `ready` | `bool` | `false` if the tool is not yet loaded (map not open) |
| `active_marker_type` | `String` | `"Line"` \| `"Shape"` \| `"Path"` \| `"Fill"` |
| `active_angle` | `float` | Line angle in degrees |
| `active_mirror` | `bool` | Line mirror mode |
| `active_shape_radius` | `float` | Shape circumradius in grid cells |
| `active_shape_angle` | `float` | Shape rotation in degrees |
| `active_shape_sides` | `int` | Shape polygon sides |
| `active_path_end_arrow` | `bool` | Path arrowhead enabled |
| `active_arrow_head_length` | `float` | Arrowhead length in pixels |
| `active_arrow_head_angle` | `float` | Arrowhead opening angle in degrees |
| `active_color` | `Color` | Current active marker color |
| `show_coordinates` | `bool` | Grid-coordinate labels on new Line markers |
| `delete_mode` | `bool` | Delete-on-click mode active |
| `merge_shapes` | `bool` | Merge mode active |
| `conforming_mode` | `bool` | Conforming mode active |
| `wrapping_mode` | `bool` | Wrapping mode active |
| `difference_mode` | `bool` | Difference mode active |
| `marker_count` | `int` | Total placed markers |
| `fill_count` | `int` | Total placed fills |
| `path_placement_active` | `bool` | Multi-point path placement in progress |
| `path_temp_point_count` | `int` | Points collected so far in active path |

#### Files changed
- **`scripts/tool/GuidesLinesTool.gd`** — added `var _api_preview = {}` field used as the one-frame preview slot.
- **`scripts/overlays/MarkerOverlay.gd`** — `_process` triggers redraw when `_api_preview` is non-empty; `_draw()` calls new `_draw_api_shape_preview()` and auto-clears the slot; added `_draw_api_shape_preview()`.
- **`scripts/api/guides_lines_api.gd`** — added `# TOOL STATE & PREVIEW` section with `set_shape_preview()`, `clear_shape_preview()`, and `get_tool_state()`.

---

## [2.2.3] - 2026-02-24

### Changed — Draw pipeline performance optimisations (no behaviour change)

A series of refactors across all overlay classes removes redundant per-frame calculations and heap allocations from the hot `_draw()` path. No visual or API behaviour has changed.

#### MarkerOverlay.gd
- **Color constants** — five static `Color(...)` literals used inside preview draw methods are now `const` class fields (`_PREVIEW_MARKER_COLOR`, `_PREVIEW_ARC_COLOR`, `_PATH_PREVIEW_LINE_COLOR`, `_PATH_PREVIEW_FIRST_COLOR`, `_PATH_PREVIEW_CURSOR_COLOR`), eliminating per-frame object allocations.
- **`coord_marker_size` / `coord_text_offset`** — previously recomputed via `get_adaptive_width` for every marker that has `show_coordinates` enabled; now computed once in `_draw()` and passed as parameters down to `_draw_marker_coordinates_cached`.
- **`custom_snap`** — previously fetched per-marker inside `_draw_custom_marker`; now fetched once in `_draw()` and passed as a parameter.
- **`active_arrow_length_px`** — previously computed via `get_adaptive_width` every preview frame; now computed once in `_draw()` and passed into `_draw_path_preview`.
- **Marker / line sizes** — `marker_size_draw`, `line_width_draw`, `preview_line_width`, `preview_marker_size` already computed once in `_draw()` (from previous session); signatures updated throughout to carry all sizes as parameters.

#### PermanentOverlay.gd
- **Map center cache** (`_update_map_cache`) — `WorldRect` is accessed and `map_cx / map_cy` recomputed only when `WorldRect` actually changes (same pattern as `CrossOverlay`). Cache is updated in `_process()` and invalidates the coord cache automatically.
- **`GuidesLinesRender.get_adaptive_width`** — `center_marker_size`, `marker_size`, and `text_offset` now use `get_adaptive_width` consistently (was raw `* cam_zoom.x`), unifying the approach with `MarkerOverlay`.
- **Coordinate point cache** (`_perm_coord_cache_v / _perm_coord_cache_h`) — the expensive `while` loops (vanilla grid iteration and custom-snap snapping) previously ran every frame. Now extracted into `_rebuild_perm_coord_cache()` and executed only when viewport bounds, map center, or snap settings change. `_draw_grid_coordinates` simply iterates the pre-built arrays; only zoom-dependent dot/text sizes are computed at draw time.
- `_draw_vanilla_coordinates` and `_draw_custom_snap_coordinates` removed; replaced by the single unified `_rebuild_perm_coord_cache()`.
- Class-level `_coord_checked_v / _coord_checked_h` dicts reused with `.clear()` instead of allocating new `{}` each rebuild.

---

## [2.2.2] - 2026-02-23

### Added — Fill polygon query methods in GuidesLinesApi

Two new methods allow other mods to programmatically retrieve fill polygons using the same computation logic as the Fill tool, without placing any markers.

- **`compute_fill_polygon(coords: Vector2) → Dictionary|null`**
  Computes the fill polygon that would be produced if the user clicked at `coords` in Fill mode.
  - If exactly one Shape marker contains `coords` → **exclusive fill**: primary shape minus every overlapping shape that is not an outer container (holes are correctly bridged in).
  - If multiple Shape markers contain `coords` → **intersection fill**: the precise region shared by all hit shapes (A ∩ B ∩ C …).
  - Returns `{ "polygon": Array[Vector2], "marker_ids": Array[int], "fill_type": String }` on success, or `null` if `coords` is not inside any Shape marker.

- **`get_shape_polygon(marker_id: int) → Dictionary|null`**
  Returns the current outline polygon of a specific Shape marker, reflecting any Merge / Difference / Clip / Conforming modifications that have been applied.
  - Returns `{ "polygon": Array[Vector2], "marker_id": int, "marker_type": String }` on success, or `null` if the marker is not found or is not a Shape.

Both methods fully delegate to internal Fill-tool helpers (`_fill_handler._collect_hit_markers`, `_fill_handler._compute_fill_polygon`, `tool._get_shape_descriptor`), so their results are always consistent with what the Fill tool produces.

#### Files changed
- **`scripts/api/guides_lines_api.gd`** — added `# FILL POLYGON QUERIES` section with `compute_fill_polygon()` and `get_shape_polygon()`.

---

## [2.2.1] - 2026-02-23

### Changed — Fill Mode moved into Marker Type dropdown

**Fill Mode** is no longer a standalone `CheckButton` in the tool panel. It is now a first-class marker type in the **"Marker Type:"** `OptionButton` dropdown, sitting alongside Line, Shape, and Path.

- Selecting **Fill** in the dropdown activates fill placement mode and shows a dedicated settings panel with a hint label and the **Delete All Fills** button.
- Switching to Delete Mode while Fill is active automatically resets the dropdown to Line (the two modes are mutually exclusive).
- All internal references to the old `fill_mode` boolean flag and `set_fill_mode()` have been removed; fill mode is now determined by `active_marker_type == MARKER_TYPE_FILL`.

#### Files changed
- **`GuidesLinesTool.gd`** — added `MARKER_TYPE_FILL = "Fill"` constant; removed `fill_mode` var and `set_fill_mode()`; updated `set_delete_mode()` to reset type to Line when Fill was active; updated `handle_fill_click()` guard to `active_marker_type != MARKER_TYPE_FILL`.
- **`GuidesLinesToolUI.gd`** — added `MARKER_TYPE_FILL` constant, `fill_settings_container` variable, `_create_fill_settings_ui()` function, and `sync_type_selector_to_active_type()` helper; added "Fill" item (index 3) to `type_selector`; updated `_switch_type_ui()` and `_on_marker_type_changed()` to handle Fill; removed standalone Fill Mode `CheckButton`, its spacer, and `_on_fill_mode_toggled()` callback; **Delete All Fills** button now lives inside the Fill settings panel.
- **`MarkerOverlay.gd`** — replaced all three `tool.fill_mode` references with `tool.active_marker_type == tool.MARKER_TYPE_FILL`.

---

## [2.2.0] - 2026-02-23

### Added — Marker visibility toggle and opacity control in tool panel

Two new display controls are now available directly in the **Guide Markers** tool panel under a new **"Map Display"** section (below the Color picker). They affect all placed markers in real time and are not in Preferences.

- **Show Markers** (`CheckButton`) — instantly hides or shows all placed markers on the map without deleting them. Preview markers shown during placement are unaffected.
- **Opacity (%)** (`SpinBox`, 0–100, step 5) — sets a global transparency level for all placed markers (lines, shapes, paths, arrowheads, and center dots). 100 = fully opaque, 0 = fully transparent.

Both settings are also exposed through `GuidesLinesApi` for inter-mod use.

#### Files changed
- **`GuidesLines.gd`** — added `markers_visible: bool` and `markers_opacity: float` state variables.
- **`GuidesLinesToolUI.gd`** — extended `_create_common_settings_ui()` with "Map Display" section; added callbacks `_on_markers_visible_toggled`, `_on_markers_opacity_changed`; added sync helpers `_update_markers_visible_checkbox`, `_update_markers_opacity_spinbox`.
- **`MarkerOverlay.gd`** — `_draw()` skips the marker loop when `markers_visible` is `false`; `_draw_custom_marker()` applies `markers_opacity` to every `draw_line`, `draw_circle`, `draw_arc`, and `draw_arrow` call.
- **`guides_lines_api.gd`** — added `set_markers_visible()`, `get_markers_visible()`, `set_markers_opacity()`, `get_markers_opacity()`; `get_settings()` extended with `markers_visible` and `markers_opacity` keys.

---

## [2.1.10] - 2026-02-23

### Changed — Inline hint labels replaced with tooltips

Removed the small grey hint `Label` nodes that appeared below certain controls in the Shape settings panel. Their text is now set as `hint_tooltip` directly on the corresponding control, so descriptions appear on hover instead of cluttering the panel layout.

#### Files changed
- **`GuidesLinesToolUI.gd`** — `radius_hbox.hint_tooltip` (circumradius note); `merge_check.hint_tooltip`, `conforming_check.hint_tooltip`, `wrapping_check.hint_tooltip`, `diff_check.hint_tooltip`; all four corresponding `Label` nodes and their `container.add_child` calls removed.

---

## [2.1.9] - 2026-02-23

### Added — Conforming Mode and Wrapping Mode (replace Cut mode)

The **Cut Into Existing Shapes** mode has been replaced by two new complementary modes.

- **Conforming Mode** — when placing shape B over existing shape A, A's outline is dented to match B's contour (Difference applied to A; B is placed normally).
- **Wrapping Mode** — inverse of Conforming: B's own outline is dented by every existing shape A it overlaps (Difference applied to B; A is left unchanged). Multiple overlapping shapes chain correctly.

Both modes are mutually exclusive with each other, Merge, and Difference. Undo/Redo fully supported via the existing `PlaceMarkerRecord` snapshot mechanism.

#### Files changed
- **`GuidesLinesTool.gd`** — `cut_existing_shapes` → `conforming_mode`; `_apply_cut_to_existing_shapes` → `_apply_conforming_to_existing_shapes` (now uses `_shapes_overlap` + appends diff boundary); added `wrapping_mode` and `_apply_wrapping_to_new_shape()`; `_snapshot_potential_clip_targets` updated to use `_shapes_overlap`.
- **`GuidesLinesToolUI.gd`** — checkboxes `ConformingModeCheckbox` and `WrappingModeCheckbox`; callbacks `_on_conforming_mode_toggled` / `_on_wrapping_mode_toggled`; mutual exclusion updated across all four mode toggles.
- **`GuidesLinesHistory.gd`** — `PlaceMarkerRecord.redo()` guard updated to `conforming_mode`.

---

## [2.1.8] - 2026-02-22

### Changed — Clip mode replaced by Merge mode

The **Clip Intersecting Shapes** mode has been replaced by **Merge Intersecting Shapes**.

#### Behaviour

- **Old (Clip):** placing shape B clipped both A and B at their intersection — two separate markers remained.
- **New (Merge):** placing shape B merges its outline into every overlapping existing marker A. No new marker is created; A absorbs the union outline and its center moves to the midpoint between the two original centers. Subsequent merges (A+B)+C always operate on the actual current outline of A.

#### Implementation

- **`GeometryUtils.gd`** — added `merge_polygons_outline(pts_a, pts_b)`: returns segments of the outer union of two polygons (handles normal intersection, full containment in either direction, and no-overlap); added `chain_segments_to_polygon(segs)`: chains a flat list of `{type:"seg"}` segments into an ordered `Array[Vector2]` polygon for use in subsequent merge/overlap tests.
- **`GuidesLinesTool.gd`** — `auto_clip_shapes` → `merge_shapes`; removed `_apply_shape_clipping()`; added `_do_apply_merge(merge_desc, new_pos)` and `_snapshot_potential_merge_targets(merge_desc)`; `place_marker()` has an early-exit Merge branch — if no existing shape overlaps, nothing happens; `_get_shape_descriptor()` now derives the polygon exclusively from current primitives via `chain_segments_to_polygon` (original shape parameters are only used once, on first `get_draw_data()` for a fresh marker).
- **`GuidesLinesHistory.gd`** — added `MergeShapeRecord`: snapshots primitives + position of every affected marker before the merge; `undo()` restores them, `redo()` replays `_do_apply_merge`.
- **`GuidesLinesToolUI.gd`** — checkbox renamed to `"Merge Intersecting Shapes"` / node name `MergeIntersectingShapesCheckbox`; hint updated; callback renamed to `_on_merge_shapes_toggled`; mutual-exclusion logic updated for Cut and Difference.

---

## [2.1.7] - 2026-02-22

### Refactoring — Code cleanup and bug fixes

- **`GuidesLinesToolUI.gd`** — Fixed bug where path placement was not cancelled when switching away from the Path type; arrow head length/angle callbacks now immediately sync `type_settings["Path"]`; removed excessive per-frame debug logging in wheel/rotate methods; removed duplicate Guide Overlays panel block (handled by ModConfigApi).
- **`GuidesLinesTool.gd`** — Fixed encoding artifact (`В°` → `°`) in debug log strings; corrected stale comments (`set_show_coordinates`, `markers.erase`); removed misleading `print()` fallback in `Enable()`; added missing section separator for `# UI STATE`.
- **`GuidesLines.gd`** — Fixed `print()` on `Global.Root` guard to use `LOGGER` pattern; removed redundant inline comment on `snappy_mod_checked`.

---

## [2.1.6] - 2026-02-22

### Refactoring — Arrow type merged into Path

The `Arrow` marker type has been removed. Its functionality is now part of the `Path` type via a new **"End with Arrow"** checkbox in the Path settings panel.

#### Changes

- **`GuideMarker.gd`** — added `path_end_arrow`, `arrow_head_length`, `arrow_head_angle` fields to Path markers; `Save`/`Load` updated accordingly; `Arrow` branches removed.
- **`GuidesLinesTool.gd`** — removed `MARKER_TYPE_ARROW` constant and all Arrow placement state (`arrow_placement_active`, `arrow_temp_points`, `arrow_preview_point`); added `active_path_end_arrow`; `type_settings["Path"]` now stores `end_arrow`/`head_length`/`head_angle`; Arrow delegate methods removed.
- **`GuidesLinesPlacement.gd`** — Arrow placement state machine removed; `finalize_path_marker()` now passes `path_end_arrow`, `arrow_head_length`, `arrow_head_angle` in marker data.
- **`GuidesLinesToolUI.gd`** — Arrow item removed from type selector; `_create_arrow_settings_ui()` removed; `_create_path_settings_ui()` extended with "End with Arrow" `CheckButton` and collapsible Head Length / Head Angle spinboxes.
- **`MarkerOverlay.gd`** — Arrow rendering and `_draw_arrow_preview()` removed; Path rendering draws arrowhead at last point when `path_end_arrow` is true; path preview shows semi-transparent arrow to cursor when option is active.
- **`guides_lines_api.gd`** — `place_arrow_marker()` now creates a Path marker with `path_end_arrow = true` (API remains compatible); `"Arrow"` match cases removed from geometry query functions.

---

## [2.1.5] - 2026-02-22

### Refactoring — GuidesLinesTool decomposition + Show Coordinates scoped to Line

#### Tool decomposition

`GuidesLinesTool.gd` (1 998 → 791 lines) split into three focused files:

- **`GuidesLinesHistory.gd`** — Undo/Redo record classes (`PlaceMarkerRecord`, `DeleteMarkerRecord`, `DeleteAllMarkersRecord`, `DifferenceRecord`).
- **`GuidesLinesToolUI.gd`** — Full UI panel creation, widget callbacks, type switching, mouse-wheel helpers.
- **`GuidesLinesPlacement.gd`** — Path and Arrow multi-point placement state machines.

`GuidesLinesTool` retains core marker state and delegates to the three helpers via thin wrapper methods.

#### Show Coordinates — Line markers only

- `CoordinatesCheckbox` moved from the common panel section into `_create_line_settings_ui()`; it now appears and disappears with the Line-type container.
- `place_marker()`: `"coordinates"` key is `show_coordinates` for Line, `false` for all other types.
- `_draw_marker_coordinates()` in `MarkerOverlay` simplified: early-exit for non-Line types; removed `_draw_coordinates_on_shape()` and `_draw_coordinates_on_path()`.

#### Removed save / load (to be redesigned)

`save_markers()`, `load_markers()`, `save_difference_ops()`, `load_difference_ops()` deleted from `GuidesLinesTool`.

#### Bug fix — Show Coordinates never applied on placement

`GuideMarker.set_property()` was missing a `"show_coordinates"` branch in its `match` block, so `show_coordinates` was always left `false` after `_do_place_marker`. Branch added.

#### GeometryUtils — `points_to_segs` moved from GuideMarker

`static func _points_to_segs` extracted from `GuideMarker` into `GeometryUtils.points_to_segs` (public, consistent with the seg-dict format used throughout clipping functions). Call site in `GuideMarker._recalculate_geometry` updated.

#### Files changed

- `scripts/tool/GuidesLinesHistory.gd` — **new**
- `scripts/tool/GuidesLinesToolUI.gd` — **new**
- `scripts/tool/GuidesLinesPlacement.gd` — **new**
- `scripts/tool/GuidesLinesTool.gd` — decomposed, save/load removed
- `scripts/guides/GuideMarker.gd` — `set_property` fix, `_points_to_segs` removed
- `scripts/utils/GeometryUtils.gd` — `points_to_segs` added
- `scripts/overlays/MarkerOverlay.gd` — coordinates rendering scoped to Line

---

## [2.1.4] - 2026-02-22

### Refactoring — Single primitives array, direct in-place modification

Simplified the Shape marker geometry model: all operations (Clip, Cut, Difference) now
modify a single `primitives` array in-place instead of maintaining separate fields.

#### Changes

- **Single `primitives` array** — replaced `render_primitives` + `render_fills` with one
  unified list. Difference boundary segments are merged directly into `primitives`.
- **Removed `clipped_by_ids`** — was a relic of the old rebuild-from-scratch approach;
  no longer needed now that operations modify primitives directly.
- **Removed `_recompute_marker_state`** — all ops call `set_primitives()` directly.
- **Circle as 64-gon** — Circle subtype unified with other Shape subtypes; computed via
  `calculate_shape_vertices` with 64 sides, no special-case code paths.
- **Single-pass renderer** — `MarkerOverlay` iterates `primitives` once per marker.
- **Undo snapshots** — `PlaceMarkerRecord` and `DifferenceRecord` snapshot and restore
  `{"primitives": [...]}` only.

#### Files changed

- `scripts/guides/GuideMarker.gd` — removed `render_fills`, `clipped_by_ids`;
  `set_primitives(segs)` takes a single array.
- `scripts/tool/GuidesLinesTool.gd` — all clip/cut/difference functions updated;
  snapshots store only `primitives`.
- `scripts/overlays/MarkerOverlay.gd` — single render loop over `primitives`.

---

## [2.1.3] - 2026-02-22

### Fixed — Difference Mode rendering split (outer outline vs. fill lines)

#### Root cause

`clip_circle_against_shapes` returns a full-circle arc (`from:0, to:TAU`) when a
difference shape is completely inside the target circle (no edge crossings).
Previously this full arc was concatenated with fill-boundary lines into one
`render_primitives` list, so the overlay would draw the full original circle
outline again in addition to any partial arcs from earlier crossing differences.

#### Architecture change — `render_primitives` and `render_fills`

`cached_draw_data` now carries two independent lists:

| Field | Semantics |
|---|---|
| `render_primitives` | Replacement outline for the marker edge (`[]` = use full-shape fallback). |
| `render_fills` | Diff-boundary lines drawn **on top** of the outline, always independently. |

`GuideMarker` API:

- `set_render_primitives(outer: Array, fills: Array = [])` — stores both.
- `get_render_primitives()` / `get_render_fills()` — accessors.
- `_recalculate_geometry` saves and restores **both** fields outside the
  `if cell_size:` block, preventing loss on grid-change or undo.

`MarkerOverlay._draw_custom_marker` now performs two explicit passes:
1. Draw outline — `render_primitives` if non-empty, full-shape fallback otherwise.
2. Always draw every item in `render_fills` on top regardless of outline state.

#### All-inside optimisation

When every affecting diff is fully inside the target (none cross its edge),
`_rebuild_all_diffs_for_marker` now sets `render_primitives = []`. This lets
the full-shape fallback handle the outline (no redundant full arc in the list),
while `render_fills` still carries the diff boundary lines correctly.

#### Legacy op migration

`applied_to` tracking was introduced mid-session.  Ops without this field (or
with an empty list) are now migrated on the fly: `_rebuild_all_diffs_for_marker`
runs a geometric `_shapes_overlap` check and appends `marker.id` to the op's
`applied_to` list so subsequent rebuilds are fast.

`load_difference_ops` was updated to detect legacy ops and rebuild **all**
markers in that case (instead of only those appearing in `applied_to`), giving
the migration code a chance to run.

#### Files changed

- `scripts/guides/GuideMarker.gd` — `render_fills` field, new two-arg
  `set_render_primitives`, `get_render_fills`, save/restore both fields.
- `scripts/tool/GuidesLinesTool.gd` — `DifferenceRecord` snapshot/undo,
  `_recompute_marker_clip`, `_take_difference_snapshot`,
  `_rebuild_all_diffs_for_marker` (migration + outer/fill split),
  `load_difference_ops` (legacy rebuild).
- `scripts/overlays/MarkerOverlay.gd` — two-pass outline + fills rendering.

---

## [2.1.2] - 2026-02-22

### Added — Difference Mode for Shape markers

A new optional mode **Difference** that permanently subtracts a newly placed
Shape marker from all Shape markers it overlaps.  The subtracted shape is then
removed from the canvas; only the "holes" it carved remain.

#### Behaviour

- Enabled via a **Difference** `CheckButton` in the Shape settings panel
  (mutually exclusive with *Clip Intersecting Shapes* and *Cut Into Existing
  Shapes*).
- Mutual exclusion: enabling Difference disables the other two checkboxes and
  vice-versa.
- Each subtraction is stored as an **operation record** (`difference_ops`) so
  it survives save/load and is properly undoable.
- Undo removes the op and restores the pre-subtraction render state of every
  affected marker (via snapshots stored in `DifferenceRecord`).

#### New geometry helpers (`GeometryUtils.gd`)

| Function | Description |
|---|---|
| `clip_polygon_inside_shape(poly_pts, shape)` | Keeps only sub-segments of a polygon whose midpoint is **inside** the given shape — used to draw the diff boundary inside the target. |
| `clip_circle_inside_shape(center, r, shape)` | Same for circle arcs. |
| `clip_primitives_against_shapes(prims, shapes)` | Filters a mixed `seg`/`arc` list to remove portions inside any of the given shapes (used to clean fills after stacked diffs). |

#### New fields and methods

**`GuideMarker.gd`**

- `render_primitives` inside `cached_draw_data` — replaces the former
  top-level `clip_data` array (unified storage in draw data).

**`GuidesLinesTool.gd`**

| Symbol | Description |
|---|---|
| `difference_mode: bool` | Feature flag. |
| `difference_ops: Array` | Persistent list of applied difference operations. |
| `DifferenceRecord` (inner class) | `HistoryRecord` subclass; stores diff descriptor, op dict, and per-marker snapshots for undo. |
| `_take_difference_snapshot()` | Captures pre-subtraction render state of all overlapping markers. |
| `_do_apply_difference(desc, op)` | Applies one diff op to all overlapping markers, records `applied_to`. |
| `_rebuild_all_diffs_for_marker(marker, cell_size)` | Recomputes outer + fills for a marker from all its ops (idempotent). |
| `save_difference_ops()` / `load_difference_ops(ops)` | Serialisation helpers called from `GuidesLines.gd`. |
| `_desc_from_op(op)` / `_op_from_desc(desc, …)` | Convert between op dicts and shape descriptors. |

**`GuidesLines.gd`**

- `save_level` serialises `difference_ops` into the level data dict.
- `load_level` deserialises and replays them via `load_difference_ops`.

#### Intersection vs. containment detection

`_shapes_overlap` = `_shapes_intersect` (edge crossings) **or** centroid
containment via `_point_in_shape`, ensuring fully-inside shapes are correctly
detected even when no edges cross.

---

## [2.1.1] - 2026-02-21

### Added — Shape Clipping Modes

Two new optional modes for Shape markers that trim overlapping outlines on placement.
Only one mode can be active at a time; enabling one automatically disables the other.

#### `scripts/utils/GeometryUtils.gd` — new static functions

| Function | Description |
|---|---|
| `segment_segment_intersect(a1,a2,b1,b2)` | Returns the intersection `Vector2` of two segments, or `null` if parallel / non-overlapping. |
| `segment_intersects_circle(a,b,center,r)` | Returns an `Array` of 0–2 `Vector2` points where segment `[a]→[b]` crosses the circle. |
| `point_inside_circle(p,center,r)` | Returns `true` if `p` is strictly inside the circle. |
| `clip_polygon_against_shapes(poly_pts,b_shapes)` | Splits each polygon edge at every intersection with `b_shapes`, keeps only sub-segments whose midpoint lies **outside** all shapes. Returns `Array` of `{"type":"seg","a":…,"b":…}`. |
| `clip_circle_against_shapes(center,r,b_shapes)` | Splits the circle at every intersection angle with `b_shapes`, keeps only arcs whose midpoint lies **outside** all shapes. Returns `Array` of `{"type":"arc","center":…,"radius":…,"from":…,"to":…}`. |

#### `scripts/guides/GuideMarker.gd`

- `var clip_data = []` — runtime list of clipped draw primitives (`seg` / `arc` items). When non-empty, the renderer uses this list instead of the full shape.
- `var clipped_by_ids = []` — IDs of other Shape markers currently acting as clippers for this marker. Used to recompute `clip_data` when a clipper is removed.
- `func clear_clip()` — resets both fields, restoring full-shape rendering.

#### `scripts/tool/GuidesLinesTool.gd`

**New variables**

| Variable | Default | Description |
|---|---|---|
| `auto_clip_shapes` | `false` | **Clip Intersecting Shapes** — mutual mode: both the new and all intersecting existing markers are clipped. |
| `cut_existing_shapes` | `false` | **Cut Into Existing Shapes** — one-way mode: only existing markers are clipped by the new shape; the new marker is left intact. |

**New private methods**

| Method | Description |
|---|---|
| `_get_shape_descriptor(marker, cell_size)` | Converts a marker's `draw_data` into a `{shape_type, …}` dict for GeometryUtils. |
| `_shapes_intersect(desc_a, desc_b)` | Returns `true` if the outlines of two shape descriptors actually cross. Handles all Poly×Poly, Poly×Circle, Circle×Circle combinations. |
| `_recompute_marker_clip(marker, cell_size)` | Rebuilds `marker.clip_data` from the current `clipped_by_ids` list. |
| `_apply_shape_clipping(new_marker)` | **Mutual** — registers `new_marker` and each intersecting marker as clippers of each other, then recomputes both sides. |
| `_apply_cut_to_existing_shapes(new_marker)` | **One-way** — registers `new_marker` as a clipper of each intersecting marker only (new marker unchanged). |
| `_remove_shape_clipping(removed_id)` | Called on deletion/undo-placement; removes `removed_id` from every marker's `clipped_by_ids` and recomputes affected markers. |
| `_set_shape_checkbox(node_name, value)` | Sets a `CheckButton` state inside `shape_settings_container` without firing its `toggled` signal (prevents recursion). |

**Hooks added to existing methods**

- `_do_place_marker` — calls `_apply_shape_clipping` or `_apply_cut_to_existing_shapes` after adding the marker.
- `_undo_place_marker` — calls `_remove_shape_clipping` before removing the marker.
- `_do_delete_marker` — calls `_remove_shape_clipping` before removing the marker.
- `_undo_delete_marker` — calls the appropriate clipping method after restoring the marker.

**UI additions** (inside Shape settings panel)

- `CheckButton "Clip Intersecting Shapes"` with hint label — enables mutual clipping.
- `CheckButton "Cut Into Existing Shapes"` with hint label — enables one-way clipping.
- Enabling either checkbox automatically unchecks the other via `_set_shape_checkbox`.

#### `scripts/overlays/MarkerOverlay.gd` — clipped rendering

- `_draw_custom_marker`: when `marker.clip_data` is non-empty, draws each `seg` item as `draw_line` and each `arc` item as `draw_arc` (point count scaled to arc span). Falls back to normal full-shape rendering when `clip_data` is empty.

#### Undo / Redo behaviour

| Action | Effect on clip state |
|---|---|
| Place B (clips A) → Undo | `_remove_shape_clipping(B.id)` restores A's full outline |
| Delete A → Undo | `_apply_shape_clipping` / `_apply_cut_to_existing_shapes` reapplies A's clipping |
| Redo Place B | `_do_place_marker` re-runs the appropriate clipping pass |

`clip_data` is **not serialised** — it is recomputed automatically through the history system and requires no changes to the save format.

---

## [2.1.0] - 2026-02-21

### Refactoring — Geometry centralisation (Phase 3)

All geometry logic that was still inlined inside `guides_lines_api.gd` has been
moved into `GeometryUtils.gd` and delegated from thin wrapper methods in the API.
No public API signatures were changed.

#### `scripts/utils/GeometryUtils.gd` — new static functions

| Function | Description |
|---|---|
| `closest_point_on_circle(p, center, r)` | Nearest point on a circle's circumference; handles the degenerate case where `p` lies exactly at the centre. |
| `closest_point_on_polygon_edges(p, pts, closed=true)` | Nearest point on any edge of a polygon or polyline. `closed=true` (default) wraps the last edge back to `pts[0]`; `closed=false` treats the array as an open polyline. Replaces per-method `for i in range(…)` edge loops. |
| `nearest_polygon_vertex(p, pts)` | Returns the vertex in `pts` closest to `p`, or `null` for an empty array. |
| `line_intersect_segment(lp, ld, a, b)` | Intersects an infinite line `(lp + t·ld)` with segment `[a]→[b]`. Returns the intersection `Vector2` or `null` when parallel / out of range. |
| `line_intersect_circle(lp, ld, center, r)` | Intersects an infinite line with a circle. Returns an `Array` of 0, 1, or 2 `Vector2` intersection points. |

#### `scripts/api/guides_lines_api.gd` — internal simplifications

- **`_get_map_context(t) → Array`** — new private helper that returns `[map_rect, cell_size]`
  for the current world (or `[null, null]` when no map is loaded). Eliminates the
  identical 4-line `map_rect`/`cell_size` boilerplate that was duplicated in
  `find_nearest_marker_by_geometry`, `find_line_intersection`, and
  `find_nearest_geometry_point`.
- **`find_nearest_marker_by_geometry`** — inline circle closest-point block (8 lines),
  polygon edge loop (8 lines), nearest-vertex loop (5 lines), and Path edge/vertex
  blocks all replaced by single `GeometryUtils.*` calls.
- **`find_nearest_geometry_point`** — same circle, polygon, and Path blocks replaced by
  `GeometryUtils.closest_point_on_circle` / `closest_point_on_polygon_edges`.
- **`_line_intersect_segment`** — body replaced by a single delegation to
  `GeometryUtils.line_intersect_segment`.
- **`_line_intersect_circle`** — body replaced by a single delegation to
  `GeometryUtils.line_intersect_circle`.

#### Bug fixes

- **`GeometryUtils.closest_point_on_circle`**: local variable named `len` conflicted
  with GDScript's built-in global function of the same name, causing a parse error on
  load. Renamed to `to_len`.
- **`guides_lines_api._get_map_context`**: parameter named `tool` is a reserved keyword
  in GDScript, causing a parse/tokeniser error. Renamed to `t`.

## [2.0.11] - 2026-02-21

### Added
- **`GuidesLinesApi` — External API for inter-mod communication**: New file `scripts/api/guides_lines_api.gd` exposes a rich programmatic interface so other mods can interact with GuidesLines without touching internal state.
  - **Signals**: `marker_placed(marker_id, position)`, `marker_deleted(marker_id)`, `all_markers_deleted()`, `settings_changed(setting_name, value)`.
  - **Marker placement**: `place_line_marker()`, `place_shape_marker()`, `place_arrow_marker()`, `place_path_marker()` — all with full parameter control and automatic history (undo/redo) recording.
  - **Marker deletion**: `delete_marker(id)`, `delete_all_markers()` — both backed by `HistoryApi`.
  - **Marker queries**: `get_markers()`, `get_marker(id)`, `get_marker_count()`.
  - **Spatial queries**:
    - `find_nearest_marker(coords, radius)` — search by marker position.
    - `find_nearest_marker_by_geometry(coords, radius)` — search against actual drawn geometry (line segments, shape edges/circumference, path segments, arrow shaft); returns closest point and nearest vertex.
    - `find_nearest_geometry_point(coords, radius)` — returns the exact closest point on any marker geometry.
    - `find_line_intersection(line_from, line_to, coords, radius)` — finds the nearest intersection of an infinite line with any marker geometry.
  - **Overlay & settings control**: `set_cross_guides()`, `set_permanent_vertical()`, `set_permanent_horizontal()`, `set_show_coordinates()`, `get_settings()`.
  - **Tool control**: `activate_tool()`, `is_tool_active()`, `is_ready()`.
  - API is registered via `_Lib`'s `ApiApi` as `"GuidesLinesApi"` and can be consumed by other mods with `self.Global.API.GuidesLinesApi`.

### Changed
- `GuidesLines.gd` now loads `guides_lines_api.gd`, instantiates `GuidesLinesApi`, and registers it after all classes are loaded via new `_register_external_api()` helper.
- `GuidesLinesTool.Update()` now always runs (even when the tool is not the active tool) so that API-placed markers are drawn correctly at all times.
- `GuidesLinesTool` creates its overlay even while the tool is inactive, ensuring markers placed via the API are visible immediately.

### Technical Changes
- **`GuidesLinesTool` — API bridge methods**: Added `api_place_marker(marker_data)` and `api_delete_marker_by_id(marker_id)` as thin public wrappers that call the internal `_do_*` helpers and record the appropriate `HistoryApi` records, keeping the inner `PlaceMarkerRecord`/`DeleteMarkerRecord` classes private.
- **Event notifications**: `_do_place_marker()`, `_do_delete_marker()`, and `_do_delete_all()` now call `guides_lines_api._notify_marker_placed/deleted/all_deleted()` after mutating state, so signal subscribers always receive events regardless of whether the action originated from the user or the API.
- `_do_delete_marker()` now captures `deleted_id` before erasing the entry from `markers_lookup` to guarantee the correct id is forwarded to the notification call.

## [2.0.10] - 2026-02-19

### Added
- **Shape subtype "Custom (N-sided)"**: New polygon subtype that allows placing a regular polygon with any number of sides from 3 to 50.
  - Added **"Custom (N-sided)"** option to the Shape Type selector in the tool panel.
  - Added **Sides** SpinBox (range 3–50) in the Shape settings UI. The control is only visible when the "Custom" subtype is selected.
  - `active_shape_sides` variable and `DEFAULT_SHAPE_SIDES = 6` constant added to `GuidesLinesTool`.
  - `SHAPE_CUSTOM = "Custom"` constant added.
  - Sides setting is persisted in `type_settings["Shape"]["sides"]` and survives type switching.
  - Sides setting is reset to default (6) when "Reset to Defaults" is pressed.
- **`shape_sides` property in `GuideMarker`**: Stores the number of polygon sides for Custom markers.
  - Saved and loaded via `Save()` / `Load()` with backward compatibility (defaults to 6 if absent).
  - Correctly invalidates geometry cache when changed via `set_property()`.
- **Custom polygon geometry**: `_recalculate_geometry()` in `GuideMarker` now handles the `"Custom"` subtype, computing vertices from `shape_sides` and `shape_angle` via `GeometryUtils.calculate_polygon_vertices()`.
- **Preview rendering**: `MarkerOverlay._draw_custom_marker_preview()` renders the Custom polygon preview at the cursor using `tool.active_shape_sides`.
- Rotation controls (scroll wheel, RMB +45°) work unchanged for the Custom subtype.

### Fixed
- Fixed `match` block in `GuideMarker._recalculate_geometry()`: the `"Custom"` branch was incorrectly indented outside the `match` statement, causing a crash on placement. Also restored the missing `cached_draw_data["points"] = ...` call that had been lost in the same block.

## [2.0.9] - 2026-02-19

### Added
- **Shape Mouse Controls**: Shape markers now follow object-tool conventions for mouse interaction:
  - **Scroll Wheel** — rotates the shape (5°/tick).
  - **Alt + Scroll Wheel** — changes the shape radius (0.1 cells/tick, previous wheel behavior).
  - **RMB** — rotates the shape by +45°.
- Added `adjust_shape_angle_with_wheel(direction)` method to `GuidesLinesTool` — adjusts shape rotation via scroll wheel (5° step), wrapping 0–360°.
- Added `rotate_shape_45()` method to `GuidesLinesTool` — rotates shape by 45° on RMB press.

### Changed
- Circle subtype is excluded from all rotation controls (scroll wheel angle and RMB +45°), as rotation has no effect on circles.

### Fixed
- **Grid snapping not working**: Marker placement never snapped to the grid even when snapping was globally enabled. Root cause was using the non-existent property `Global.Editor.IsSnapToGrid` (always evaluated to `false`) instead of the correct official API property `Global.Editor.IsSnapping`. Fixed in `place_marker()`, `_handle_path_placement()`, and `_handle_arrow_placement()`.

## [2.0.8] - 2026-02-19

### Added
- **Mod Settings Panel**: Integrated with `_Lib` `ModConfigApi` — settings are now accessible via **Edit → Preferences → Mods → Guides Lines**.
- **Persistent Settings**: Toggle states for Proximity Cross Guides, Permanent Vertical/Horizontal Center Lines, and Show Grid Coordinates are now saved between sessions (`user://mod_config/choson_guideslines.json`).
- **Configurable Hotkey**: Added a hotkey to activate the Guide Markers tool (default: `9`), configurable via **Edit → Preferences → Shortcuts → Guides Lines**. Shortcut assignment is saved between sessions.

### Changed
- Settings variables (`cross_guides_enabled`, `perm_vertical_enabled`, `perm_horizontal_enabled`, `show_coordinates_enabled`) are now managed through `ModConfigApi` rather than being hardcoded.

## [2.0.7] - 2026-02-17

### Changed
- The "Snap to Grid" checkbox has been removed from the tool's UI.
- The mod now respects Dungeondraft's global "Snap to Grid" setting, providing better integration and a more consistent user experience.
- Marker placement (including lines, shapes, paths, and arrows) will only snap to the grid if the global snapping option is enabled in Dungeondraft.

### Fixed
- Resolved a bug where markers would always snap to the grid, regardless of the global setting.
- Fixed several parsing errors caused by incorrect indentation and leftover code from the refactoring process.

## [2.0.6] - 2026-02-17

### Refactoring
- Reorganized the `scripts` folder by grouping files into subdirectories based on their functionality (`tool`, `render`, `overlays`, `guides`, `utils`).
- Updated all `preload` and `ResourceLoader.load` paths to reflect the new file structure.

## [2.0.5] - 2026-02-17

### Refactoring
- **Drawing Logic Refactoring**:
  - Created a new static helper class `GuidesLinesRender` (`scripts/GuidesLinesRender.gd`) to centralize all drawing logic.
  - Moved adaptive line width calculation, text-with-outline rendering, and drawing of primitives (lines, circles, polygons, arrows) into `GuidesLinesRender`.
  - All overlay classes (`MarkerOverlay`, `PermanentOverlay`, `CrossOverlay`) now use `GuidesLinesRender` for their drawing operations, eliminating code duplication.
- **Code Cleanup**:
  - Removed redundant drawing helper functions from `MarkerOverlay.gd` and `PermanentOverlay.gd`.
  - Ensured consistent rendering behavior across all guide types by using the centralized rendering class.

### Bug Fixes
- Fixed several parsing errors (`Expected indented block`, `Identifier not found`) that occurred during the refactoring process by ensuring correct `preload` usage and cleaning up corrupted code blocks.

## [2.0.4] - 2026-02-17

### 🚀 Optimized & Refactored

**Code Architecture**:
- **Consolidated Geometry**: Created a new `GeometryUtils` static helper class to handle all geometric calculations.
- **Unified Math**: Moved duplicate logic for polygon generation, line clipping, and ray intersection to `GeometryUtils`.
- **Improved Ray Clippping**: Implemented a robust "Slab Method" algorithm for `get_ray_to_rect_edge` to correctly handle ray intersections with map boundaries from both inside and outside.
- **Cleaner Code**: Significantly reduced code duplication in `GuideMarker.gd` and `MarkerOverlay.gd`.

**Stability**:
- **Parser Fixes**: Resolved GDScript parsing errors related to class loading order (`extends` before `class_name`).
- **Constant Management**: Replaced usage of potentially ambiguous `TAU` with `GeometryUtils.TWO_PI`.

## [2.0.3] - 2026-02-16

### 🚀 Optimized

- **Massive Performance Boost**: Completely refactored the rendering pipeline for markers (`GuideMarker` and `MarkerOverlay`).
- **Geometry Caching**: Implemented a comprehensive caching system that pre-calculates marker geometry (lines, polygons, rays) only when properties change, rather than every frame.
- **Rendering Efficiency**: Removed all expensive trigonometric operations and intersection calculations from the `_draw` loop. The renderer now simply consumes pre-calculated vector arrays.
- **Engine-Native Clipping**: Replaced manualviewport line clipping with `Liang-Barsky` ray clipping to map boundaries, leveraging Godot's built-in canvas item culling for maximum efficiency.
- **Fixed Mirroring**: Corrected `Line` marker behavior to properly respect the `Mirror` property by calculating two distinct rays instead of one infinite line.
- **Code Stability**: Fixed syntax errors and potential "unexpected assignment" issues in GDScript.

## [2.0.2] - 2026-02-16

### 🚀 Optimized & Fixed

**Performance & Memory**:
- **Critical Memory Leak Fix**: Fixed memory leak in `PermanentOverlay` and `MarkerOverlay` where font resources were re-created every frame. Fonts are now cached once.
- **Instant Marker Access**: Implemented `Dictionary` lookup for markers (O(1) access), significantly speeding up Undo/Redo operations and deletions for large numbers of markers.
- **Cached Geometry**: `CrossOverlay` now pre-calculates and caches map dimensions and guide line coordinates instead of recalculating them every draw call.
- **Engine-Native Culling**: Removed redundant manual camera culling code in `CrossOverlay`. Now relies on Godot's efficient built-in viewport culling, simplifying rendering logic.

## [2.0.1] - 2026-02-16

### 🐛 Fixed

**Performance Optimizations**:
- Fixed critical performance issue with infinite `update_count` accumulation in `GuidesLinesTool._process()`
- Removed forced `update()` calls every frame (60fps × 4 overlays = 240fps rendering)
- Added conditional rendering: overlays now update only when camera/markers/state changes
- Added iteration limits to coordinate drawing loops (100 for vanilla grid, 1000 for custom_snap)
- Eliminated performance degradation during idle time

**UI Interaction**:
- Fixed markers being created when clicking UI buttons (now checks viewport x < 450)
- Fixed preview marker freezing at last position when cursor enters UI area (now disappears cleanly)
- Preview now updates smoothly only when cursor is outside UI region

**Visual Improvements**:
- Added adaptive scaling for lines and markers at low zoom levels (50% and below)
- Lines and markers now scale proportionally with camera zoom for better visibility
- All visual elements (lines, markers, text, arrows) adapt to zoom level
- Consolidated preview constants (PREVIEW_MARKER_SIZE, PREVIEW_LINE_WIDTH) at class level

**Line Marker Rendering**:
- Fixed Line marker rays disappearing when marker point is outside camera viewport
- Implemented proper ray-viewport intersection algorithm for off-screen markers
- Added map boundary clipping: lines no longer extend beyond map edges (WorldRect)
- Implemented Liang-Barsky line clipping algorithm for precise boundary handling
- Fixed Mirror parameter: rays now correctly render in one direction, Mirror adds opposite ray

**Code Quality**:
- Fixed GDScript parse error: moved constants to class level (not inside functions)
- Simplified `_get_ray_to_viewport_edge()` function for better maintainability
- Removed unnecessary helper functions

## [2.0.0] - 2026-02-15

### 🎉 Major Release - Complete Redesign

This is a **major breaking release** with a complete architectural overhaul. Maps saved with v2.0.0+ are **NOT** compatible with v1.x versions.

### 🚀 Added

**New Marker System**:
- **Line Markers**: 
  - Any angle (0-360°) with infinite length to map boundaries
  - Mirror mode for symmetrical designs
  - Mouse wheel adjustment (5° increments)
  - Custom color per marker
  
- **Shape Markers**: 
  - 5 subtypes: Circle, Square, Pentagon, Hexagon, Octagon
  - Adjustable radius (0.5-100 cells)
  - Full rotation (0-360°)
  - Mouse wheel radius adjustment (0.5 cell increments)
  - Mouse wheel rotation adjustment (5° increments)
  - Custom color per marker
  
- **Path Markers**: 
  - Multi-point custom paths with sequential placement
  - Click to add points (minimum 2, no maximum)
  - Right-click to finish as open path
  - Click near first point to close path (creates loop, requires 3+ points)
  - ESC to cancel placement
  - Real-time preview with visual feedback:
    - First point: green, larger
    - Intermediate points: red, semi-transparent
    - Preview line to cursor: white, dashed
    - Pulsing green indicator when hovering to close
  - Grid snapping support for each point
  - Custom color per marker
  
- **Arrow Markers**: 
  - 2-point directional arrows with arrowheads
  - Automatic completion at second point
  - Customizable arrowhead:
    - Length: 10-200 pixels
    - Angle: 10-60 degrees
  - Right-click or ESC to cancel before second point
  - Real-time preview showing arrow line and arrowhead
  - Custom color per marker

**Enhanced Features**:
- Mouse wheel parameter adjustment while hovering over controls
- Color picker for each marker with independent color memory per type
- Smart UI: type-specific settings appear dynamically
- Preview system shows exact appearance before placement
- Quick angle buttons (0°, 45°, 90°, 135°) for Line markers
- Quick angle buttons for Shape rotation

### 🔄 Changed

**Complete UI Redesign**:
- Single marker type selector (dropdown instead of checkboxes)
- Dynamic settings panels based on selected type
- All marker parameters accessible before placement
- Cleaner, more intuitive layout
- Reset to Defaults button for all settings

**Architecture Improvements**:
- Single `marker_type` field instead of `marker_types` array
- Each marker stores its own visual parameters
- Type-specific settings stored independently
- Simplified data model with better extensibility

**Behavior Changes**:
- Right-click now cancels Path/Arrow placement (no longer deletes markers during preview)
- Right-click deletion only works when NOT in placement mode
- Settings are remembered per-type when switching between marker types
- Lines always extend to map boundaries (infinite appearance)

### 💔 Breaking Changes

**⚠️ THIS RELEASE BREAKS BACKWARD COMPATIBILITY**

- **Save Format**: Maps saved with v2.0.0 cannot be loaded in v1.x
  - Old marker format (vertical/horizontal/diagonal) completely removed
  - New format uses single type with parameters
  - No automatic migration from v1.x to v2.0.0
  
- **API Changes**: 
  - `GuideMarker.has_type()` removed
  - `GuideMarker.add_type()` removed
  - `GuideMarker.remove_type()` removed
  - Replaced with: `marker_type`, `angle`, `line_range`, `circle_radius`, `shape_subtype`, `shape_angle`, `path_points`, `path_closed`, `arrow_head_length`, `arrow_head_angle`, `color`, `mirror`

**Migration Path**:
- ⚠️ **Backup all maps** before upgrading from v1.x
- Old maps must be recreated with new marker system
- No automated conversion tool available

### 🐛 Fixed

- Fixed Shape markers not showing in correct rotation
- Fixed coordinate display showing incorrect distances for diagonal lines
- Fixed undo/redo not properly restoring marker visual state
- Fixed preview not updating when adjusting parameters with mouse wheel
- Fixed Path placement allowing single-point paths
- Fixed Arrow placement allowing cancellation after completion
- Fixed color not persisting when switching marker types
- Fixed Shape angle controls not disabling for Circle subtype

### 🔧 Technical Changes

**Code Structure**:
- Refactored `GuidesLinesTool.gd` (~800 lines modified)
  - Single `active_marker_type` instead of array
  - Added `type_settings` dictionary for per-type state
  - Path/Arrow placement state machines
  - Mouse wheel event handling
  
- Refactored `GuideMarker.gd` (~200 lines modified)
  - Flat property structure for all marker types
  - Simplified serialization/deserialization
  - Removed backward compatibility code
  
- Refactored `MarkerOverlay.gd` (~640 lines modified)
  - Path preview rendering with visual feedback
  - Arrow preview with arrowhead display
  - Shape rendering with rotation support
  - Mouse wheel input handling
  - ESC key cancellation support

**History System**:
- Custom record classes now track full marker state including visual parameters
- Proper restoration of color, angle, radius, and all type-specific properties
- History limits maintained (100 records per operation type)

**Constants**:
- Added: `MARKER_TYPE_LINE`, `MARKER_TYPE_SHAPE`, `MARKER_TYPE_PATH`, `MARKER_TYPE_ARROW`
- Added: `SHAPE_SUBTYPE_CIRCLE`, `SHAPE_SUBTYPE_SQUARE`, etc.
- Renamed: `LINE_COLOR` → `DEFAULT_LINE_COLOR`
- Added: Default values for all marker parameters

### 📝 Documentation

- Complete README rewrite for new marker system
- Updated all screenshots and examples
- New usage sections for each marker type
- Migration guide for v1.x users (see "Breaking Changes" above)

### ⚡ Performance

- Optimized rendering for multiple markers
- Reduced redundant coordinate calculations
- Improved preview update efficiency
- Better memory management for Path markers with many points

### 🧪 Testing Status

- ✅ Line markers: angles, mirror, color, infinite extension
- ✅ Shape markers: all subtypes, rotation, radius, color
- ✅ Path markers: placement, closing, cancellation, preview
- ✅ Arrow markers: placement, cancellation, arrowhead customization
- ✅ Undo/redo: all operations with full state restoration
- ✅ Save/load: new format serialization
- ✅ Custom_snap integration: grid snapping with custom grids
- ✅ Performance testing with 100+ markers
- ✅ Edge cases: large radii, extreme arrow lengths

---

## [1.0.10] - 2026-02-04

### Added
- **UpdateChecker Integration**: Automatic update notifications
- **HistoryApi Integration**: Full undo/redo support

### Fixed
- Corrected Logger API usage
- Fixed Global.API references

### Technical Changes
- Custom History Record classes
- UpdateChecker for GitHub repository

---

## [1.0.9] - 2026-02-03

### Changed
- **UI Redesign**: All settings in tool panel

### Fixed
- **_Lib-1.2.0 Compatibility**: Complete rewrite for new API

### Technical Changes
- Removed ModConfig integration
- Updated Logger initialization

---

## [1.0.8] - 2026-02-01

### Added
- **Logger API Integration**
- **HistoryApi Integration**
- **ModConfigApi Integration**

### Improved
- **ModRegistry Integration**
- **Code Quality**

---

## [1.0.7] - 2026-02-01

### Updated
- **Compatibility Update**: _Lib 1.2.0

---

## [1.0.6] - 2026-01-17

### Fixed
- Application crash when `custom_snap` not activated

### Improved
- Smart Coordinates Toggle

---

## [1.0.5] - 2026-01-XX

### Features
- Basic guide lines system
- Multiple marker types (vertical, horizontal, diagonal)
- Grid coordinate display
- Snap to grid with custom_snap support

---

[2.1.1]: https://github.com/ChosonDev/GuidesLines/compare/v2.1.0...v2.1.1
[2.0.0]: https://github.com/ChosonDev/GuidesLines/compare/v1.0.10...v2.0.0
[1.0.10]: https://github.com/ChosonDev/GuidesLines/compare/v1.0.9...v1.0.10
[1.0.9]: https://github.com/ChosonDev/GuidesLines/compare/v1.0.8...v1.0.9
[1.0.8]: https://github.com/ChosonDev/GuidesLines/compare/v1.0.7...v1.0.8
[1.0.7]: https://github.com/ChosonDev/GuidesLines/compare/v1.0.6...v1.0.7
[1.0.6]: https://github.com/ChosonDev/GuidesLines/compare/v1.0.5...v1.0.6
[1.0.5]: https://github.com/ChosonDev/GuidesLines/releases/tag/v1.0.5

### Changed - Major Refactoring (Phase 2)
- **Shape Marker System**: Completely redesigned Circle markers into versatile Shape markers
  - Replaced Circle marker type with Shape marker type
  - Added 5 shape subtypes: Circle, Square, Pentagon, Hexagon, Octagon
  - Added shape rotation with **Angle** parameter (0-360°, disabled for Circle)
  - Shape markers now support polygon generation with customizable angles
  - Quick angle buttons (0°, 45°, 90°, 135°) for fast rotation setup
  
- **Line Markers Simplified**: Removed Range parameter for cleaner behavior
  - Line markers now **always draw to map boundaries** (infinite length)
  - Removed line_range parameter and related UI controls
  - Simplified line rendering logic - no more finite/infinite distinction
  
- **UI Streamlining**: Removed redundant information displays
  - Removed InfoLabel section that showed "Ready to start" messages
  - Cleaner, more focused tool panel
  
- **Consistent UX**: Unified cancellation behavior across marker types
  - Arrow markers now use **right-click cancellation** (like Path markers)
  - Removed Cancel Arrow button for consistency
  - Both Path and Arrow now support right-click to cancel placement

- **Bug Fixes**:
  - Fixed Reset to Defaults button not resetting Arrow parameters (Head Length, Head Angle)

### Changed - Major Refactoring (Phase 1)
- **Complete Marker System Redesign**: Replaced fixed guide line types with flexible custom marker system
  - Removed pre-defined marker types (vertical, horizontal, diagonal left, diagonal right)
  - Introduced marker type system: Line, Shape, Path, and Arrow types (with extensibility for future types)
  - Line markers now support custom angles (0-360°) instead of fixed orientations
  - Added mirror option for Line markers (creates second line at 180° offset)
  - **NEW: Path markers** with multi-point placement for complex guide paths
    - Draw paths with any number of points (minimum 2)
    - Click to add points sequentially
    - Close path by clicking near first point (creates loop, requires 3+ points)
    - Finish open path with right-click
    - Cancel placement with ESC key
    - Real-time preview shows points, lines, and closing indicator
    - Supports grid snapping for each point
  - **NEW: Arrow markers** with 2-point directional arrows and customizable arrowheads
    - Simplified Path variant with exactly 2 points (auto-finishes at second point)
    - Draws directional arrow from first point to second point
    - Customizable arrowhead with length (10-200 pixels) and angle (10-60 degrees)
    - Real-time preview shows arrow line and arrowhead to cursor
    - Cancel placement with right-click or ESC key before placing second point
    - Supports grid snapping for both points
  - Added per-marker color customization (default blue, but any color supported)
  - Each marker type has independent settings (angle/mirror for Lines; shape/angle/radius for Shapes; multi-point for Paths; arrowhead for Arrows)

- **UI Completely Redesigned**:
  - Replaced individual line type checkboxes with unified marker type selector
  - Type-specific controls appear dynamically based on selected marker type
  - **Line Controls**: Angle spinbox (0-360°), Mirror checkbox
  - **Shape Controls**: Shape subtype selector (Circle/Square/Pentagon/Hexagon/Octagon), Radius spinbox (0.1+ cells), Angle spinbox (0-360°, disabled for Circle), Quick angle buttons (0°/45°/90°/135°)
  - **Path Controls**: Interactive multi-point placement mode with instructions
  - **Arrow Controls**: Arrowhead Length spinbox (10-200 pixels), Arrowhead Angle spinbox (10-60 degrees)
  - Added color picker button for customizing marker colors
  - Type-specific settings are remembered when switching between types
  - Mouse wheel support for quick parameter adjustment:
    - Lines: Scroll to adjust angle (5° increments, wraps around 360°)
    - Shapes: Scroll to adjust radius (0.5 cell increments, minimum 0.5)
  - Updated preview system to show custom angles, shapes with rotation, and path placement in real-time
  - Path preview features:
    - First point shown in green (larger)
    - Intermediate points shown in red
    - White dashed line to cursor position
    - Pulsing green circle around first point when hovering to close path
    - Cancel button visible during placement

### Technical Changes

**Phase 2 Changes:**

- **GuideMarker.gd**:
  - Replaced `circle_radius` with `shape_radius` (applies to all Shape subtypes)
  - Removed `line_range` property (lines now always infinite)
  - Added `shape_angle` property (float, 0.0-360.0 degrees) for rotating Shape markers
  - Added `shape_subtype` property (String: "Circle", "Square", "Pentagon", "Hexagon", "Octagon")
  - Renamed `marker_points` universal property (used by Path, Arrow, and Shape markers)
  - Updated Save() and Load() methods for new Shape system

- **GuidesLinesTool.gd**:
  - Removed `active_line_range` and all Range-related UI code
  - Added `active_shape_angle` (0.0-360.0) with UI controls
  - Added `active_shape_subtype` with OptionButton selector
  - Renamed marker type constant: `MARKER_TYPE_CIRCLE` → `MARKER_TYPE_SHAPE`
  - Added quick angle buttons (0°, 45°, 90°, 135°) for Shape rotation
  - Updated `_generate_shape_vertices()` to accept `angle_degrees` parameter
  - Updated `_calculate_polygon_vertices()` for N-sided polygons with rotation
  - Removed InfoLabel and all status display logic
  - Removed ArrowCancelButton from UI
  - Updated `_handle_arrow_placement()` to support right-click cancellation
  - Fixed `_on_reset_pressed()` to properly reset Arrow parameters (Head Length, Head Angle)
  - Shape Angle control automatically disabled when Circle subtype selected
  - Updated `update_ui()` to handle Shape Angle enable/disable logic

- **MarkerOverlay.gd**:
  - Removed `range_cells` parameter from `_calculate_line_endpoints()` - lines always draw to map boundaries
  - Updated Shape rendering to apply `shape_angle` rotation to polygon vertices
  - Added right-click (RMB) cancellation support for Arrow markers
  - Simplified coordinate display: Shape markers show coordinates only at center point
  - Updated `_draw_custom_marker()` for Shape variants with rotation
  - Updated vertex calculation for rotated polygons

**Phase 1 Changes:**

- **GuideMarker.gd**:
  - Replaced `marker_types` array with single `marker_type` field ("Line", "Circle", "Path", or "Arrow")
  - Added properties: `angle`, `line_range`, `circle_radius`, `color`, `mirror`
  - Added Path properties: `path_points` (Array of Vector2), `path_closed` (bool)
  - Added Arrow properties: `arrow_head_length` (float), `arrow_head_angle` (float)
  - Removed old methods: `has_type()`, `add_type()`, `remove_type()`
  - Updated `Save()` and `Load()` methods for new data format including Path and Arrow serialization
  - Removed backward compatibility with v1.0.9 and earlier save formats
  - Changed default LINE_COLOR constant to DEFAULT_LINE_COLOR

- **GuidesLinesTool.gd** (~800 lines added/modified):
  - Replaced `active_marker_types` array with `active_marker_type` single value
  - Added active settings variables: `active_angle`, `active_line_range`, `active_circle_radius`, `active_color`, `active_mirror`
  - Added Path state variables: `path_placement_active`, `path_temp_points`, `path_preview_point`
  - Added Arrow state variables: `arrow_placement_active`, `arrow_temp_points`, `arrow_preview_point`, `arrow_head_length`, `arrow_head_angle`
  - Added `type_settings` dictionary to store per-type settings independently
  - Added constants: `MARKER_TYPE_LINE`, `MARKER_TYPE_CIRCLE`, `MARKER_TYPE_PATH`, `MARKER_TYPE_ARROW`, default value constants
  - Added UI reference variables: `type_selector`, `type_specific_container`, type-specific containers including `path_settings_container` and `arrow_settings_container`
  - Completely rewrote `_build_tool_panel()` to support new UI layout
  - Removed `toggle_marker_type()` function (no longer needed)
  - Updated `place_marker()` to handle Path type with multi-point logic
  - Added Path-specific methods:
    - `_handle_path_placement()` - handles sequential point placement
    - `_finalize_path_marker()` - creates Path marker from collected points
    - `_cancel_path_placement()` - resets Path placement state
  - Added Arrow-specific methods:
    - `_handle_arrow_placement()` - handles 2-point placement with auto-finish
    - `_finalize_arrow_marker()` - creates Arrow marker from two points
    - `_cancel_arrow_placement()` - resets Arrow placement state
  - Updated `_do_place_marker()` to create markers with new format including Path and Arrow
  - Added spinner/color change callbacks for all new UI controls
  - Added methods: `adjust_angle_with_wheel()`, `adjust_circle_radius_with_wheel()`
  - Updated `update_ui_checkboxes_state()` to handle new UI elements
  - Updated `set_snap_to_grid()` to cancel Path placement when snap is disabled
  - Updated `_switch_type_ui()` to cancel Path placement when switching away from Path type

 - **MarkerOverlay.gd** (~640 lines restructured):
  - Added mouse wheel input handling in `_input()`:
    - Wheel up/down adjusts angle for Line type (5° increments)
    - Wheel up/down adjusts radius for Circle type (0.5 cell increments)
    - Ignores wheel when CTRL is held (preserves zoom functionality)
  - Added input handling for Path type:
    - Right-click (RMB) finalizes open path
    - ESC key cancels Path placement
  - Added input handling for Arrow type:
    - ESC key cancels Arrow placement before second point
  - Updated `_process()` to track mouse position for Path and Arrow previews
  - Completely rewrote `_draw()` to support custom marker types including Path and Arrow previews
  - Added `_draw_custom_marker()` - unified drawing for any marker type (Line, Circle, Path, Arrow)
  - Added `_draw_custom_marker_preview()` - preview drawing at cursor
  - Added `_draw_path_preview()` - interactive path placement preview with:
    - Visual differentiation for first point (green, larger)
    - Intermediate points (red, semi-transparent)
    - Preview line from last point to cursor (white, dashed style)
    - Pulsing indicator when hovering near first point to close path
  - Added `_draw_arrow_preview()` - interactive arrow placement preview with:
    - Green start point
    - White preview line from start to cursor
    - Preview arrowhead at cursor position
  - Added `_draw_arrowhead()` - helper function to draw arrowhead chevron using trigonometry
  - Added `_calculate_line_endpoints()` - computes line endpoints for any angle/range
  - Removed old separate drawing code for vertical/horizontal/diagonal lines
  - Line rendering now supports arbitrary angles and finite ranges
  - Circle rendering with proper coordinate display
  - Path rendering with lines connecting all points (closed or open)
  - Arrow rendering with main line and arrowhead chevron
  - Preview now shows exact appearance before placement
  - Added `_draw_coordinates_on_path()` - displays cumulative distance at each path point
  - Updated `_draw_marker_coordinates()` to handle Arrow type

- **GuidesLines.gd**:
  - Removed unused callback: `_on_marker_type_toggled()`
  - Minor code cleanup

### Breaking Changes
- **Save Format**: Maps saved with this version cannot be loaded in v1.0.10 or earlier
  - Old maps with vertical/horizontal/diagonal markers will NOT load correctly
  - Removed backward compatibility code
  - New format uses `marker_type`, `angle`, `line_range`, `circle_radius`, `color`, `mirror` fields
- **API Changes**: Anyone extending GuideMarker class will need to update to new structure

### Notes
- This is a work-in-progress intermediate commit
- Version number unchanged (still 1.0.10) pending completion
- Extensive testing needed before release
- Future consideration: Add backward compatibility loader if needed

## [1.0.10] - 2026-02-04

### Added
- **UpdateChecker Integration**: Automatic update notifications
  - Integrated with _Lib UpdateChecker API for GitHub release tracking
  - Automatic version checking on startup
  - Visual notifications when new versions are available
  - One-click access to download page from "Mod Versions" window (Mods menu)
  - Follows semantic versioning (SemVer 2.0.0) for proper version comparison

- **HistoryApi Integration**: Full undo/redo support for marker operations
  - Press Ctrl+Z to undo marker placement/deletion
  - Press Ctrl+Y to redo marker placement/deletion
  - History tracking for individual marker placement (limit: 100 records)
  - History tracking for individual marker deletion (limit: 100 records)
  - History tracking for "Delete All Markers" operation
  - Proper integration with Dungeondraft's native undo/redo system
  - Seamless cooperation with other mods using HistoryApi

### Fixed
- Corrected Logger API usage to properly use ClassInstancedLogger pattern
- Fixed unsupported format specifier %v (changed to %s for Vector2 output)
- Fixed Global.API references to use parent_mod.Global.API for proper _Lib access

### Technical Changes
- Implemented custom History Record classes:
  - `PlaceMarkerRecord` - tracks marker creation with full state
  - `DeleteMarkerRecord` - tracks single marker deletion with restoration data
  - `DeleteAllMarkersRecord` - tracks bulk deletion with full restoration
- Added record type identifiers for proper history grouping:
  - `GuidesLines.PlaceMarker` - for placement operations
  - `GuidesLines.DeleteMarker` - for deletion operations
  - `GuidesLines.DeleteAll` - for bulk deletion
- UpdateChecker configured for GitHub repository: Choson/GuidesLines
- History records implement proper `redo()`, `undo()`, and `record_type()` methods
- Max count limiting prevents history overflow (100 records per operation type)

## [1.0.9] - 2026-02-03

### Changed
- **UI Redesign**: All settings moved to Guide Markers tool panel
  - Removed ModConfigApi settings menu (compatibility issues with _Lib-1.2.0)
  - All guide overlay settings now accessible directly in tool panel
  - More streamlined and accessible user experience
  - Settings organized in logical sections: Marker Types, Options, and Guide Overlays

### Fixed
- **_Lib-1.2.0 Compatibility**: Complete rewrite for new API structure
  - Fixed Logger API usage (removed non-existent `for_mod()` method)
  - Updated to use `self.Global.API` instead of `Global.API`
  - Fixed ResourceLoader cache parameter (changed from `true` to `false`)
  - Corrected ModRegistry API usage for mod detection
  - All API calls now conform to _Lib-1.2.0 standards
- Fixed integration with Custom Snap Mod (Lievven.Snappy_Mod)
- Markers now correctly snap to custom grid when Custom Snap Mod is enabled
- Improved mod detection using proper unique_id lookup instead of searching for field name

### Technical Changes
- Removed ModConfig integration (ModConfigApi builder)
- Added new UI callbacks: `_on_cross_guides_toggled`, `_on_perm_vertical_toggled`, `_on_perm_horizontal_toggled`, `_on_perm_coordinates_toggled`
- Updated Logger initialization to use InstancedLogger directly
- Fixed snappy_mod detection to work with new ModRegistry structure
- Removed `mod_config` and `config_initialized` variables
- Simplified `_init_mod_config()` removed entirely

## [1.0.8] - 2026-02-01

### Added
- **Logger API Integration**: Professional structured logging system
  - Replaced all `print()` calls with Logger API for better diagnostics
  - Added log levels (debug, info, error) for different message types
  - Automatic mod name prefix in all log messages
  - Better error tracking and debugging capabilities

- **HistoryApi Integration**: Full undo/redo support
  - Press Ctrl+Z to undo marker placement
  - Press Ctrl+Y to redo marker placement
  - Undo/redo for individual marker deletion
  - Undo/redo for "Delete All Markers" operation
  - Seamless integration with Dungeondraft's native history system

- **ModConfigApi Integration**: Professional settings panel
  - Replaced manual UI creation with ModConfigApi builder
  - Settings now integrated into Dungeondraft's Preferences window
  - Automatic saving/loading of all settings
  - Clean, organized settings categories:
    - Proximity Guides (cross guides toggle)
    - Permanent Guides (vertical/horizontal lines, coordinates)

### Improved
- **ModRegistry Integration**: Enhanced mod detection
  - Better detection of custom_snap mod using ModRegistry
  - Shows detected mod name and version in logs
  - More reliable cross-mod compatibility
  - Graceful fallback if ModRegistry not available

- **Code Quality**: Significant refactoring
  - Removed ~70 lines of manual UI code
  - Cleaner separation of concerns
  - Better error handling throughout
  - More maintainable codebase

### Technical Changes
- Added LOGGER variable to main mod and tool classes
- Implemented _init_mod_config() for ModConfigApi setup
- Added history action handlers: _do_place_marker, _undo_place_marker, etc.
- Removed manual settings panel creation (replaced by ModConfigApi)
- Removed manual toggle callback functions
- Enhanced snappy_mod detection with proper mod info retrieval

## [1.0.7] - 2026-02-01

### Updated
- **Compatibility Update**: Updated for _Lib 1.2.0 and Dungeondraft 1.1.1.1
  - Fixed snappy_mod detection to work with new _Lib API structure
  - Replaced unsafe `_get_property_list()` access with safe `get()` method
  - Improved compatibility with _Lib's new InstancedApiApi system
  - Added _Lib as explicit dependency

### Technical Changes
- Simplified snappy_mod detection logic using defensive programming
- Removed iteration through property list in favor of direct get() call
- Updated dd_version requirement to 1.1.1.1

## [1.0.6] - 2026-01-17

### Fixed
- **Critical Fix**: Application crash when `custom_snap` mod is not activated
  - Fixed incompatibility with Godot 3.4's property access mechanism for dynamic properties
  - Centralized `snappy_mod` detection in main mod file (`GuidesLines.gd`)
  - Implemented single-check optimization: `snappy_mod` availability is now checked only once after map load
  - Removed unsafe property access methods that caused crashes with _Lib API
  - All overlay classes now use cached reference to `snappy_mod` instead of performing runtime checks

### Improved
- **Smart Coordinates Toggle**: "Show Grid Coordinates" option now automatically disables when no guide lines are active
  - In Guide Markers tool: disabled when no marker line types are selected
  - In Guide Settings panel: disabled when both permanent center lines are off

### Technical Changes
- Replaced `cached_api` with `cached_snappy_mod` in tool and overlay classes
- Added `snappy_mod_checked` flag to prevent redundant API property list queries
- Simplified `_get_custom_snap()` methods to return cached reference
- Removed all debug logging statements
- Added `update_coordinates_checkbox_state()` method in `GuidesLinesTool`
- Added `settings_coords_checkbox` reference in main mod for dynamic UI updates

## [1.0.5] - Previous Version

### Features
- Advanced guide lines system with placeable markers
- Multiple marker types: vertical, horizontal, diagonal (45° and 135°)
- Grid coordinate display on guide lines
- Snap to grid functionality with custom_snap mod support
- Delete mode for marker removal
- Save/load markers with map files
- Optional proximity-based cross guides
- Optional permanent center guide lines


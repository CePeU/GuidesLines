# GuidesLines - Dungeondraft Mod

**Version:** 2.4.1<br>
**Compatible with:** Dungeondraft 1.1.1.1 and later  
**Requires:** _Lib-1.2.0

Advanced guide system with fully customizable markers for precise map alignment and composition.

### What's New in 2.4.1

Technical maintenance improves code quality, reliability and performance, with expanded regression tests. Markers, fill regions and marker templates are now saved and restored with the map.

---

## ⚠️ v2.0.0 — Breaking Changes (maps from v1.x are incompatible)

**Maps saved with v2.0.0+ are NOT compatible with v1.x.  No automatic migration — recreate markers using the new system.**

## ✨ What's New since 2.0.0

- 🔷 **Custom (N-sided) shapes** — place any regular polygon with 3–50 sides
- 🖱️ **Shape mouse controls** — scroll rotates, Alt+scroll changes radius, RMB rotates +45°
- ⚙️ **Persistent settings** — preferences saved between sessions (Edit → Preferences → Mods)
- ⌨️ **Configurable hotkey** — bind a key to the Guide Markers tool (default: `9`)
- 🔌 **External API** (`GuidesLinesApi`) — other mods can place/delete/query markers programmatically
- 🏗️ **Geometry centralised** — all math lives in `GeometryUtils.gd`; rendering in `GuidesLinesRender.gd`

---

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
  - [Placing Line Markers](#placing-line-markers)
  - [Placing Shape Markers](#placing-shape-markers)
  - [Placing Path Markers](#placing-path-markers)
  - [Placing Arrow Markers](#placing-arrow-markers)
  - [Managing Markers](#managing-markers)
  - [Overlay Features](#overlay-features)
  - [External API](#external-api)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Technical Details](#technical-details)
- [Troubleshooting](#troubleshooting)
- [Compatibility](#compatibility)
- [License](#license)

---

## Features

### 🎨 Flexible Marker System

**4 Powerful Marker Types:**

1. **Line Markers**
   - Any angle from 0° to 360°
   - Infinite length extending to map boundaries
   - Mirror mode for symmetrical designs
   - Mouse wheel angle adjustment (5° increments)
   - Custom color per marker
   - Perfect for alignment and perspective guides

2. **Shape Markers**
   - 6 subtypes: Circle, Square, Pentagon, Hexagon, Octagon, **Custom (N-sided)**
   - Custom subtype: any regular polygon from 3 to 50 sides
   - Radius: 0.5 to 100 grid cells
   - Full rotation support (except circles)
   - **Scroll wheel** — rotates shape (5° increments)
   - **Alt + Scroll wheel** — changes radius (0.1 cell increments)
   - **Right-click (RMB)** — quick +45° rotation
   - Custom color per marker
   - Ideal for circular rooms, polygonal features, area planning

3. **Path Markers**
   - Multi-point custom paths (minimum 2 points, no maximum)
   - Open or closed paths
   - Sequential placement with visual feedback
   - Right-click to finish, ESC to cancel
   - Grid snapping for each point
   - Custom color per marker
   - Perfect for complex curves, custom boundaries, organic shapes

4. **Arrow Markers**
   - 2-point directional arrows
   - Customizable arrowhead (length 10-200px, angle 10-60°)
   - Automatic completion at second point
   - Real-time preview
   - Custom color per marker
   - Great for indicating flow, direction, connections

### 🖱️ Interactive Controls

- **Mouse Wheel** (over Line Angle): Adjust angle ±5°
- **Mouse Wheel** (over Shape): Rotate shape ±5°
- **Alt + Mouse Wheel** (over Shape): Adjust radius ±0.1 cells
- **Right-Click** (Shape, before placement): Quick +45° rotation
- **Quick Angle Buttons**: 0°, 45°, 90°, 135° presets for common angles
- **Color Picker**: Independent color for each marker
- **Real-time Preview**: See exactly what you'll place
- **Settings Memory**: Each marker type remembers its last settings

### 📐 Advanced Features

- **Grid Snapping**: Respects Dungeondraft's global Snap to Grid setting; works with custom_snap mod
- **Coordinate Display**: Show grid positions on guide lines
- **Overlay System**:
  - Proximity guides (cross overlays near cursor)
  - Permanent center guides (vertical/horizontal)
  - Coordinate markers on guide lines
- **Full Undo/Redo**: Every operation is undoable (Ctrl+Z / Ctrl+Y)
- **Persistent Settings**: Overlay toggles and preferences saved across sessions (Edit → Preferences → Mods → Guides Lines)
- **Configurable Hotkey**: Bind any key to activate the tool (Edit → Preferences → Shortcuts → Guides Lines; default: `9`)
- **External API**: Other mods can interact with GuidesLines via `self.Global.API.GuidesLinesApi`
- **Auto-Updates**: GitHub release notifications via UpdateChecker

### 💾 Persistence

- Line, Shape and Path markers, Fill regions and captured templates are stored inside the map file.
- Saved geometry includes outlines modified by boolean operations, colors and marker parameters.
- Map data has its own format version, independent of the mod release version. Only an exact format-version match is loaded; incompatible or malformed blocks load no GuidesLines objects. The next map save replaces the entire GuidesLines block using the current format, including when the current collection is empty.
- In-progress placement, dragging, previews and undo history are session state and are not saved. Templates belong to their map.

---

## Installation

### Requirements

- **Dungeondraft** 1.1.1.1 or later
- **_Lib** 1.2.0 (required dependency)

### Steps

1. **Download** the latest release from [GitHub](https://github.com/ChosonDev/GuidesLines/releases)
2. **Extract** to your Dungeondraft mods folder:
   - **Windows**: `%AppData%\Dungeondraft\mods\`
   - **macOS**: `~/Library/Application Support/Dungeondraft/mods/`
   - **Linux**: `~/.local/share/Dungeondraft/mods/`
3. **Install _Lib** if not already present (from [_Lib releases](https://github.com/CreepyCre/_Lib/releases))
4. **Restart** Dungeondraft

### Verification

1. Launch Dungeondraft
2. Check **Mods** menu → **Mod Versions** — should show "Guide Markers v2.4.1"
3. Create/open a map
4. Select **Design** category → **Guide Markers** tool (or press **`9`**)
5. Tool panel should display marker type dropdown and settings

---

## Usage

### Placing Line Markers

**Best for: alignment, perspective, symmetry**

1. Select **Guide Markers** tool (Design category)
2. Choose **"Line"** from marker type dropdown
3. Configure settings:
   - **Angle**: 0-360° (or use quick buttons: 0°, 45°, 90°, 135°)
   - **Mirror**: Check for symmetrical paired line at 180° offset
   - **Color**: Click to pick custom color
   - **Tip**: Hover over angle spinbox and scroll mouse wheel to adjust in 5° increments
5. Click on map to place marker
6. Guide lines appear instantly, extending infinitely to map edges

**Angle Reference:**
- 0° = Horizontal right →
- 90° = Vertical down ↓
- 180° = Horizontal left ←
- 270° = Vertical up ↑

**Mirror Mode:** Creates two lines through the same point at opposite angles (great for symmetry axes)

---

### Placing Shape Markers

**Best for: circular rooms, polygonal structures, area planning**

1. Select **Guide Markers** tool
2. Choose **"Shape"** from dropdown
3. Select **Shape Subtype**:
   - Circle
   - Square
   - Pentagon (5 sides)
   - Hexagon (6 sides)
   - Octagon (8 sides)
   - **Custom (N-sided)** — any regular polygon from 3 to 50 sides
     - Extra **Sides** spinbox appears when Custom is selected
4. Configure settings:
   - **Radius**: 0.5–100 grid cells
     - **Alt + scroll wheel** to adjust in 0.1-cell increments
   - **Shape Angle**: 0–360° rotation (disabled for circles)
     - **Scroll wheel** to rotate in 5° increments
     - **Right-click** for quick +45° snap
     - Or use quick angle buttons (0°, 45°, 90°, 135°)
   - **Color**: Custom color picker
5. Optionally toggle **Snap to Grid** (follows Dungeondraft global setting)
6. Click to place marker at shape center
7. Shape outline appears with specified radius and rotation

**Shape Angle Behavior:**
- Square: rotates on all 4 corners
- Pentagon/Hexagon/Octagon/Custom: rotates all vertices
- Circle: all rotation controls disabled (circles have no rotation)

---

### Placing Path Markers

**Best for: complex curves, custom boundaries, organic shapes**

Path markers use **interactive sequential placement**:

1. Select **Guide Markers** tool
2. Choose **"Path"** from dropdown
3. Configure color (other settings disabled during placement)
4. **Start placement**: Click on map for first point
   - Point appears in **green** (larger size)
   - Placement mode activates automatically
5. **Add points**: Click to add more points
   - Each new point connects to previous
   - Points shown in **red** (semi-transparent)
   - **White dashed line** previews next segment to cursor
6. **Finish placement**:
   - **Right-click**: Finish as open path (minimum 2 points)
   - **Click near first point**: Close path into loop (minimum 3 points)
     - Pulsing green circle indicates "close zone"
   - **ESC key**: Cancel and discard all points
7. Path appears in chosen color

**Path Tips:**
- Each point snaps to grid (if enabled)
- Preview line shows exactly where next segment will go
- Coordinate display (if enabled) shows cumulative distance from start
- No maximum point limit (tested up to 100+ points)
- Can't edit path after placement - use undo (Ctrl+Z) to remove and start over

---

### Placing Arrow Markers

**Best for: direction indicators, flow, connections**

Arrow markers use **2-point placement** with automatic completion:

1. Select **Guide Markers** tool
2. Choose **"Arrow"** from dropdown
3. Configure **Arrow head**:
   - **Head Length**: 10-200 pixels (arrowhead line length)
   - **Head Angle**: 10-60 degrees (wing angle)
4. Configure **Color**
5. **Start placement**: Click for arrow start point
   - Point appears in **green**
   - White preview line follows cursor with arrowhead preview
6. **Complete arrow**: Click for end point
   - Arrow automatically finishes (no third click needed)
   - Arrowhead appears at end point
   - Arrow points from start → end
7. **Cancel placement** (before second point):
   - **Right-click** or **ESC key**

**Arrow Tips:**
- Both points snap to grid (if enabled)
- Preview shows exact arrowhead appearance
- Arrowhead scales with camera zoom for visibility
- Can adjust head length/angle before or between placements
- Coordinate display shows start and end distances

---

### Managing Markers

#### Deleting Markers

**Method 1: Right-Click (Quick)**
- Right-click near any marker to delete instantly
- Works when NOT in path/arrow placement mode
- Fully undoable (Ctrl+Z)

**Method 2: Delete Mode (Precise)**
1. Enable **"Delete Markers Mode"** checkbox
2. All other options disabled, preview hidden
3. Click near marker (within 20 pixels of center) to delete
4. Disable checkbox to return to placement mode

**Method 3: Delete All**
- Click **"Delete All Markers"** button
- Removes all markers instantly
- Fully undoable (Ctrl+Z)

#### Undo/Redo

- **Ctrl+Z**: Undo last operation (placement, deletion, delete all)
- **Ctrl+Y** (or Ctrl+Shift+Z): Redo operation
- History limit: 100 operations per type
- Full state restoration (color, angle, all parameters)

#### Notes

- **Markers cannot be moved** - delete and recreate to reposition
- **Use preview** to verify placement before clicking
- **Right-click deletion** doesn't work during path/arrow placement

---

### External API

`GuidesLinesApi` is available to other mods via `self.Global.API.GuidesLinesApi` after a map is loaded.

**Check readiness:**
```gdscript
if self.Global.API.has("GuidesLinesApi") and self.Global.API.GuidesLinesApi.is_ready():
    var gl = self.Global.API.GuidesLinesApi
```

**Or listen for late registration:**
```gdscript
self.Global.API.connect("api_registered", self, "_on_api_registered")
func _on_api_registered(api_id, _api):
    if api_id == "GuidesLinesApi":
        var gl = self.Global.API.GuidesLinesApi
```

**Placement:**
```gdscript
var id = gl.place_line_marker(Vector2(512, 512), 45.0)            # Line at 45°
var id = gl.place_shape_marker(Vector2(512, 512), "Hexagon", 3.0) # Hexagon r=3
var id = gl.place_shape_marker(pos, "Custom", 2.0, 0.0, 8)        # Octagon (custom)
var id = gl.place_path_marker([p1, p2, p3], true)                  # Closed path
var id = gl.place_arrow_marker(p1, p2, 60.0, 30.0)                # Arrow
```

**Queries:**
```gdscript
var nearest = gl.find_nearest_marker_by_geometry(cursor_pos, 100.0)
# Returns: { id, marker_type, position, point (closest geometry point), distance, ... }

var hit = gl.find_line_intersection(line_a, line_b, cursor_pos, 80.0)
# Returns: { point, distance, on_positive, marker_id, marker_type, ... }
```

`get_shape_state()` returns a fresh snapshot containing `ready`,
`active_shape_radius` (grid cells), `active_shape_angle` (degrees),
`active_shape_sides` and `active_color`. Before initialization it returns
`{"ready": false}`. It is suitable for polling shape previews each frame;
consumers supporting older versions can fall back to `get_tool_state()` when
`has_method("get_shape_state")` is false. Continue calling `set_shape_preview()`
every frame to keep a preview alive, and `clear_shape_preview()` when leaving it.

**Signals:**
```gdscript
gl.connect("marker_placed", self, "_on_marker_placed")  # (marker_id, position)
gl.connect("marker_deleted", self, "_on_marker_deleted") # (marker_id)
```

---

## Overlay Features

#### Proximity Guides (Cross Overlays)

**When enabled, shows guide lines when cursor approaches a marker:**

- Vertical and horizontal lines through marker center
- Appears when cursor within configurable distance
- Helps align new elements with existing markers
- Toggle: **"Show Cross Guides"** checkbox

#### Permanent Center Guides

**Fixed guide lines through map center:**

- **Permanent Vertical Guide**: Vertical line through center
- **Permanent Horizontal Guide**: Horizontal line through center
- Always visible when enabled (not tied to cursor)
- Great for symmetry and map center reference
- Toggle independently in **Guide Overlays** section

#### Grid Coordinates

**Display coordinate markers on guide lines:**

- Shows grid position at intersections
- Numbers indicate distance from marker center in cells
- Red center dot marks reference point (0, 0)
- Automatically enables "Snap to Grid" when activated
- Toggle: **"Show Grid Coordinates"** checkbox
- Works with custom_snap modified grids

**Smart Behavior:**
- Auto-disables when no guide lines active
- Updates dynamically as markers are added/removed

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| **`9`** (default, configurable) | Activate Guide Markers tool |
| **ESC** | Cancel path/arrow placement |
| **Right-Click** | Finish path (open) / Cancel arrow / Delete marker (when not placing) / Shape +45° (before placement) |
| **Ctrl+Z** | Undo last operation |
| **Ctrl+Y** / **Ctrl+Shift+Z** | Redo operation |
| **Scroll Wheel** (Line, over Angle) | Adjust angle ±5° |
| **Scroll Wheel** (Shape, in viewport) | Rotate shape ±5° |
| **Alt + Scroll Wheel** (Shape) | Adjust radius ±0.1 cells |

---

## Technical Details

### Architecture

**Clean separation of concerns:**

1. **GuidesLines.gd** — Main coordinator
   - Registers with Dungeondraft and _Lib API
   - Creates tools and manages lifecycle
   - Handles save/load operations
   - Registers `GuidesLinesApi` with `_Lib`'s ApiApi

2. **GuidesLinesTool.gd** — Tool logic
   - Marker creation and storage
   - UI interactions and settings management
   - Path/Arrow placement state machines
   - Custom_snap integration
   - History record creation
   - Public bridge methods for external API (`api_place_marker`, `api_delete_marker_by_id`)

3. **MarkerOverlay.gd** — Rendering engine
   - Draws all marker types and guide lines
   - Handles preview rendering
   - Path/Arrow interactive previews
   - Mouse wheel / RMB input handling

4. **GuidesLinesRender.gd** — Drawing primitives
   - Centralised static helpers for lines, circles, polygons, arrows, text
   - All overlays delegate drawing calls here

5. **GeometryUtils.gd** — Math library
   - Polygon/vertex generation, line clipping, ray intersection
   - Closest-point and line–geometry intersection helpers used by the API

6. **GuideMarker.gd** — Data model
   - Stores marker type and all parameters
   - Serialization for save/load
   - Caches computed geometry (invalidated on property change)

7. **GuidesLinesApi** — External API
   - Signals: `marker_placed`, `marker_deleted`, `all_markers_deleted`, `settings_changed`
   - Placement: `place_line_marker()`, `place_shape_marker()`, `place_path_marker()`, `place_arrow_marker()`
   - Explicit plain Shape: `place_shape_marker_plain(position, radius, angle, sides, color)`
     ignores active Conform/Wrap modes without changing the user's mode settings.
   - Deletion: `delete_marker()`, `delete_all_markers()`
   - Compound history: `begin_history_capture()` / `end_history_capture()` capture
     synchronous edits for a caller-owned history record. Reject nested capture,
     never yield between calls, and always end a successful capture, including on
     failure. Undo returned records in reverse order; redo in execution order.
     The caller must record the compound action or roll it back. This addition is
     currently unreleased; detect both methods before starting edits.
   - Queries: `get_markers()`, `get_marker()`, `find_nearest_marker()`, `find_nearest_marker_by_geometry()`, `find_nearest_geometry_point()`, `find_line_intersection()`
   - Settings: `set_cross_guides()`, `set_permanent_vertical/horizontal()`, `get_settings()`

8. **CrossOverlay.gd & PermanentOverlay.gd** — Overlay systems
   - Proximity-based and permanent guides
   - Coordinate display system
   - Grid compatibility layer

### Integration

- **_Lib-1.2.0 API**: Modern `self.Global.API` pattern
- **Logger API**: Professional logging with class-scoped instances
- **HistoryApi**: Full undo/redo with custom record classes
- **ModConfigApi**: Persistent settings panel (Edit → Preferences → Mods)
- **InputMapApi**: Configurable hotkey (Edit → Preferences → Shortcuts)
- **ModRegistry API**: Enhanced mod detection (custom_snap)
- **UpdateChecker**: Automatic GitHub release notifications
- **GuidesLinesApi**: External inter-mod API registered as `self.Global.API.GuidesLinesApi`
- **custom_snap**: Detects and uses custom grid snapping

### Save Format

Markers stored in map file under `guide_markers` key:

```json
{
  "marker_type": "Line|Shape|Path|Arrow",
  "position": {"x": float, "y": float},
  "color": {"r": float, "g": float, "b": float, "a": float},

  // Line-specific
  "angle": float (0-360),
  "mirror": bool,

  // Shape-specific
  "shape_radius": float,
  "shape_subtype": "Circle|Square|Pentagon|Hexagon|Octagon|Custom",
  "shape_angle": float (0-360),
  "shape_sides": int (3-50, used when subtype == "Custom"),

  // Path-specific
  "marker_points": [{"x": float, "y": float}, ...],
  "path_closed": bool,

  // Arrow-specific
  "marker_points": [{"x": float, "y": float}, {"x": float, "y": float}],
  "arrow_head_length": float (10-200),
  "arrow_head_angle": float (10-60)
}
```

### Performance

- Tested with 100+ markers on 4K maps
- Optimized rendering loop
- Efficient coordinate calculations
- Smart preview updates

---

## Troubleshooting

### Mod not appearing
- **Check**: _Lib-1.2.0 installed?
- **Check**: Dungeondraft version ≥ 1.1.1.1?
- **Action**: Restart Dungeondraft completely

### Guide lines not visible
- **Check**: At least one marker placed?
- **Check**: Guide Markers tool active?
- **Action**: Try placing a Line marker at (0, 0)

### Undo not working
- **Check**: _Lib-1.2.0 properly installed?
- **Check**: History limit not exceeded? (100 per type)
- **Action**: Restart Dungeondraft

### Path placement stuck
- **Action**: Press ESC to cancel
- **Action**: Switch to different marker type
- **Check**: Minimum 2 points for open path, 3 for closed

### Custom_snap not detected
- **Check**: custom_snap enabled in Mods menu?
- **Check**: Map created with custom_snap active?
- **Note**: Detection happens once per map load

### Old map won't load
- **Reason**: v1.x maps incompatible with v2.0.0
- **Solution**: Use v1.x mod version for old maps
- **Alternative**: Recreate markers in v2.0.0 (better flexibility!)

---

## Compatibility

### Requirements
- **Dungeondraft**: 1.1.1.1+
- **_Lib**: 1.2.0 (required)

### Optional Mods
- **custom_snap**: Enhanced grid snapping (auto-detected)

### Compatible Mods
- All _Lib-based mods
- Essential Utils
- Minor Utils
- Most Dungeondraft mods

### Known Incompatibilities
- **None** - If you find one, please report on [GitHub Issues](https://github.com/ChosonDev/GuidesLines/issues)

---

## Version History

### v2.4.1 (Current) — 2026-11-04
- Technical maintenance: code cleanup, bug fixes, performance improvements and expanded regression tests.
- Markers, fill regions and marker templates are saved and restored with the map.

See [CHANGELOG.md](CHANGELOG.md) for the complete release history.

### v2.1.0 — 2026-02-21
- 🏗️ Geometry centralised into `GeometryUtils.gd` (Phase 3)
- Internal API helpers extracted; no public signature changes

### v2.0.11 — 2026-02-21
- 🔌 `GuidesLinesApi` external mod API with signals, placement, deletion, spatial queries

### v2.0.10 — 2026-02-19
- ➕ Custom (N-sided) shape subtype (3–50 sides)

### v2.0.9 — 2026-02-19
- 🖱️ Shape mouse controls: scroll = rotate, Alt+scroll = radius, RMB = +45°

### v2.0.8 — 2026-02-19
- ⚙️ Persistent settings via ModConfigApi; configurable hotkey

### v2.0.7 — 2026-02-17
- Removed Snap to Grid checkbox; respects Dungeondraft global snap

### v2.0.6 — 2026-02-17
- Scripts reorganised into subdirectories (`tool/`, `render/`, `overlays/`, `guides/`, `utils/`)

### v2.0.5 — 2026-02-17
- `GuidesLinesRender.gd` centralises all drawing primitives

### v2.0.4 — 2026-02-17
- `GeometryUtils.gd` created; polygon, clipping, ray math consolidated

### v2.0.3 — 2026-02-16
- ⚡ Geometry caching; expensive trig removed from render loop

### v2.0.0 — 2026-02-15
- 🎉 Complete redesign: Line, Shape, Path, Arrow markers
- ⚠️ Breaking: v1.x maps incompatible

### v1.0.10 — 2026-02-04
- UpdateChecker + HistoryApi

### v1.0.9 — 2026-02-03
- _Lib-1.2.0 compatibility

[Full changelog](CHANGELOG.md)

---

## Known Limitations

- Markers cannot be moved after placement
- Maximum tested: ~100 markers (system-dependent)
- Delete mode requires clicking within 20px of center
- No automated v1.x → v2.0.0 migration

---

## Tips & Best Practices

### For Line Markers
- Use 0°/90° for axis-aligned grids
- Use 45°/135° for diagonal perspectives
- Enable Mirror for symmetrical designs
- Adjust angle with mouse wheel while hovering

### For Shape Markers
- Use circles for room templates
- Use hexagons for hex-grid overlays
- Rotate squares to create diamond guides
- **Scroll wheel** to rotate quickly; **Alt+scroll** to resize
- **Right-click** for instant +45° snap rotation
- Use **Custom** subtype for any regular polygon (3–50 sides)

### For Path Markers
- Place fewer points for smooth curves
- Use many points for complex shapes
- Close paths for area boundaries
- Right-click to finish, ESC to cancel

### For Arrow Markers
- Use for one-way passages
- Great for trap triggers
- Indicate flow direction in rivers
- Adjust head angle for different arrow styles

### General Tips
- Use "Snap to Grid" for precision
- Enable coordinates for exact measurements
- Use preview to verify before placing
- Remember: Ctrl+Z is your friend!
- Save your map frequently

---

## Author

**Choson**  
Created for the Dungeondraft map-making community.

### Links
- [GitHub Repository](https://github.com/ChosonDev/GuidesLines)
- [Issue Tracker](https://github.com/ChosonDev/GuidesLines/issues)
- [Releases](https://github.com/ChosonDev/GuidesLines/releases)

### Special Thanks
- **CreepyCre** (MegalomaniacMegalodon) for the [_Lib framework](https://github.com/CreepyCre/_Lib)
- **Lievven** for the custom_snap mod inspiration
- The Dungeondraft modding community

---

## License

Free to use and modify for personal and commercial projects.

**MIT License** - See [LICENSE.md](LICENSE.md) for details.

---

## Support

### Getting Help
1. Check this README's [Troubleshooting](#troubleshooting) section
2. Search existing [GitHub Issues](https://github.com/ChosonDev/GuidesLines/issues)
3. Create a new issue with:
   - Dungeondraft version
   - _Lib version
   - Steps to reproduce problem
   - Error messages (if any)

### Feature Requests
Open an issue with tag `enhancement` describing:
- Desired feature
- Use case
- Why existing features don't solve it

---

**Happy Mapping! 🗺️**


extends Reference

# GuidesLinesTool - Tool for managing guide markers
# Stores markers internally and draws them via overlay

const CLASS_NAME = "GuidesLinesTool"
const GeometryUtils = preload("../utils/GeometryUtils.gd")
const GuidesLinesHistory = preload("GuidesLinesHistory.gd")
const GuidesLinesToolUI = preload("GuidesLinesToolUI.gd")
const GuidesLinesPlacement = preload("GuidesLinesPlacement.gd")
const GuidesLinesFill = preload("GuidesLinesFill.gd")

# ============================================================================
# VARIABLES
# ============================================================================

var parent_mod = null
var GuideMarkerClass = null
var MarkerOverlayClass = null
var LOGGER = null  # Logger instance (passed from parent mod)

# Cached references (passed from main mod)
var cached_world = null
var cached_worldui = null
var cached_camera = null
var cached_snappy_mod = null  # Custom_snap mod reference (if available)

# Tool state
var is_enabled = false
var show_coordinates = false  # Show grid coordinates on new markers
var delete_mode = false  # Delete mode - click to remove markers
var move_mode = false   # Move Mode — drag existing markers to new position
# fill mode is active when active_marker_type == MARKER_TYPE_FILL

# Move mode drag state
var _move_selected_marker = null   # Marker currently being dragged
var _move_drag_offset = Vector2.ZERO  # Click offset from marker.position
var _move_drag_pos = Vector2.ZERO     # Current drag position (mouse world pos)

# Marker type system
const MARKER_TYPE_LINE = "Line"
const MARKER_TYPE_SHAPE = "Shape"
const MARKER_TYPE_PATH = "Path"
const MARKER_TYPE_FILL = "Fill"
const MARKER_TYPE_TEMPLATE = "Template"

# Shape preset labels (UI-only — used to set initial sides/angle when a preset is selected)
const SHAPE_CIRCLE = "Circle"
const SHAPE_SQUARE = "Square"
const SHAPE_PENTAGON = "Pentagon"
const SHAPE_HEXAGON = "Hexagon"
const SHAPE_OCTAGON = "Octagon"
const SHAPE_CUSTOM = "Custom"

var active_marker_type = MARKER_TYPE_LINE  # Current selected marker type

# Active marker settings (for new markers)
var active_angle = 0.0
var active_shape_radius = 1.0  # Shape radius in grid cells (circumradius)
var active_shape_angle = 0.0  # Shape rotation angle in degrees
var active_shape_sides = 64  # Number of polygon sides (64 = Circle approximation on start)
var active_shape_size_mode = "radius"  # "radius" or "side" — UI-only, does not persist on marker
var active_shape_side = 1.0            # Side length in grid cells (used only when size_mode == "side")
var active_path_end_arrow = false  # Draw arrowhead at last point of path
var active_arrow_head_length = 50.0  # Arrow head length in pixels
var active_arrow_head_angle = 30.0  # Arrow head angle in degrees
var active_color = Color(0, 0.7, 1, 1)
var active_mirror = false
var merge_shapes = false       # Merge intersecting shape markers on placement (union outline)
var conforming_mode = false  # Conforming mode — new shape dents existing shapes' outlines (Difference applied to others + place B)
var wrapping_mode = false    # Wrapping mode — new shape is dented by existing shapes (Difference applied to new shape + place B)
var difference_mode = false  # Difference mode — don't place new shape; fill overlap into existing markers
var cut_mode = false        # Cut mode — clip existing shapes with the new shape outline and convert them to Path markers

# Template mode state
var templates = []                # Array of { "id": int, "name": String, "data": Dictionary }
var template_next_id = 0          # Counter for auto-naming templates
var active_template_index = -1    # Index of selected template in templates[] (-1 = none)
var template_capture_mode = false # When true, next map click captures a marker as a template
var template_rotation_offset = 0.0  # Ephemeral rotation offset (degrees); reset on template select/re-select

# Type-specific settings storage (each type stores its own parameters)
var type_settings = {
	"Line": {
		"angle": 0.0,
		"mirror": false
	},
	"Shape": {
		"radius": 1.0,
		"angle": 0.0,
		"sides": 64,
		"size_mode": "radius",
		"side": 1.0
	},
	"Path": {
		"end_arrow": false,
		"head_length": 50.0,
		"head_angle": 30.0
	}
}

# Saved key -> active property and legacy fallback when a field is absent.
const TYPE_SETTING_FIELDS = {
	"Line": {"angle": ["active_angle", 0.0], "mirror": ["active_mirror", false]},
	"Shape": {"radius": ["active_shape_radius", 1.0], "angle": ["active_shape_angle", 0.0],
		"sides": ["active_shape_sides", 6], "size_mode": ["active_shape_size_mode", "radius"],
		"side": ["active_shape_side", 1.0]},
	"Path": {"end_arrow": ["active_path_end_arrow", false],
		"head_length": ["active_arrow_head_length", 50.0], "head_angle": ["active_arrow_head_angle", 30.0]}
}

# Default values
const DEFAULT_SHAPE_SIDES = 6  # Fallback for missing "sides" key in saved/loaded marker data

# Markers storage
var markers = []  # Array of GuideMarker instances
var markers_lookup = {} # Dictionary { id: GuideMarker } for O(1) access
var next_id = 0

# Fill storage (Fill Mode)
var fills = []          # Array of FillMarker instances
var fills_lookup = {}   # Dictionary { id: FillMarker } for O(1) access
var next_fill_id = 0
var FillMarkerClass = null  # Injected by GuidesLines.gd after start()

# UI References
var tool_panel = null
var overlay = null  # Node2D for drawing
var ui = null  # GuidesLinesToolUI instance
var placement = null  # GuidesLinesPlacement instance
var _fill_handler = null  # GuidesLinesFill instance

# Path placement state
var path_placement_active = false  # Whether we're in path placement mode
var path_temp_points = []  # Temporary storage for points being placed
var path_preview_point = null  # Current mouse position for line preview

# API-requested one-frame preview (set by GuidesLinesApi.set_shape_preview, auto-cleared after one render)
var _api_preview = {}
var _api_preview_frame = -1


# Initialize tool with reference to parent mod
func _init(mod):
	parent_mod = mod
	# Note: LOGGER will be set by parent mod after initialization
	ui = GuidesLinesToolUI.new(self)
	placement = GuidesLinesPlacement.new(self)
	_fill_handler = GuidesLinesFill.new(self)

# Enable tool when selected in Dungeondraft
func Enable():
	is_enabled = true
	if LOGGER:
		LOGGER.info("Guide Markers tool ENABLED")

# Disable tool when deselected
func Disable():
	is_enabled = false
	if LOGGER:
		LOGGER.info("Guide Markers tool DISABLED")

# Main update loop - manages overlay and drawing
func Update(_delta):
	if not is_enabled:
		# Still ensure overlay exists for API-placed markers
		if not overlay and cached_worldui:
			_create_overlay()
		return

	# Create overlay if needed
	if not overlay and cached_worldui:
		_create_overlay()

	# In Side size mode, keep active_shape_radius in sync with the current hex
	# edge correction.  This handles the case where the user switches the
	# snappy_mod between Corner and Edge without touching the Side spinbox —
	# no signal is emitted by snappy_mod, so we poll here every frame instead.
	if active_marker_type == MARKER_TYPE_SHAPE and active_shape_size_mode == "side":
		var previous_radius = active_shape_radius
		recompute_radius_from_side()
		if abs(active_shape_radius - previous_radius) > 0.0001:
			if ui:
				ui._update_shape_radius_spinbox()
			if overlay:
				overlay.update()

	# Overlay manages its own update based on changes
	# No need to force update every frame

# Create overlay node for drawing markers and guide lines
func _create_overlay():
	if LOGGER:
		LOGGER.info("Creating MarkerOverlay...")
	overlay = MarkerOverlayClass.new()
	overlay.tool = self
	cached_worldui.add_child(overlay)
	overlay.set_z_index(100)
	if LOGGER:
		LOGGER.info("MarkerOverlay created successfully")

# Helper: record undo/redo action if HistoryApi is available.
# max_count: maximum number of records kept in history (0 = unlimited)
func _record_history(record, max_count: int = 100) -> void:
	if parent_mod.Global.API and parent_mod.Global.API.has("HistoryApi"):
		parent_mod.Global.API.HistoryApi.record(record, max_count)

# Place a new marker at the specified position
# Applies grid snapping and active custom line settings
func place_marker(pos):
	# Template mode: place a copy of the selected template at this position
	if active_marker_type == MARKER_TYPE_TEMPLATE:
		_place_template_marker(pos)
		return

	# Special handling for Path type
	if active_marker_type == MARKER_TYPE_PATH:
		_handle_path_placement(pos)
		return

	var final_pos = pos
	if parent_mod.Global.Editor.IsSnapping:
		final_pos = snap_position_to_grid(pos)
	if active_marker_type == MARKER_TYPE_SHAPE and (difference_mode or cut_mode or merge_shapes):
		if _try_apply_non_placing_shape_mode(_build_shape_descriptor_at(final_pos), final_pos):
			return

	var marker_data = {
		"position": final_pos,
		"marker_type": active_marker_type,
		"color": active_color,
		"id": next_id
	}
	
	# Add type-specific parameters
	if active_marker_type == MARKER_TYPE_LINE:
		marker_data["show_coordinates"] = show_coordinates
		marker_data["angle"] = active_angle
		marker_data["mirror"] = active_mirror
	elif active_marker_type == MARKER_TYPE_SHAPE:
		marker_data["shape_radius"] = active_shape_radius
		marker_data["shape_angle"] = active_shape_angle
		marker_data["shape_sides"] = active_shape_sides
	
	# Snapshot primitives of markers that would be modified BEFORE placement,
	# so PlaceMarkerRecord can restore them on undo.
	var clip_snaps = {}
	if active_marker_type == MARKER_TYPE_SHAPE and conforming_mode:
		clip_snaps = _snapshot_potential_clip_targets(final_pos)

	# Execute the action first
	_do_place_marker(marker_data)
	next_id += 1
	
	# Then add to history if available
	if LOGGER:
		LOGGER.debug("Adding marker placement to history (id: %d)" % [marker_data["id"]])
	_record_history(GuidesLinesHistory.PlaceMarkerRecord.new(self, marker_data, clip_snaps))


# ============================================================================
# MULTI-POINT PLACEMENT (delegates to GuidesLinesPlacement)
# ============================================================================

func _handle_path_placement(pos): placement.handle_path_placement(pos)
func _finalize_path_marker(closed): placement.finalize_path_marker(closed)
func _cancel_path_placement(): placement.cancel_path_placement()

# ============================================================================
# TEMPLATE MODE
# ============================================================================

# Start template capture — next click on a map marker saves it as a template.
func start_template_capture() -> void:
	template_capture_mode = true
	if ui:
		ui._update_template_capture_button(true)
	if overlay:
		overlay.update()

# Capture the marker nearest to [pos] and store it as a new template.
func capture_marker_as_template(pos: Vector2) -> void:
	template_capture_mode = false
	if ui:
		ui._update_template_capture_button(false)

	var marker = find_marker_at(pos, 20.0)
	if not marker:
		if overlay:
			overlay.update()
		return

	var tmpl_id = template_next_id
	template_next_id += 1

	# Snapshot all marker parameters
	var data = {
		"marker_type":       marker.marker_type,
		"color":             marker.color,
		"angle":             marker.angle,
		"mirror":            marker.mirror,
		"shape_radius":      marker.shape_radius,
		"shape_angle":       marker.shape_angle,
		"shape_sides":       marker.shape_sides,
		"path_closed":       marker.path_closed,
		"path_end_arrow":    marker.path_end_arrow,
		"arrow_head_length": marker.arrow_head_length,
		"arrow_head_angle":  marker.arrow_head_angle,
	}

	if marker.marker_type == MARKER_TYPE_LINE:
		data["show_coordinates"] = marker.show_coordinates

	# For Path: store points relative to the first point so the shape is position-independent
	if marker.marker_type == MARKER_TYPE_PATH and marker.marker_points.size() > 0:
		var origin = marker.marker_points[0]
		var rel_points = []
		for pt in marker.marker_points:
			rel_points.append(pt - origin)
		data["relative_points"] = rel_points

	# For Shape: if the marker was modified by Merge/Conforming/Difference/etc.,
	# its real geometry lives in cached_draw_data["primitives"], not in shape_radius/angle/sides.
	# Store segments in relative coords so they can be re-placed anywhere.
	if marker.marker_type == MARKER_TYPE_SHAPE:
		var prims = marker.get_primitives()
		if prims.size() > 0:
			var rel_prims = []
			for seg in prims:
				rel_prims.append({"a": seg.a - marker.position, "b": seg.b - marker.position})
			data["shape_primitives"] = rel_prims

	templates.append({
		"id":   tmpl_id,
		"name": "Template %d" % [tmpl_id + 1],
		"data": data,
	})

	if ui:
		ui.rebuild_template_list()
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Captured marker as template (id: %d, type: %s)" % [tmpl_id, marker.marker_type])

# Select template by index (sets as active for placement).
func select_template(index: int) -> void:
	active_template_index = index
	template_rotation_offset = 0.0  # Reset ephemeral rotation on every (re-)select
	if overlay:
		overlay.update()

# Delete template by index.
func delete_template(index: int) -> void:
	if index < 0 or index >= templates.size():
		return
	templates.remove(index)
	if active_template_index >= templates.size():
		active_template_index = templates.size() - 1
		template_rotation_offset = 0.0
	if ui:
		ui.rebuild_template_list()
	if overlay:
		overlay.update()

# Adjust ephemeral rotation via mouse wheel.
func adjust_template_rotation_with_wheel(direction: int) -> void:
	if active_template_index < 0 or active_template_index >= templates.size():
		return
	var tmpl_type = templates[active_template_index]["data"].get("marker_type", "")
	var step = 1.0 if tmpl_type == MARKER_TYPE_LINE else 5.0
	template_rotation_offset = fposmod(template_rotation_offset + direction * step, 360.0)
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Template rotation offset adjusted: %.1f°" % [template_rotation_offset])

# Rotate template by 45° via RMB shortcut.
func rotate_template_45() -> void:
	if active_template_index < 0 or active_template_index >= templates.size():
		return
	template_rotation_offset = fposmod(template_rotation_offset + 45.0, 360.0)
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Template rotated 45° via RMB: offset = %.1f°" % [template_rotation_offset])

# Build a shape descriptor from the currently selected template at [pos],
# applying the ephemeral rotation offset. Handles both primitive-based
# (Merge/Conforming/Difference-modified) and standard parametric templates.
func _build_shape_descriptor_from_template(pos: Vector2) -> Dictionary:
	if active_template_index < 0 or active_template_index >= templates.size():
		return {}
	var cell_size = _get_grid_cell_size()
	if cell_size == null:
		return {}
	var tmpl_data = templates[active_template_index]["data"]
	var rot_rad = deg2rad(template_rotation_offset)
	var data = {"position": pos, "shape_radius": tmpl_data.get("shape_radius", 1.0),
		"shape_angle": fposmod(tmpl_data.get("shape_angle", 0.0) + template_rotation_offset, 360.0),
		"shape_sides": tmpl_data.get("shape_sides", DEFAULT_SHAPE_SIDES)}
	if tmpl_data.has("shape_primitives"):
		# Inject modified primitives translated + rotated to the new position
		var abs_prims = []
		for rel_seg in tmpl_data["shape_primitives"]:
			abs_prims.append({
				"type": "seg",
				"a": pos + rel_seg["a"].rotated(rot_rad),
				"b": pos + rel_seg["b"].rotated(rot_rad),
			})
		data["shape_primitives"] = abs_prims
	return _get_shape_descriptor_from_marker_data(data)

# Place a new marker using the currently selected template at [pos].
func _place_template_marker(pos: Vector2) -> void:
	if active_template_index < 0 or active_template_index >= templates.size():
		return

	var tmpl_data = templates[active_template_index]["data"]
	var final_pos = pos
	if parent_mod.Global.Editor.IsSnapping:
		final_pos = snap_position_to_grid(pos)

	# ── SHAPE OVERLAP MODES ──────────────────────────────────────────────────
	if tmpl_data["marker_type"] == MARKER_TYPE_SHAPE:
		var tmpl_desc = _build_shape_descriptor_from_template(final_pos)
		if tmpl_desc.empty():
			return

		if _try_apply_non_placing_shape_mode(tmpl_desc, final_pos):
			return

	# ── BUILD MARKER DATA ────────────────────────────────────────────────────
	var marker_data = {
		"position":    final_pos,
		"marker_type": tmpl_data["marker_type"],
		"color":       tmpl_data["color"],
		"id":          next_id,
	}

	match tmpl_data["marker_type"]:
		MARKER_TYPE_LINE:
			marker_data["show_coordinates"] = tmpl_data.get("coordinates", tmpl_data.get("show_coordinates", false))
			var eff_angle = fposmod(tmpl_data.get("angle", 0.0) + template_rotation_offset, 360.0)
			marker_data["angle"]  = eff_angle
			marker_data["mirror"] = tmpl_data.get("mirror", false)
		MARKER_TYPE_SHAPE:
			var eff_angle = fposmod(tmpl_data.get("shape_angle", 0.0) + template_rotation_offset, 360.0)
			marker_data["shape_radius"] = tmpl_data.get("shape_radius", 1.0)
			marker_data["shape_angle"]  = eff_angle
			marker_data["shape_sides"]  = tmpl_data.get("shape_sides",  DEFAULT_SHAPE_SIDES)
		MARKER_TYPE_PATH:
			var rel_pts = tmpl_data.get("relative_points", [Vector2.ZERO])
			var rot_rad = deg2rad(template_rotation_offset)
			var abs_pts = []
			for rp in rel_pts:
				abs_pts.append(final_pos + rp.rotated(rot_rad))
			marker_data["marker_points"]     = abs_pts
			marker_data["path_closed"]       = tmpl_data.get("path_closed",       false)
			marker_data["path_end_arrow"]    = tmpl_data.get("path_end_arrow",    false)
			marker_data["arrow_head_length"] = tmpl_data.get("arrow_head_length", 50.0)
			marker_data["arrow_head_angle"]  = tmpl_data.get("arrow_head_angle",  30.0)

	# Store absolute template geometry so initial placement and redo share it.
	if tmpl_data["marker_type"] == MARKER_TYPE_SHAPE and tmpl_data.has("shape_primitives"):
		marker_data["shape_primitives"] = []
		var rot_rad = deg2rad(template_rotation_offset)
		for seg in tmpl_data["shape_primitives"]:
			marker_data["shape_primitives"].append({
				"type": "seg", "a": final_pos + seg.a.rotated(rot_rad),
				"b": final_pos + seg.b.rotated(rot_rad)})

	var clip_snaps = {}
	if tmpl_data["marker_type"] == MARKER_TYPE_SHAPE:
		var tmpl_desc = _build_shape_descriptor_from_template(final_pos)
		if conforming_mode and not tmpl_desc.empty():
			clip_snaps = _snapshot_potential_clip_targets_by_desc(tmpl_desc)

	_do_place_marker(marker_data)
	next_id += 1

	_record_history(GuidesLinesHistory.PlaceMarkerRecord.new(self, marker_data, clip_snaps))

	if LOGGER:
		LOGGER.debug("Placed template marker (template: %d, type: %s, pos: %s)" % [
			active_template_index, marker_data["marker_type"], str(final_pos)])

# ============================================================================
# API BRIDGE METHODS
# Called by GuidesLinesApi to avoid exposing inner HistoryRecord classes
# ============================================================================

# Place a marker from the external API (handles history recording internally)
func api_place_marker(marker_data: Dictionary) -> void:
	var clip_snaps = {}
	if marker_data.get("marker_type") == MARKER_TYPE_SHAPE and conforming_mode:
		clip_snaps = _snapshot_potential_clip_targets_by_desc(_get_shape_descriptor_from_marker_data(marker_data))
	_do_place_marker(marker_data)
	next_id += 1
	_record_history(GuidesLinesHistory.PlaceMarkerRecord.new(self, marker_data, clip_snaps))

## Bridge: build a shape descriptor from a marker_data Dictionary without
## touching the tool's active shape parameters.
func _get_shape_descriptor_from_marker_data(marker_data: Dictionary) -> Dictionary:
	var cell_size = _get_grid_cell_size()
	if cell_size == null:
		return {}
	var points
	if marker_data.has("shape_primitives"):
		points = GeometryUtils.chain_segments_to_polygon(marker_data["shape_primitives"])
	else:
		points = GeometryUtils.calculate_polygon_vertices(marker_data["position"],
			marker_data.get("shape_radius", active_shape_radius) * min(cell_size.x, cell_size.y),
			marker_data.get("shape_sides", DEFAULT_SHAPE_SIDES), deg2rad(marker_data.get("shape_angle", 0.0)))
	return {"shape_type": "poly", "points": points} if not points.empty() else {}

## Bridge: snapshot clip targets using an already-built descriptor instead of
## the tool's active shape parameters.  Semantically identical to
## _snapshot_potential_clip_targets but decoupled from active settings.
func _snapshot_potential_clip_targets_by_desc(new_desc: Dictionary) -> Dictionary:
	return _snapshot_overlapping_shapes(new_desc)

func api_place_shape_merge(marker_data: Dictionary) -> Dictionary:
	var merge_desc = _get_shape_descriptor_from_marker_data(marker_data)
	if merge_desc.empty():
		return {}
	var snap = _snapshot_potential_merge_targets(merge_desc)
	if snap.empty():
		return {"affected_markers": [], "absorbed_marker_ids": []}
	var cell_size = _get_grid_cell_size()
	var old_positions = {}
	for mid in snap:
		if markers_lookup.has(mid):
			old_positions[mid] = markers_lookup[mid].position
	var merge_absorbed = _do_apply_merge(merge_desc, marker_data["position"])
	_record_history(GuidesLinesHistory.MergeShapeRecord.new(
		self, merge_desc, marker_data["position"], snap, merge_absorbed))
	# Build the result: the primary survivor + any still-live markers from snap.
	var affected = []
	for mid in snap:
		if not markers_lookup.has(mid):
			continue  # absorbed marker — omit from result
		var m = markers_lookup[mid]
		var desc = _get_shape_descriptor(m, cell_size)
		affected.append({
			"marker_id":    mid,
			"new_polygon":  desc.get("points", []),
			"old_position": old_positions.get(mid, m.position),
			"new_position": m.position,
		})
	return {
		"affected_markers":    affected,
		"absorbed_marker_ids": merge_absorbed,
	}

## API bridge: Place a Shape marker with Conforming mode applied.
## Returns { "marker_id": int, "affected_markers": Array } where each entry is:
##   { marker_id, new_polygon }
## Returns {"marker_id":-1,"affected_markers":[]} on failure.
func api_place_shape_conforming(marker_data: Dictionary) -> Dictionary:
	var cell_size = _get_grid_cell_size()
	if cell_size == null:
		return {"marker_id": -1, "affected_markers": []}
	var new_desc   = _get_shape_descriptor_from_marker_data(marker_data)
	var clip_snaps = _snapshot_potential_clip_targets_by_desc(new_desc)
	var prev_conforming = conforming_mode
	var prev_wrapping = wrapping_mode
	conforming_mode = true
	wrapping_mode = false
	_do_place_marker(marker_data)
	next_id += 1
	conforming_mode = prev_conforming
	wrapping_mode = prev_wrapping
	_record_history(GuidesLinesHistory.PlaceMarkerRecord.new(
		self, marker_data, clip_snaps, true, false))
	var affected = []
	for mid in clip_snaps:
		if not markers_lookup.has(mid):
			continue
		var m = markers_lookup[mid]
		var desc = _get_shape_descriptor(m, cell_size)
		affected.append({
			"marker_id":   mid,
			"new_polygon": desc.get("points", []),
		})
	var new_marker_polygon = []
	if markers_lookup.has(marker_data["id"]):
		var placed = markers_lookup[marker_data["id"]]
		var placed_desc = _get_shape_descriptor(placed, cell_size)
		new_marker_polygon = placed_desc.get("points", [])
	return {
		"marker_id":      marker_data["id"],
		"marker_polygon": new_marker_polygon,
		"affected_markers": affected,
	}

## API bridge: Place a Shape marker with Wrapping mode applied.
## Returns marker_id, dented_by IDs, marker_polygon and affected_markers entries
## {marker_id, new_polygon} for the unchanged shapes that caused dents.
## Returns marker_id=-1 and empty arrays on failure.
func api_place_shape_wrapping(marker_data: Dictionary) -> Dictionary:
	var cell_size = _get_grid_cell_size()
	if cell_size == null:
		return {"marker_id": -1, "dented_by": [], "marker_polygon": [], "affected_markers": []}
	# Identify which existing shapes would cause dents (pre-placement overlap check).
	var tmp_desc = _get_shape_descriptor_from_marker_data(marker_data)
	var dented_by_ids = []
	var affected = []
	if not tmp_desc.empty():
		for m in markers:
			if m.marker_type != MARKER_TYPE_SHAPE:
				continue
			var other_desc = _get_shape_descriptor(m, cell_size)
			if not other_desc.empty() and _shapes_overlap(other_desc, tmp_desc):
				dented_by_ids.append(m.id)
				affected.append({"marker_id": m.id, "new_polygon": other_desc.points.duplicate()})
	var prev_wrapping = wrapping_mode
	var prev_conforming = conforming_mode
	wrapping_mode = true
	conforming_mode = false
	_do_place_marker(marker_data)
	next_id += 1
	wrapping_mode = prev_wrapping
	conforming_mode = prev_conforming
	_record_history(GuidesLinesHistory.PlaceMarkerRecord.new(
		self, marker_data, {}, false, true))
	var final_polygon = []
	if markers_lookup.has(marker_data["id"]):
		var placed = markers_lookup[marker_data["id"]]
		var final_desc = _get_shape_descriptor(placed, cell_size)
		final_polygon = final_desc.get("points", [])
	return {
		"marker_id":      marker_data["id"],
		"dented_by":      dented_by_ids,
		"affected_markers": affected,
		"marker_polygon": final_polygon,
	}

## API bridge: Apply Difference mode at the shape described by marker_data.
## No new marker is created — existing Shape markers get a hole punched in them.
## Returns { "affected_markers": Array } where each entry is:
##   { marker_id, new_polygon }
## Returns {} on internal failure.
func api_apply_shape_difference(marker_data: Dictionary) -> Dictionary:
	var diff_desc = _get_shape_descriptor_from_marker_data(marker_data)
	if diff_desc.empty():
		return {}
	var cell_size = _get_grid_cell_size()
	var snap = _take_difference_snapshot(diff_desc)
	_do_apply_difference(diff_desc)
	_record_history(GuidesLinesHistory.DifferenceRecord.new(self, diff_desc, snap))
	var affected = []
	for mid in snap:
		if not markers_lookup.has(mid):
			continue
		var m = markers_lookup[mid]
		var desc = _get_shape_descriptor(m, cell_size)
		affected.append({
			"marker_id":   mid,
			"new_polygon": desc.get("points", []),
		})
	return {"affected_markers": affected}

# Delete a marker by id from the external API (handles history recording internally)
# Returns true if the marker was found and deleted
func api_delete_marker_by_id(marker_id: int) -> bool:
	if not markers_lookup.has(marker_id):
		return false
	var marker = markers_lookup[marker_id]
	var index = markers.find(marker)
	if index == -1:
		return false
	var marker_data = marker.Save()
	_do_delete_marker(index)
	_record_history(GuidesLinesHistory.DeleteMarkerRecord.new(self, marker_data, index))
	return true

# Delete all markers from the map
func delete_all_markers():
	if markers.size() == 0:
		return
	
	# Save state before deletion
	var saved_markers = []
	for marker in markers:
		saved_markers.append(marker.Save())
	
	# Execute the action first
	_do_delete_all()
	
	# Then add to history if available
	_record_history(GuidesLinesHistory.DeleteAllMarkersRecord.new(self, saved_markers))

func _do_delete_all():
	markers = []
	markers_lookup = {} # Clear lookup
	update_ui()
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("All markers deleted")
	# Notify external API listeners
	if parent_mod.guides_lines_api:
		parent_mod.guides_lines_api._notify_all_markers_deleted()

func _undo_delete_all(saved_markers):
	for marker_data in saved_markers:
		var marker = GuideMarkerClass.new()
		marker.Load(marker_data)
		marker.update_opacity(_current_opacity())
		markers.append(marker)
		markers_lookup[marker.id] = marker # Add to lookup
		if marker.id >= next_id:
			next_id = marker.id + 1
	update_ui()
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Restored %d markers" % [saved_markers.size()])

# Delete marker at specific position (within threshold)
func delete_marker_at_position(pos, threshold = 20.0):
	var marker = find_marker_at(pos, threshold)
	if marker == null:
		return false
	var index = markers.find(marker)
	var marker_data = marker.Save()
	_do_delete_marker(index)
	_record_history(GuidesLinesHistory.DeleteMarkerRecord.new(self, marker_data, index))
	return true

func _do_delete_marker(index):
	if index < markers.size():
		var marker = markers[index]
		var deleted_id = marker.id
		# Clean up clipping relationships before removing
		markers_lookup.erase(marker.id) # Remove from lookup
		markers.remove(index)
		update_ui()
		if overlay:
			overlay.update()
		if LOGGER:
			LOGGER.debug("Marker deleted at index %d" % [index])
		# Notify external API listeners
		if parent_mod.guides_lines_api:
			parent_mod.guides_lines_api._notify_marker_deleted(deleted_id)

func _undo_delete_marker(marker_data, index):
	var marker = GuideMarkerClass.new()
	marker.Load(marker_data)
	marker.update_opacity(_current_opacity())
	markers.insert(index, marker)
	markers_lookup[marker.id] = marker # Add to lookup
	if marker.id >= next_id:
		next_id = marker.id + 1
	update_ui()
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Marker restored at index %d" % [index])

# Helper functions for HistoryApi - place marker
func _do_place_marker(marker_data):
	var marker = GuideMarkerClass.new()
	marker.set_property("position", marker_data["position"])
	marker.id = marker_data["id"] 
	marker.set_property("marker_type", marker_data["marker_type"])
	marker.color = marker_data["color"]
	marker.update_opacity(_current_opacity())
	marker.set_property("show_coordinates", marker_data.get("coordinates", marker_data.get("show_coordinates", false)))
	
	# Load type-specific parameters
	if marker_data["marker_type"] == MARKER_TYPE_LINE:
		marker.set_property("angle", marker_data.get("angle", 0.0))
		marker.set_property("mirror", marker_data.get("mirror", false))
	elif marker_data["marker_type"] == MARKER_TYPE_SHAPE:
		marker.set_property("shape_radius", marker_data["shape_radius"])
		marker.set_property("shape_angle", marker_data.get("shape_angle", 0.0))
		marker.set_property("shape_sides", marker_data.get("shape_sides", DEFAULT_SHAPE_SIDES))
		if marker_data.has("shape_primitives"):
			marker.set_primitives(marker_data["shape_primitives"].duplicate(true))
	elif marker_data["marker_type"] == MARKER_TYPE_PATH:
		marker.set_property("marker_points", marker_data["marker_points"].duplicate())
		marker.set_property("path_closed", marker_data["path_closed"])
		marker.set_property("path_end_arrow", marker_data.get("path_end_arrow", false))
		if marker_data.get("path_end_arrow", false):
			marker.set_property("arrow_head_length", marker_data.get("arrow_head_length", 50.0))
			marker.set_property("arrow_head_angle", marker_data.get("arrow_head_angle", 30.0))
	
	markers.append(marker)
	markers_lookup[marker.id] = marker # Add to lookup
	# Apply conforming dent to existing markers if the feature is enabled
	if conforming_mode and marker.marker_type == MARKER_TYPE_SHAPE:
		_apply_conforming_to_existing_shapes(marker)
	# Apply wrapping dent to the new marker itself if the feature is enabled
	if wrapping_mode and marker.marker_type == MARKER_TYPE_SHAPE:
		_apply_wrapping_to_new_shape(marker)
	update_ui()
	if overlay:
		overlay.update()
	if LOGGER:
		if marker_data["marker_type"] == MARKER_TYPE_LINE:
			LOGGER.debug("Line marker placed at %s (angle: %.1f°, mirror: %s)" % [
				str(marker_data["position"]),
				marker_data.get("angle", 0.0),
				str(marker_data.get("mirror", false))
			])
		elif marker_data["marker_type"] == MARKER_TYPE_SHAPE:
			LOGGER.debug("Shape marker placed at %s (sides: %d, radius: %.1f cells)" % [
				str(marker_data["position"]),
				marker_data["shape_sides"],
				marker_data["shape_radius"]
			])
		elif marker_data["marker_type"] == MARKER_TYPE_PATH:
			LOGGER.debug("Path marker placed with %d points (closed: %s, end_arrow: %s)" % [
				marker_data["marker_points"].size(),
				str(marker_data["path_closed"]),
				str(marker_data.get("path_end_arrow", false))
			])
	# Notify external API listeners
	if parent_mod.guides_lines_api:
		parent_mod.guides_lines_api._notify_marker_placed(marker_data["id"], marker_data["position"])

func _undo_place_marker(marker_id):
	# Optimized removal using Dictionary lookup
	if markers_lookup.has(marker_id):
		var marker = markers_lookup[marker_id]
		# Clean up clipping relationships contributed by this marker
		markers.erase(marker) # O(n) linear search — acceptable since markers_lookup O(1) already found it
		markers_lookup.erase(marker_id) # O(1)
		
		update_ui()
		if overlay:
			overlay.update()
		if LOGGER:
			LOGGER.debug("Marker placement undone (id: %d)" % [marker_id])
	else:
		if LOGGER:
			LOGGER.warn("Attempted to undo placement of non-existent marker id: %d" % [marker_id])

# Enable/disable coordinate display on new markers
func set_show_coordinates(enabled):
	var changed = show_coordinates != enabled
	show_coordinates = enabled
	if ui:
		ui._set_control_value("CoordinatesCheckbox", enabled, "pressed")
	if changed and parent_mod.guides_lines_api:
		parent_mod.guides_lines_api.emit_signal("settings_changed", "marker_coordinates", enabled)

func set_delete_mode(enabled):
	delete_mode = enabled
	# Delete mode and Fill type are mutually exclusive — reset dropdown to Line.
	if enabled and active_marker_type == MARKER_TYPE_FILL:
		set_marker_type(MARKER_TYPE_LINE)
	# Delete mode and Move mode are mutually exclusive.
	if enabled and move_mode:
		move_mode = false
		_move_selected_marker = null
	# Cancel template capture when entering delete mode
	if enabled and template_capture_mode:
		template_capture_mode = false
		if ui:
			ui._update_template_capture_button(false)
	update_ui_checkboxes_state()
	# Force overlay update to hide/show preview
	if overlay:
		overlay.update()

func set_move_mode(enabled: bool):
	move_mode = enabled
	_move_selected_marker = null
	# Fill regions are not draggable; return to the marker tool as Delete mode does.
	if enabled and active_marker_type == MARKER_TYPE_FILL:
		set_marker_type(MARKER_TYPE_LINE)
	# Move mode and Delete mode are mutually exclusive.
	if enabled and delete_mode:
		delete_mode = false
	# Cancel template capture when entering move mode
	if enabled and template_capture_mode:
		template_capture_mode = false
		if ui:
			ui._update_template_capture_button(false)
	update_ui_checkboxes_state()
	if overlay:
		overlay.update()

# Use the same anchor/outline candidates and tie order as the public query.
func find_marker_at(pos: Vector2, threshold: float = 20.0):
	var hit = find_nearest_geometry(pos, threshold, true)
	return hit.marker if hit != null else null

func find_nearest_geometry(coords: Vector2, radius: float, include_anchor: bool):
	var map_rect = cached_world.WorldRect if cached_world != null else null
	var cell_size = _get_grid_cell_size() if cached_world != null else null

	var nearest_marker = null
	var nearest_dist = radius
	var nearest_point = null   # actual closest Vector2 on the geometry

	for marker in markers:
		# Only the marker query includes the anchor as a candidate.
		var min_dist = marker.position.distance_to(coords) if include_anchor else INF
		var min_point = marker.position
		if marker.marker_type in [MARKER_TYPE_SHAPE, MARKER_TYPE_PATH]:
			var bounds = marker.get_geometry_bounds(map_rect, cell_size)
			# Inclusive borders preserve zero-radius queries and equally near edges.
			if min_dist > nearest_dist and (bounds == null or not bounds.grow(nearest_dist).intersects(Rect2(coords, Vector2.ZERO), true)):
				continue

		match marker.marker_type:
			"Line":
				var draw_data = marker.get_draw_data(map_rect, cell_size)
				if draw_data.has("segments"):
					for seg in draw_data["segments"]:
						var pt = GeometryUtils.closest_point_on_segment(coords, seg[0], seg[1])
						var d = coords.distance_to(pt)
						if d < min_dist or (not include_anchor and d == min_dist):
							min_dist = d
							min_point = pt

			"Shape":
				var draw_data = marker.get_draw_data(map_rect, cell_size)
				if draw_data.has("primitives"):
					for prim in draw_data["primitives"]:
						if prim.type == "seg":
							var pt = GeometryUtils.closest_point_on_segment(coords, prim.a, prim.b)
							var d = coords.distance_to(pt)
							if d < min_dist or (not include_anchor and d == min_dist):
								min_dist = d
								min_point = pt

			"Path":
				var pts = marker.marker_points
				if pts.size() >= 2:
					var pt = GeometryUtils.closest_point_on_polygon_edges(coords, pts, marker.path_closed)
					var d = coords.distance_to(pt)
					if d < min_dist or (not include_anchor and d == min_dist):
						min_dist = d
						min_point = pt

		if min_dist < INF and min_dist <= nearest_dist:
			nearest_dist = min_dist
			nearest_point = min_point
			nearest_marker = marker

	if nearest_marker == null:
		return null
	return {"marker": nearest_marker, "point": nearest_point, "distance": nearest_dist}


# Move [marker] to [new_pos] and record the action in history.
func move_marker(marker, new_pos: Vector2):
	var old_pos = marker.position
	_do_move_marker(marker, new_pos)
	_record_history(GuidesLinesHistory.MoveMarkerRecord.new(self, marker.id, old_pos, new_pos))

# Low-level move — called by move_marker() and by undo/redo.
func _do_move_marker(marker, new_pos: Vector2):
	marker.set_property("position", new_pos)
	if overlay:
		overlay.update()

# ============================================================================
# FILL MODE — ENTRY POINT (called from MarkerOverlay)
# ============================================================================

# Handle a fill click at [pos] (world-space).
# Delegates polygon computation to GuidesLinesFill, then stores the result
# and records it in the undo/redo history.
func handle_fill_click(pos: Vector2) -> void:
	if active_marker_type != MARKER_TYPE_FILL:
		return
	if not FillMarkerClass:
		if LOGGER:
			LOGGER.error("handle_fill_click: FillMarkerClass not injected")
		return

	var fill_data = _fill_handler.handle_fill_click(pos)
	if fill_data.empty():
		return

	_do_place_fill(fill_data)
	next_fill_id += 1
	_record_history(GuidesLinesHistory.PlaceFillRecord.new(self, fill_data))

# ============================================================================
# FILL MODE — CRUD HELPERS
# ============================================================================

# Place a fill from serialised data (used by handle_fill_click and redo).
func _do_place_fill(fill_data: Dictionary) -> void:
	var fill = FillMarkerClass.new()
	fill.Load(fill_data)
	fill.update_opacity(_current_opacity())
	fills.append(fill)
	fills_lookup[fill.id] = fill
	if fill.id >= next_fill_id:
		next_fill_id = fill.id + 1
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Fill placed (id=%d, %d vertices)" % [fill.id, fill.polygon.size()])

# Remove a placed fill (used by undo of PlaceFillRecord).
func _undo_place_fill(fill_id: int) -> void:
	if not fills_lookup.has(fill_id):
		if LOGGER:
			LOGGER.warn("_undo_place_fill: fill id %d not found" % fill_id)
		return
	var fill = fills_lookup[fill_id]
	fills.erase(fill)
	fills_lookup.erase(fill_id)
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Fill placement undone (id=%d)" % fill_id)

# Delete ALL fills (action — called from UI button).
func delete_all_fills() -> void:
	if fills.empty():
		return
	var saved = []
	for fill in fills:
		saved.append(fill.Save())
	_do_delete_all_fills()
	_record_history(GuidesLinesHistory.DeleteAllFillsRecord.new(self, saved))

# Execute delete-all-fills (also used by redo).
func _do_delete_all_fills() -> void:
	fills = []
	fills_lookup = {}
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("All fills deleted")

# Restore fills from saved data (undo of DeleteAllFillsRecord).
func _undo_delete_all_fills(saved_fills: Array) -> void:
	for fill_data in saved_fills:
		var fill = FillMarkerClass.new()
		fill.Load(fill_data)
		fill.update_opacity(_current_opacity())
		fills.append(fill)
		fills_lookup[fill.id] = fill
		if fill.id >= next_fill_id:
			next_fill_id = fill.id + 1
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Restored %d fills" % [saved_fills.size()])


# Update all UI checkboxes based on delete mode
func update_ui_checkboxes_state():
	if ui:
		ui.update_ui_checkboxes_state()

# Return the current global markers opacity (0.0–1.0).
func _current_opacity() -> float:
	return parent_mod.markers_opacity if parent_mod else 1.0

# Refresh cached draw colors on every marker and fill for the given opacity.
# Call this whenever the global opacity setting changes.
func _apply_opacity_to_all(opacity: float) -> void:
	for marker in markers:
		if marker:
			marker.update_opacity(opacity)
	for fill in fills:
		if fill:
			fill.update_opacity(opacity)

# Snap position to grid, using custom_snap mod if available
# Falls back to vanilla Dungeondraft snapping
func snap_position_to_grid(position):
	# Use custom_snap if available
	if cached_snappy_mod and cached_snappy_mod.has_method("get_snapped_position"):
		return cached_snappy_mod.get_snapped_position(position)
	
	# Use vanilla DD snap if custom_snap not available
	if cached_worldui:
		return cached_worldui.GetSnappedPosition(position)
	
	return position


# Get grid cell size (accounting for custom_snap mod if active)
func _get_grid_cell_size():
	if not cached_world:
		return null
	
	# Check if custom_snap is active and use its snap_interval.
	# Direct property access (no .has() guard) — consistent with MarkerOverlay.
	if cached_snappy_mod and cached_snappy_mod.custom_snap_enabled:
		return cached_snappy_mod.snap_interval
	
	# Fallback to vanilla grid cell size
	if not cached_world.Level or not cached_world.Level.TileMap:
		return null
	return cached_world.Level.TileMap.CellSize

# Returns a correction multiplier for side-to-circumradius conversion when the
# active grid is a hex grid in Edge (apothem) mode.
#
# Background: snap_interval always equals what the user sees as "1 grid unit".
# Corner mode → snap_interval = circumradius of the hex cell → correction = 1.0
# Edge   mode → snap_interval = apothem = R_cell × √3/2
#              → R_cell = snap_interval × 2/√3 → correction = 2/√3 ≈ 1.1547
#
# The correction is applied only when:
#   • custom_snap is active
#   • geometry is HEX_V (1) or HEX_H (2)
#   • radial_mode_to_corner == false  (Edge mode)
func _get_hex_edge_correction() -> float:
	if cached_snappy_mod == null or not cached_snappy_mod.custom_snap_enabled:
		return 1.0
	var geom = cached_snappy_mod.active_geometry
	# GEOMETRY enum: SQUARE=0, HEX_V=1, HEX_H=2, ISOMETRIC=3
	if geom != 1 and geom != 2:
		return 1.0
	if cached_snappy_mod.radial_mode_to_corner:
		return 1.0
	return 2.0 / sqrt(3.0)

func recompute_radius_from_side() -> float:
	active_shape_radius = max(0.1, GeometryUtils.side_to_circumradius(active_shape_side, active_shape_sides) * _get_hex_edge_correction())
	type_settings[MARKER_TYPE_SHAPE]["radius"] = active_shape_radius
	return active_shape_radius

# ============================================================================
# SHAPE CLIPPING (Clip Intersecting Shapes feature)
# ============================================================================

# Build a shape descriptor dict for GeometryUtils clip functions.
# Return the current polygon points of [marker] as a shape descriptor.
# For a fresh marker get_draw_data() builds primitives from shape parameters
# (this is the ONLY moment original params are used). For any modified marker
# (after Merge / Cut / Difference) the stored primitives are used directly.
# Always reflects the actual current outline — never re-reads shape params.
# Returns { shape_type, points } or {} if not applicable.
func _get_shape_descriptor(marker, cell_size) -> Dictionary:
	if marker.marker_type != MARKER_TYPE_SHAPE:
		return {}
	# Ensures primitives exist; for fresh markers builds them from shape params
	# (once only — subsequent calls hit the cache).
	marker.get_draw_data(null, cell_size)
	var pts = marker.get_polygon()
	if pts.empty():
		return {}
	return {"shape_type": "poly", "points": pts}

## Build a shape descriptor for a virtual (not-yet-placed) shape
## using current tool settings at [pos].
func _build_shape_descriptor_at(pos: Vector2) -> Dictionary:
	var cell_size = _get_grid_cell_size()
	if cell_size == null:
		return {}
	return _get_shape_descriptor_from_marker_data({"position": pos,
		"shape_radius": active_shape_radius, "shape_angle": active_shape_angle,
		"shape_sides": active_shape_sides})

# Return true if the outlines of two shape descriptors actually intersect.
func _shapes_intersect(desc_a: Dictionary, desc_b: Dictionary) -> bool:
	if desc_a.empty() or desc_b.empty():
		return false
	if desc_a.shape_type == "poly" and desc_b.shape_type == "poly":
		if not GeometryUtils.polygon_intersection_bounds(desc_a.points).intersects(
				GeometryUtils.polygon_intersection_bounds(desc_b.points), true):
			return false
		var n = desc_a.points.size()
		var m = desc_b.points.size()
		for i in range(n):
			var a1 = desc_a.points[i]
			var a2 = desc_a.points[(i + 1) % n]
			for j in range(m):
				var b1 = desc_b.points[j]
				var b2 = desc_b.points[(j + 1) % m]
				if GeometryUtils.segment_segment_intersect(a1, a2, b1, b2) != null:
					return true
		return false
	return false

# Return true if the two shapes have any overlapping area:
# edges intersect OR one shape is fully contained inside the other.
# Used by Difference mode (unlike clip/cut which require actual edge crossings).
func _shapes_overlap(desc_a: Dictionary, desc_b: Dictionary) -> bool:
	if _shapes_intersect(desc_a, desc_b):
		return true
	# Check containment: one representative point of A inside B or vice-versa
	var pt_a = _shape_sample_point(desc_a)
	var pt_b = _shape_sample_point(desc_b)
	if pt_a != null and _point_in_shape(pt_a, desc_b):
		return true
	if pt_b != null and _point_in_shape(pt_b, desc_a):
		return true
	return false

# Return a representative interior point for a shape descriptor (centroid).
func _shape_sample_point(desc: Dictionary):
	if desc.shape_type == "poly" and desc.points.size() > 0:
		var sum = Vector2.ZERO
		for p in desc.points:
			sum += p
		return sum / desc.points.size()
	return null

# Return true if [pt] is strictly inside [desc] (boundary not counted).
func _point_in_shape(pt: Vector2, desc: Dictionary) -> bool:
	if desc.shape_type == "poly":
		return Geometry.is_point_in_polygon(pt, desc.points)
	return false


# Apply CONFORMING when [new_marker] is placed: for every existing Shape marker
# that overlaps new_marker, dent its outline to the boundary of new_marker.
# This is identical to Difference applied to the existing marker, but the new
# marker is still placed normally.
# The new marker itself keeps its full unclipped outline.
func _apply_conforming_to_existing_shapes(new_marker):
	if conforming_mode and new_marker.marker_type == MARKER_TYPE_SHAPE:
		_subtract_desc_from_markers(_get_shape_descriptor(new_marker, _get_grid_cell_size()), new_marker.id)

func _apply_wrapping_to_new_shape(new_marker):
	if not wrapping_mode or new_marker.marker_type != MARKER_TYPE_SHAPE:
		return
	var cell_size = _get_grid_cell_size()
	if cell_size == null:
		return
	for other in markers:
		if other.id == new_marker.id or other.marker_type != MARKER_TYPE_SHAPE:
			continue
		var other_desc = _get_shape_descriptor(other, cell_size)
		if other_desc.empty():
			continue
		# Re-derive new_marker's current descriptor each iteration so that
		# sequential clips from multiple existing shapes chain correctly.
		var new_desc = _get_shape_descriptor(new_marker, cell_size)
		if new_desc.empty():
			break
		if not _shapes_overlap(other_desc, new_desc):
			continue
		# Keep segments of new_marker that are OUTSIDE other,
		# then append other's boundary where it runs inside new_marker.
		var diff_boundary = GeometryUtils.clip_polygon_inside_shape(
			other_desc.points, new_desc)
		new_marker.set_primitives(
			GeometryUtils.clip_primitives_against_shapes(
				new_marker.get_primitives(), [other_desc]) + diff_boundary)
	if overlay:
		overlay.update()

func _snapshot_potential_merge_targets(merge_desc: Dictionary) -> Dictionary:
	return _snapshot_overlapping_shapes(merge_desc, true)

func _snapshot_overlapping_shapes(desc: Dictionary, include_meta: bool = false) -> Dictionary:
	var snapshots = {}
	var cell_size = _get_grid_cell_size()
	if desc.empty() or cell_size == null:
		return snapshots
	for marker in markers:
		if marker.marker_type != MARKER_TYPE_SHAPE:
			continue
		var other = _get_shape_descriptor(marker, cell_size)
		if other.empty() or not _shapes_overlap(desc, other):
			continue
		var snap = {"primitives": marker.get_primitives().duplicate(true)}
		if include_meta:
			snap["position"] = marker.position
			snap["color"] = marker.color
			snap["saved_marker"] = marker.Save()
		snapshots[marker.id] = snap
	return snapshots

func _do_apply_merge(merge_desc: Dictionary, new_pos: Vector2) -> Array:
	if merge_desc.empty():
		return []
	var cell_size = _get_grid_cell_size()
	if cell_size == null:
		return []

	# ── 1. Collect all Shape markers that overlap merge_desc ─────────────────
	var overlapping = []
	for marker in markers:
		if marker.marker_type != MARKER_TYPE_SHAPE:
			continue
		var desc = _get_shape_descriptor(marker, cell_size)
		if desc.empty():
			continue
		if _shapes_overlap(desc, merge_desc):
			overlapping.append(marker)

	if overlapping.empty():
		return []

	# ── 1.5. Early exit if virtual shape is nearly identical to the only overlapping marker ─
	# This prevents degenerate polygons when merging identical shapes.
	if overlapping.size() == 1:
		var primary_desc = _get_shape_descriptor(overlapping[0], cell_size)
		if not primary_desc.empty():
			# Check if shapes are approximately identical (same vertex count and similar geometry)
			if primary_desc.points.size() == merge_desc.points.size():
				var pos_delta = overlapping[0].position.distance_to(new_pos)
				if pos_delta < 1.0:  # Positions are nearly identical (< 1 pixel apart)
					# Shapes are essentially identical - no merge needed
					if LOGGER:
						LOGGER.debug("Merge: virtual shape is identical to marker %d — no merge needed" % [overlapping[0].id])
					return []

	# ── 2. Build one unified polygon from virtual shape + all overlapping markers ─
	# Start with the virtual (placed) shape's points.
	var running_pts: Array = merge_desc.points.duplicate()
	# Weighted-average centre: start from the virtual shape's centre.
	var center_sum: Vector2 = new_pos
	var center_count: int = 1
	var merged_markers = []

	for marker in overlapping:
		var desc = _get_shape_descriptor(marker, cell_size)
		if desc.empty():
			continue
		var merged_segs = GeometryUtils.merge_polygons_outline(running_pts, desc.points)
		if merged_segs.empty():
			# No geometric overlap (e.g. tangent touch with zero area) — skip this
			# marker entirely so its position does not skew the centroid.
			continue
		var chained = GeometryUtils.chain_segments_to_polygon(merged_segs)
		if chained.empty():
			# Fallback: keep previous running polygon without shifting centroid.
			continue
		# Merge succeeded — accumulate centroid only now.
		center_sum += marker.position
		center_count += 1
		merged_markers.append(marker)
		running_pts = chained

	# ── 2.5. Validate the merged polygon ──────────────────────────────────────
	# If merging produced a degenerate polygon (e.g., two identical shapes),
	# keep the original primary marker's geometry unchanged.
	if merged_markers.empty() or running_pts.size() < 3:
		if LOGGER:
			LOGGER.warn("Merge: resulted in degenerate polygon (< 3 vertices) — keeping primary marker %d unchanged" % [overlapping[0].id])
		return []

	# ── 3. Write the final outline and position to the primary marker ─────────
	var final_segs = GeometryUtils.points_to_segs(running_pts)
	var final_pos  = center_sum / float(center_count)

	var primary = merged_markers[0]
	primary.set_primitives(final_segs)
	primary.position = final_pos
	if LOGGER:
		LOGGER.debug("Merge: primary marker %d updated, pos %s" % [primary.id, str(final_pos)])

	# Remove only markers whose geometry was successfully included.
	var absorbed_ids: Array = []
	for i in range(1, merged_markers.size()):
		var m = merged_markers[i]
		absorbed_ids.append(m.id)
		var idx = markers.find(m)
		if idx != -1:
			markers.remove(idx)
		markers_lookup.erase(m.id)
		if parent_mod.guides_lines_api:
			parent_mod.guides_lines_api._notify_marker_deleted(m.id)
		if LOGGER:
			LOGGER.debug("Merge: marker %d absorbed into marker %d" % [m.id, primary.id])

	if overlay:
		overlay.update()

	return absorbed_ids

# ============================================================================
# DIFFERENCE MODE CORE
# ============================================================================

## Snapshot primitives of all Shape markers that intersect diff_desc.
func _take_difference_snapshot(diff_desc: Dictionary) -> Dictionary:
	return _snapshot_overlapping_shapes(diff_desc)

func _do_apply_difference(diff_desc: Dictionary):
	_subtract_desc_from_markers(diff_desc)

func _subtract_desc_from_markers(desc: Dictionary, exclude_id: int = -1):
	var cell_size = _get_grid_cell_size()
	if desc.empty() or cell_size == null:
		return
	for marker in markers:
		if marker.marker_type != MARKER_TYPE_SHAPE or marker.id == exclude_id:
			continue
		var target = _get_shape_descriptor(marker, cell_size)
		if target.empty() or not _shapes_overlap(target, desc):
			continue
		marker.set_primitives(GeometryUtils.clip_primitives_against_shapes(
			marker.get_primitives(), [desc]) + GeometryUtils.clip_polygon_inside_shape(desc.points, target))
	if overlay:
		overlay.update()

func _snapshot_potential_clip_targets(pos: Vector2) -> Dictionary:
	return _snapshot_overlapping_shapes(_build_shape_descriptor_at(pos))

func _take_cut_snapshot(cut_desc: Dictionary) -> Dictionary:
	var snap = {}
	var cell_size = _get_grid_cell_size()
	if cell_size == null:
		return snap
	for marker in markers:
		if marker.marker_type != MARKER_TYPE_SHAPE:
			continue
		var desc = _get_shape_descriptor(marker, cell_size)
		if desc.empty():
			continue
		# Case (a): outline edges actually cross the cut shape.
		if _shapes_intersect(cut_desc, desc):
			snap[marker.id] = {
				"primitives": marker.get_primitives().duplicate(true),
				"color":      marker.color,
				"position":   marker.position,
				"saved_marker": marker.Save()
			}
			continue
		# Case (b): shape fully inside cut (no edge intersection but contained).
		if not desc.points.empty() and Geometry.is_point_in_polygon(desc.points[0], cut_desc.points):
			snap[marker.id] = {
				"primitives": marker.get_primitives().duplicate(true),
				"color":      marker.color,
				"position":   marker.position,
				"saved_marker": marker.Save()
			}
	return snap

## Apply the Cut operation:
##   • Shapes whose edges intersect cut_desc are clipped; remaining segments
##     are split into disconnected chains and each chain becomes a Path marker.
##     The first chain reuses the existing marker (type changed to Path).
##     Additional chains spawn new Path markers.
##   • Shapes fully inside cut_desc (no edge intersection) are deleted.
##   • Shapes that contain cut_desc without edge intersection are untouched.
##
## Returns { "deleted_ids": Array[int], "created_markers_data": Array[Dictionary] }.
## Call _take_cut_snapshot BEFORE this to capture the pre-cut state for undo.
func _do_apply_cut(cut_desc: Dictionary) -> Dictionary:
	var cell_size = _get_grid_cell_size()
	if cell_size == null:
		return {"deleted_ids": [], "created_markers_data": []}

	var deleted_ids          = []
	var created_markers_data = []

	# Freeze count so newly appended Path markers are not re-processed.
	var original_count = markers.size()
	for i in range(original_count - 1, -1, -1):
		var marker = markers[i]
		if marker.marker_type != MARKER_TYPE_SHAPE:
			continue
		var target_desc = _get_shape_descriptor(marker, cell_size)
		if target_desc.empty():
			continue

		var intersects = _shapes_intersect(cut_desc, target_desc)
		if not intersects:
			# Only delete if the shape lies fully inside the cut (not the reverse).
			if not target_desc.points.empty() and \
					Geometry.is_point_in_polygon(target_desc.points[0], cut_desc.points):
				deleted_ids.append(marker.id)
				markers_lookup.erase(marker.id)
				markers.remove(i)
				if parent_mod.guides_lines_api:
					parent_mod.guides_lines_api._notify_marker_deleted(marker.id)
				if LOGGER:
					LOGGER.debug("Cut: deleted marker %d (fully inside cut)" % [marker.id])
			# else: cut is inside the shape, or shapes don't overlap — leave untouched.
			continue

		# Clip: keep only segments whose midpoint lies OUTSIDE the cut shape.
		var remaining_segs = GeometryUtils.clip_primitives_against_shapes(
				marker.get_primitives(), [cut_desc])

		if remaining_segs.empty():
			# All segments consumed — shape is effectively fully inside cut.
			deleted_ids.append(marker.id)
			markers_lookup.erase(marker.id)
			markers.remove(i)
			if parent_mod.guides_lines_api:
				parent_mod.guides_lines_api._notify_marker_deleted(marker.id)
			if LOGGER:
				LOGGER.debug("Cut: deleted marker %d (no segments remained after clip)" % [marker.id])
			continue

		# Split the remaining segments into disconnected chains.
		var chains = GeometryUtils.split_segments_into_chains(remaining_segs)
		if chains.empty():
			deleted_ids.append(marker.id)
			markers_lookup.erase(marker.id)
			markers.remove(i)
			if parent_mod.guides_lines_api:
				parent_mod.guides_lines_api._notify_marker_deleted(marker.id)
			if LOGGER:
				LOGGER.warn("Cut: deleted marker %d (split_segments_into_chains returned empty)" % [marker.id])
			continue

		# Preserve color before we change marker state.
		var saved_color = marker.color

		# ── First chain: convert the existing marker in-place to a Path ────
		marker.marker_type    = MARKER_TYPE_PATH
		marker.marker_points  = chains[0].duplicate()
		marker.position       = chains[0][0]  # Move anchor to start of path.
		marker.path_closed    = false
		marker.path_end_arrow = false
		# Clear the Shape draw cache; Path rendering reads marker_points directly.
		marker.cached_draw_data = {}
		marker._dirty = true
		if LOGGER:
			LOGGER.debug("Cut: marker %d converted to Path (%d points)" % [
					marker.id, chains[0].size()])

		# ── Remaining chains: create new Path markers ───────────────────────
		for ci in range(1, chains.size()):
			var new_id = next_id
			next_id += 1
			var md = {
				"position":       chains[ci][0],
				"marker_type":    MARKER_TYPE_PATH,
				"color":          saved_color,
				"id":             new_id,
				"marker_points":  chains[ci].duplicate(),
				"path_closed":    false,
				"path_end_arrow": false
			}
			_do_place_marker(md)
			created_markers_data.append(md)
			if LOGGER:
				LOGGER.debug("Cut: created extra Path marker %d (%d points, chain %d)" % [
						new_id, chains[ci].size(), ci])

	if overlay:
		overlay.update()

	return {"deleted_ids": deleted_ids, "created_markers_data": created_markers_data}

## Undo a Cut operation:
##   1. Remove every Path marker that was created as an extra fragment.
##   2. For markers that were modified (Shape → Path): restore them to Shape.
##   3. For markers that were deleted (fully inside cut): re-create them as Shape.
func _undo_cut(snapshots: Dictionary, deleted_ids: Array, created_markers_data: Array) -> void:
	# 1. Remove extra Path markers that did not exist before the cut.
	for md in created_markers_data:
		var mid = md["id"]
		if markers_lookup.has(mid):
			var m = markers_lookup[mid]
			markers.erase(m)
			markers_lookup.erase(mid)
			if LOGGER:
				LOGGER.debug("Cut undo: removed created Path marker id=%d" % mid)

	# 2 & 3. Restore every affected marker from its snapshot.
	for sid in snapshots:
		var snap = snapshots[sid]
		if deleted_ids.has(sid):
			# Was deleted — re-create as Shape.
			var marker = GuideMarkerClass.new()
			marker.Load(snap.saved_marker)
			marker.color = snap.color
			marker.update_opacity(_current_opacity())
			marker.set_primitives(snap.primitives.duplicate(true))
			markers.append(marker)
			markers_lookup[sid] = marker
			if sid >= next_id:
				next_id = sid + 1
			if LOGGER:
				LOGGER.debug("Cut undo: restored deleted marker id=%d" % sid)
		else:
			# Was modified (Path) — restore back to Shape.
			if markers_lookup.has(sid):
				var marker = markers_lookup[sid]
				marker.Load(snap.saved_marker)
				marker.color = snap.color
				marker.update_opacity(_current_opacity())
				marker.set_primitives(snap.primitives.duplicate(true))
				marker._dirty = true
				if LOGGER:
					LOGGER.debug("Cut undo: restored Shape marker id=%d" % sid)

	update_ui()
	if overlay:
		overlay.update()


# ============================================================================
# UI STATE
# ============================================================================

# Update tool panel UI with current state
func update_ui():
	if ui:
		ui.update_ui()

# ============================================================================
# UI PANEL AND PARAMETER ACTIONS
# ============================================================================

# Create the UI panel for the tool with all controls
func create_ui_panel():
	if ui:
		ui.create_ui_panel()

# Parameter actions work independently of the sidebar controls.
func save_current_type_settings():
	if not TYPE_SETTING_FIELDS.has(active_marker_type):
		return
	var settings = type_settings.get(active_marker_type, {})
	for key in TYPE_SETTING_FIELDS[active_marker_type]:
		settings[key] = get(TYPE_SETTING_FIELDS[active_marker_type][key][0])
	type_settings[active_marker_type] = settings

func load_type_settings(marker_type):
	if not TYPE_SETTING_FIELDS.has(marker_type) or not type_settings.has(marker_type):
		return
	for key in TYPE_SETTING_FIELDS[marker_type]:
		var field = TYPE_SETTING_FIELDS[marker_type][key]
		set(field[0], type_settings[marker_type].get(key, field[1]))
	if ui:
		ui.sync_type_settings_controls(marker_type)

func set_marker_type(marker_type):
	if not marker_type in [MARKER_TYPE_LINE, MARKER_TYPE_SHAPE, MARKER_TYPE_PATH, MARKER_TYPE_FILL, MARKER_TYPE_TEMPLATE]:
		return
	save_current_type_settings()
	if active_marker_type == MARKER_TYPE_PATH and marker_type != MARKER_TYPE_PATH:
		_cancel_path_placement()
	if active_marker_type == MARKER_TYPE_TEMPLATE and marker_type != MARKER_TYPE_TEMPLATE:
		template_capture_mode = false
		if ui: ui._update_template_capture_button(false)
	active_marker_type = marker_type
	load_type_settings(marker_type)
	if ui: ui.sync_type_selector_to_active_type()
	if overlay: overlay.update()
	if LOGGER: LOGGER.debug("Marker type changed to: %s" % marker_type)

func set_shape_mode(mode: String):
	# Set all modes to false first
	merge_shapes = false
	conforming_mode = false
	wrapping_mode = false
	difference_mode = false
	cut_mode = false

	# Activate the selected mode (normal means all stay false)
	match mode:
		"merge":
			merge_shapes = true
		"conforming":
			conforming_mode = true
		"wrapping":
			wrapping_mode = true
		"difference":
			difference_mode = true
		"cut":
			cut_mode = true
		"normal":
			pass  # All modes already false

	# Update button pressed states
	if ui:
		ui._update_shape_mode_buttons(mode)
		ui._sync_template_overlap_mode_buttons()

	if LOGGER:
		LOGGER.info("Shape interaction mode changed to: %s" % [mode])

func set_path_end_arrow(enabled):
	active_path_end_arrow = enabled
	type_settings[MARKER_TYPE_PATH]["end_arrow"] = enabled
	if ui: ui._update_path_end_arrow_checkbox()
	if overlay: overlay.update()

func set_angle(value):
	active_angle = value
	type_settings[MARKER_TYPE_LINE]["angle"] = value
	if ui: ui._update_angle_spinbox()
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Angle changed to: %.1f°" % [value])

func set_color(new_color):
	active_color = new_color
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Color changed to: %s" % [new_color.to_html()])

func set_mirror(enabled):
	active_mirror = enabled
	if ui: ui._update_mirror_checkbox()
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Mirror toggled: %s" % [str(enabled)])

func set_shape_angle(value):
	active_shape_angle = value
	type_settings[MARKER_TYPE_SHAPE]["angle"] = value
	if ui: ui._update_shape_angle_spinbox()
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Shape angle changed to: %.1f°" % [value])

func set_path_arrow_head_length(value):
	if value < 10.0:
		value = 10.0
	active_arrow_head_length = value
	type_settings[MARKER_TYPE_PATH]["head_length"] = value
	if ui: ui._update_path_arrow_head_length_spinbox()
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Path arrow head length changed to: %.1f px" % [value])

func set_path_arrow_head_angle(value):
	active_arrow_head_angle = value
	if ui: ui._update_path_arrow_head_angle_spinbox()
	type_settings[MARKER_TYPE_PATH]["head_angle"] = value
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Path arrow head angle changed to: %.1f°" % [value])

func set_shape_size_mode(mode):
	if not mode in ["radius", "side"]:
		return
	active_shape_size_mode = mode
	type_settings[MARKER_TYPE_SHAPE]["size_mode"] = mode
	if mode == "side":
		# Compute equivalent side from the current circumradius
		var computed_side = GeometryUtils.circumradius_to_side(active_shape_radius / _get_hex_edge_correction(), active_shape_sides)
		if computed_side < 0.1:
			computed_side = 0.1
		active_shape_side = computed_side
		type_settings[MARKER_TYPE_SHAPE]["side"] = computed_side
		if ui: ui._update_shape_side_spinbox()
	if ui: ui._update_shape_size_mode_ui()
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Shape size mode changed to: %s" % [mode])

func set_shape_preset(preset):
	# Apply canonical defaults for the selected preset
	match preset:
		SHAPE_CIRCLE:
			active_shape_sides = 64
			active_shape_angle = 0.0
		SHAPE_SQUARE:
			active_shape_sides = 4
			active_shape_angle = 45.0
		SHAPE_PENTAGON:
			active_shape_sides = 5
			active_shape_angle = -90.0
		SHAPE_HEXAGON:
			active_shape_sides = 6
			active_shape_angle = 0.0
		SHAPE_OCTAGON:
			active_shape_sides = 8
			active_shape_angle = 0.0
		SHAPE_CUSTOM:
			active_shape_angle = 0.0

	type_settings[MARKER_TYPE_SHAPE]["angle"] = active_shape_angle
	type_settings[MARKER_TYPE_SHAPE]["sides"] = active_shape_sides

	if ui: ui.sync_shape_preset(preset)

	# Circle has no meaningful side — force radius mode and hide the size toggle
	var is_circle = (preset == SHAPE_CIRCLE)
	if is_circle and active_shape_size_mode == "side":
		active_shape_size_mode = "radius"
		type_settings[MARKER_TYPE_SHAPE]["size_mode"] = "radius"
	if ui: ui._update_shape_size_mode_ui()

	# In side mode with a non-circle preset, keep the user's side value and
	# recompute the circumradius for the new number of sides.
	if active_shape_size_mode == "side" and not is_circle:
		recompute_radius_from_side()
		if ui: ui._update_shape_radius_spinbox()

	if ui: ui._update_shape_angle_spinbox()
	if ui: ui._update_shape_sides_spinbox()

	if overlay:
		overlay.update()

	if LOGGER:
		LOGGER.info("Shape preset changed to: %s (sides=%d, angle=%.1f)" % [preset, active_shape_sides, active_shape_angle])

func adjust_angle_with_wheel(direction):
	if active_marker_type == MARKER_TYPE_LINE:
		set_angle(fposmod(active_angle + direction, 360.0))

# Compatibility name: adjusts the size selected by Radius/Side mode.
func adjust_shape_radius_with_wheel(direction):
	if active_marker_type != MARKER_TYPE_SHAPE:
		return
	if active_shape_size_mode == "side":
		set_shape_side(active_shape_side + direction * 0.1)
	else:
		set_shape_radius(active_shape_radius + direction * 0.1)

func adjust_shape_angle_with_wheel(direction):
	if active_marker_type == MARKER_TYPE_SHAPE:
		set_shape_angle(fposmod(active_shape_angle + direction * 5.0, 360.0))

func rotate_shape_45():
	if active_marker_type == MARKER_TYPE_SHAPE:
		set_shape_angle(fposmod(active_shape_angle + 45.0, 360.0))

func set_shape_side(value):
	if value < 0.1:
		value = 0.1
	active_shape_side = value
	type_settings[MARKER_TYPE_SHAPE]["side"] = value
	if ui: ui._update_shape_side_spinbox()
	var new_radius = recompute_radius_from_side()
	if ui: ui._update_shape_radius_spinbox()
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Shape side changed to: %.2f cells (radius=%.3f)" % [value, new_radius])

func set_shape_sides(value):
	active_shape_sides = int(value)
	type_settings[MARKER_TYPE_SHAPE]["sides"] = active_shape_sides
	if ui: ui._update_shape_sides_spinbox()
	# In side mode, recompute circumradius from the kept side value with the new sides count
	if active_shape_size_mode == "side":
		recompute_radius_from_side()
		if ui: ui._update_shape_radius_spinbox()
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Shape sides changed to: %d" % [active_shape_sides])

func set_shape_radius(value):
	if value < 0.1:
		value = 0.1
	active_shape_radius = value
	type_settings[MARKER_TYPE_SHAPE]["radius"] = value
	if ui: ui._update_shape_radius_spinbox()
	if overlay:
		overlay.update()
	if LOGGER:
		LOGGER.debug("Shape radius changed to: %.1f cells" % [value])

func _try_apply_non_placing_shape_mode(desc: Dictionary, pos: Vector2) -> bool:
	if desc.empty():
		return true
	if difference_mode:
		var snapshots = _take_difference_snapshot(desc)
		_do_apply_difference(desc)
		_record_history(GuidesLinesHistory.DifferenceRecord.new(self, desc, snapshots))
		return true
	if cut_mode:
		var snapshots = _take_cut_snapshot(desc)
		if not snapshots.empty():
			var result = _do_apply_cut(desc)
			_record_history(GuidesLinesHistory.CutRecord.new(self, desc, snapshots, result.deleted_ids, result.created_markers_data))
		return true
	if merge_shapes:
		var snapshots = _snapshot_potential_merge_targets(desc)
		if not snapshots.empty():
			var absorbed = _do_apply_merge(desc, pos)
			_record_history(GuidesLinesHistory.MergeShapeRecord.new(self, desc, pos, snapshots, absorbed))
			return true
	return false

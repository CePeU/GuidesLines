extends Reference

const GeometryUtils = preload("../utils/GeometryUtils.gd")

# GuidesLinesApi - External API for the GuidesLines mod
#
# Allows other mods to interact with GuidesLines programmatically.
#
# Usage from another mod:
#
#   # After map is loaded, check if the API is available:
#   if self.Global.API.has("GuidesLinesApi"):
#       var gl = self.Global.API.GuidesLinesApi
#       var id = gl.place_line_marker(Vector2(512, 512))
#       gl.connect("marker_placed", self, "_on_marker_placed")
#
#   # Or listen for late registration:
#   self.Global.API.connect("api_registered", self, "_on_api_registered")
#   func _on_api_registered(api_id, _api):
#       if api_id == "GuidesLinesApi":
#           var gl = self.Global.API.GuidesLinesApi
#           ...
#
# ============================================================================
# SIGNALS
# ============================================================================

# Emitted when any marker is placed via tool or API.
# marker_id: int  — unique marker id
# position:  Vector2 — world position of the marker
signal marker_placed(marker_id, position)

# Emitted when a single marker is deleted.
# marker_id: int — unique marker id that was removed
signal marker_deleted(marker_id)

# Emitted when all markers are cleared at once.
signal all_markers_deleted()

# Emitted when an overlay setting changes.
# setting_name: String — one of "cross_guides", "perm_vertical",
#                        "perm_horizontal", "show_coordinates",
#                        "markers_visible", "markers_opacity"
# value: bool | float
signal settings_changed(setting_name, value)

# ============================================================================
# INTERNALS
# ============================================================================

const CLASS_NAME = "GuidesLinesApi"

var _mod   # Reference to GuidesLines main script
var LOGGER  # Logger instance

# ============================================================================
# INIT / UNLOAD
# ============================================================================

func _init(mod, logger):
	_mod = mod
	LOGGER = logger
	if LOGGER:
		LOGGER.info("GuidesLinesApi initialized")

func _unload():
	if LOGGER:
		LOGGER.info("Unloading %s." % [CLASS_NAME])
	# Disconnect all signal connections
	for signal_dict in get_signal_list():
		var signal_name = signal_dict.name
		for callable_dict in get_signal_connection_list(signal_name):
			disconnect(signal_name, callable_dict.target, callable_dict.method)

# ============================================================================
# MARKER PLACEMENT
# ============================================================================

## Places a Line marker at [position].
## Returns the integer id of the created marker, or -1 on failure.
## Parameters:
##   position — world-space Vector2
##   angle    — line angle in degrees (default 0.0)
##   mirror   — whether to also draw the mirrored line (default false)
##   color    — marker color (default Color(0, 0.7, 1, 1))
func place_line_marker(position: Vector2, angle: float = 0.0, mirror: bool = false, color = null) -> int:
	if not _has_tool():
		return -1
	var tool = _tool()
	var marker_id = tool.next_id
	var marker_data = {
		"position": position,
		"marker_type": "Line",
		"color": color if color != null else tool.active_color,
		"show_coordinates": tool.show_coordinates,
		"id": marker_id,
		"angle": angle,
		"mirror": mirror,
	}
	tool.api_place_marker(marker_data)
	if LOGGER:
		LOGGER.debug("API: Line marker placed id=%d pos=%s angle=%.1f" % [marker_id, str(position), angle])
	return marker_id

## Places a Shape marker at [position].
## Returns the integer id of the created marker, or -1 on failure.
## Parameters:
##   position — world-space Vector2
##   radius   — circumradius in grid cells (default 1.0)
##   angle    — rotation in degrees (default 0.0)
##   sides    — number of polygon sides (default 6)
##   color    — marker color (default active color)
func place_shape_marker(position: Vector2, radius: float = 1.0,
						angle: float = 0.0, sides: int = 6, color = null) -> int:
	if not _has_tool():
		return -1
	var tool = _tool()
	var marker_id = tool.next_id
	var marker_data = {
		"position": position,
		"marker_type": "Shape",
		"color": color if color != null else tool.active_color,
		"id": marker_id,
		"shape_radius": radius,
		"shape_angle": angle,
		"shape_sides": sides,
	}
	tool.api_place_marker(marker_data)
	if LOGGER:
		LOGGER.debug("API: Shape marker placed id=%d pos=%s sides=%d" % [marker_id, str(position), sides])
	return marker_id

## Places a Path marker.
## Returns the integer id of the created marker, or -1 on failure.
## Parameters:
##   points — Array of Vector2, minimum 2 points
##   closed — whether the path is a closed loop (default false)
##   color  — marker color (default active color)
func place_path_marker(points: Array, closed: bool = false, color = null) -> int:
	if not _has_tool():
		return -1
	if points.size() < 2:
		if LOGGER:
			LOGGER.warn("API: place_path_marker requires at least 2 points")
		return -1
	var tool = _tool()
	var marker_id = tool.next_id
	var marker_data = {
		"position": points[0],
		"marker_type": "Path",
		"color": color if color != null else tool.active_color,
		"id": marker_id,
		"marker_points": points.duplicate(),
		"path_closed": closed,
	}
	tool.api_place_marker(marker_data)
	if LOGGER:
		LOGGER.debug("API: Path marker placed id=%d points=%d closed=%s" % [marker_id, points.size(), str(closed)])
	return marker_id

## Places an Arrow marker from [from_pos] to [to_pos].
## Internally creates a Path marker with path_end_arrow = true
## (Arrow type was merged into Path in v2.1.6; this function remains for API compatibility).
## Returns the integer id of the created marker, or -1 on failure.
## Parameters:
##   from_pos    — start world-space Vector2
##   to_pos      — end world-space Vector2
##   head_length — arrowhead length in pixels (default 50.0)
##   head_angle  — arrowhead opening angle in degrees (default 30.0)
##   color       — marker color (default active color)
func place_arrow_marker(from_pos: Vector2, to_pos: Vector2,
						head_length: float = 50.0, head_angle: float = 30.0, color = null) -> int:
	if not _has_tool():
		return -1
	var tool = _tool()
	var marker_id = tool.next_id
	var marker_data = {
		"position": from_pos,
		"marker_type": "Path",
		"color": color if color != null else tool.active_color,
		"id": marker_id,
		"marker_points": [from_pos, to_pos],
		"path_closed": false,
		"path_end_arrow": true,
		"arrow_head_length": head_length,
		"arrow_head_angle": head_angle,
	}
	tool.api_place_marker(marker_data)
	if LOGGER:
		LOGGER.debug("API: Arrow(Path) marker placed id=%d from=%s to=%s" % [marker_id, str(from_pos), str(to_pos)])
	return marker_id

# ============================================================================
# SHAPE PLACEMENT WITH INTERACTION MODES
# ============================================================================

## Places a virtual Shape and merges it into every overlapping existing Shape
## marker (union of outlines).  No new marker is created.
## All overlapping markers are folded into a single primary marker; the rest
## are deleted and their IDs returned in "absorbed_marker_ids".
##
## Note: If the virtual shape is nearly identical to a single existing marker
## (same position, same vertex count), no merge occurs and the existing marker
## remains unchanged. This prevents degenerate polygons from identical overlaps.
##
## Returns a Dictionary on success:
##   {
##     "affected_markers": Array — one entry for the surviving primary marker:
##       {
##         "marker_id":    int,
##         "new_polygon":  Array[Vector2] — full union outline,
##         "old_position": Vector2,
##         "new_position": Vector2,       — average of all participants,
##       }
##     "absorbed_marker_ids": Array[int] — IDs of markers that were deleted
##                              during the merge (empty if only one overlap)
##   }
## Returns {} on internal failure.
## Returns {"affected_markers":[], "absorbed_marker_ids":[]} when no overlap
##         or when the virtual shape is identical to the existing marker.
##
## Parameters:
##   position — world-space Vector2 centre of the virtual new shape
##   radius   — circumradius in grid cells (default 1.0)
##   angle    — rotation in degrees (default 0.0)
##   sides    — number of polygon sides (default 6)
func place_shape_merge(position: Vector2, radius: float = 1.0,
		angle: float = 0.0, sides: int = 6) -> Dictionary:
	if not _has_tool():
		return {}
	var tool = _tool()
	var marker_data = {
		"position":     position,
		"marker_type":  "Shape",
		"shape_radius": radius,
		"shape_angle":  angle,
		"shape_sides":  sides,
	}
	var result = tool.api_place_shape_merge(marker_data)
	if LOGGER:
		var absorbed = result.get("absorbed_marker_ids", [])
		LOGGER.debug("API: place_shape_merge at %s — absorbed %d markers" % [str(position), absorbed.size()])
	return result

## Places a Shape marker in Conforming mode.
## The new marker is placed with its original outline; every existing Shape
## marker that overlaps is dented to accommodate the new one
## (Difference applied to existing markers only).
##
## Returns a Dictionary on success:
##   {
##     "marker_id":        int,              — id of the newly placed marker
##     "marker_polygon":   Array[Vector2],   — final outline of the new marker
##     "affected_markers": Array — one entry per dented existing marker:
##       {
##         "marker_id":   int,
##         "new_polygon": Array[Vector2],
##       }
##   }
## "marker_id" is -1 on failure (map not loaded).
##
## Parameters:
##   position — world-space Vector2 centre
##   radius   — circumradius in grid cells (default 1.0)
##   angle    — rotation in degrees (default 0.0)
##   sides    — number of polygon sides (default 6)
##   color    — marker color (default active color)
func place_shape_conforming(position: Vector2, radius: float = 1.0,
		angle: float = 0.0, sides: int = 6, color = null) -> Dictionary:
	if not _has_tool():
		return {"marker_id": -1, "marker_polygon": [], "affected_markers": []}
	var tool = _tool()
	var marker_id = tool.next_id
	var marker_data = {
		"position":     position,
		"marker_type":  "Shape",
		"color":        color if color != null else tool.active_color,
		"id":           marker_id,
		"shape_radius": radius,
		"shape_angle":  angle,
		"shape_sides":  sides,
	}
	var result = tool.api_place_shape_conforming(marker_data)
	if LOGGER:
		var n = result.get("affected_markers", []).size()
		LOGGER.debug("API: place_shape_conforming — id=%d dented %d markers" % [marker_id, n])
	return result

## Places a Shape marker in Wrapping mode.
## The new marker is placed but its own outline is dented wherever it overlaps
## existing Shape markers (Difference applied to the new shape only; existing
## markers are left unchanged).
##
## Returns a Dictionary on success:
##   {
##     "marker_id":        int,            — id of the newly placed (dented) marker
##     "marker_polygon":   Array[Vector2], — final outline of the new marker after denting
##     "affected_markers": Array — one entry per marker that caused a dent:
##       {
##         "marker_id":   int,
##         "new_polygon": Array[Vector2],  — polygon of that marker (unchanged)
##       }
##   }
## "marker_id" is -1 on failure (map not loaded).
##
## Parameters:
##   position — world-space Vector2 centre
##   radius   — circumradius in grid cells (default 1.0)
##   angle    — rotation in degrees (default 0.0)
##   sides    — number of polygon sides (default 6)
##   color    — marker color (default active color)
func place_shape_wrapping(position: Vector2, radius: float = 1.0,
		angle: float = 0.0, sides: int = 6, color = null) -> Dictionary:
	if not _has_tool():
		return {"marker_id": -1, "marker_polygon": [], "affected_markers": []}
	var tool = _tool()
	var marker_id = tool.next_id
	var marker_data = {
		"position":     position,
		"marker_type":  "Shape",
		"color":        color if color != null else tool.active_color,
		"id":           marker_id,
		"shape_radius": radius,
		"shape_angle":  angle,
		"shape_sides":  sides,
	}
	var result = tool.api_place_shape_wrapping(marker_data)
	if LOGGER:
		LOGGER.debug("API: place_shape_wrapping — id=%d verts=%d affected=%d" % [
			marker_id,
			result.get("marker_polygon", []).size(),
			result.get("affected_markers", []).size()])
	return result

## Applies a Difference operation using a virtual shape at [position].
## No new marker is created — a hole is punched into every overlapping
## existing Shape marker's outline.
##
## Returns a Dictionary:
##   {
##     "affected_markers": Array — one entry per modified marker:
##       {
##         "marker_id":   int,
##         "new_polygon": Array[Vector2],
##       }
##   }
## Returns {} on internal failure.
## Returns {"affected_markers":[]} when no existing Shape overlaps [position].
##
## Parameters:
##   position — world-space Vector2 centre of the virtual cutter shape
##   radius   — circumradius in grid cells (default 1.0)
##   angle    — rotation in degrees (default 0.0)
##   sides    — number of polygon sides (default 6)
func apply_shape_difference(position: Vector2, radius: float = 1.0,
		angle: float = 0.0, sides: int = 6) -> Dictionary:
	if not _has_tool():
		return {}
	var tool = _tool()
	var marker_data = {
		"position":     position,
		"marker_type":  "Shape",
		"shape_radius": radius,
		"shape_angle":  angle,
		"shape_sides":  sides,
	}
	var result = tool.api_apply_shape_difference(marker_data)
	if LOGGER:
		var n = result.get("affected_markers", []).size()
		LOGGER.debug("API: apply_shape_difference — affected %d markers at %s" % [n, str(position)])
	return result

# ============================================================================
# MARKER DELETION
# ============================================================================

## Deletes a marker by its integer id.
## Returns true if the marker was found and deleted, false otherwise.
func delete_marker(marker_id: int) -> bool:
	if not _has_tool():
		return false
	var result = _tool().api_delete_marker_by_id(marker_id)
	if not result and LOGGER:
		LOGGER.warn("API: delete_marker — id %d not found" % [marker_id])
	return result

## Deletes all markers on the map. Supports undo.
func delete_all_markers() -> void:
	if not _has_tool():
		return
	_tool().delete_all_markers()
	if LOGGER:
		LOGGER.debug("API: All markers deleted")

# ============================================================================
# MARKER QUERIES
# ============================================================================

## Returns an Array of Dictionaries, one per marker.
## Each dict has the same format as GuideMarker.Save():
##   { id, position, marker_type, color, show_coordinates, ... }
## Note: position is returned as Vector2 (not serialized array).
func get_markers() -> Array:
	if not _has_tool():
		return []
	var result = []
	for marker in _tool().markers:
		result.append(_marker_save_with_pos(marker))
	return result

## Returns a single marker Dictionary by id, or null if not found.
## Dict format is the same as for get_markers().
func get_marker(marker_id: int):
	if not _has_tool():
		return null
	var tool = _tool()
	if not tool.markers_lookup.has(marker_id):
		return null
	return _marker_save_with_pos(tool.markers_lookup[marker_id])

## Returns the total number of markers currently on the map.
func get_marker_count() -> int:
	if not _has_tool():
		return 0
	return _tool().markers.size()

## Finds the nearest marker within [radius] world units of [coords].
## Searches by marker.position.
## Returns a Dictionary (same format as get_marker, with an extra "distance" key),
## or null if no marker exists within the given radius.
## Parameters:
##   coords — world-space Vector2 to search around
##   radius — search radius in world units (default 100.0)
func find_nearest_marker(coords: Vector2, radius: float = 100.0):
	if not _has_tool():
		return null
	var nearest_marker = null
	var nearest_dist = radius
	for marker in _tool().markers:
		var dist = marker.position.distance_to(coords)
		if dist <= nearest_dist:
			nearest_dist = dist
			nearest_marker = marker
	if nearest_marker == null:
		if LOGGER:
			LOGGER.debug("API: find_nearest_marker — nothing found within radius %.1f of %s" % [radius, str(coords)])
		return null
	var d = _marker_save_with_pos(nearest_marker)
	d["distance"] = nearest_dist
	if LOGGER:
		LOGGER.debug("API: find_nearest_marker — id=%d type=%s dist=%.3f" % [nearest_marker.id, nearest_marker.marker_type, nearest_dist])
	return d

## Finds the nearest marker by checking BOTH the marker's position and its drawn
## geometry (line segments, shape edges/circle circumference, path segments, arrow shaft).
## For each marker the minimum distance across the position and all geometry pieces
## is computed. Returns the marker with the smallest such distance within [radius].
##
## Returns a Dictionary on success:
##   { "point":    Vector2       — actual closest point on the marker's geometry,
##     "vertex":   Vector2|null  — nearest vertex of the marker (only for Shape/poly
##                                  and Path; null for Line),
##     "distance": float         — distance from [coords] to [point],
##     + all keys from marker.Save(), plus "position" as Vector2 }
## Returns null if no marker geometry is found within the given radius.
##
## Parameters:
##   coords — world-space Vector2 to search around
##   radius — search radius in world units (default 100.0)
func find_nearest_marker_by_geometry(coords: Vector2, radius: float = 100.0):
	var hit = _find_nearest_geometry(coords, radius, true)
	if hit == null:
		if LOGGER:
			LOGGER.debug("API: find_nearest_marker_by_geometry — nothing found within radius %.1f of %s" % [radius, str(coords)])
		return null
	var nearest_marker = hit.marker
	var nearest_point = hit.point
	var nearest_dist = hit.distance
	var nearest_vertex = null
	if nearest_marker.marker_type == "Shape":
		var vertices = []
		for prim in nearest_marker.get_primitives():
			if prim.type == "seg" and not vertices.has(prim.a):
				vertices.append(prim.a)
		nearest_vertex = GeometryUtils.nearest_polygon_vertex(coords, vertices)
	elif nearest_marker.marker_type == "Path" and nearest_marker.marker_points.size() >= 2:
		nearest_vertex = GeometryUtils.nearest_polygon_vertex(coords, nearest_marker.marker_points)
	var d = _marker_save_with_pos(nearest_marker)
	d["point"] = nearest_point
	d["vertex"] = nearest_vertex
	d["distance"] = nearest_dist
	if LOGGER:
		LOGGER.debug("API: find_nearest_marker_by_geometry — id=%d type=%s point=%s vertex=%s dist=%.3f" % [nearest_marker.id, nearest_marker.marker_type, str(nearest_point), str(nearest_vertex), nearest_dist])
	return d

# Anchor inclusion and tie order are part of the two public query contracts.
func _find_nearest_geometry(coords: Vector2, radius: float, include_anchor: bool):
	if not _has_tool():
		return null
	return _tool().find_nearest_geometry(coords, radius, include_anchor)

## Finds the nearest intersection point between an infinite line and any marker
## geometry within [radius] world units of [coords].
##
## The line is defined by two world-space points and is treated as infinite
## in both directions. Only intersection points that land within [radius] of
## [coords] are considered. The nearest such point to [coords] is returned.
## Line-type markers are always tested (their segments span the whole map);
## Shape/Path candidates are filtered by actual geometry distance to [coords].
##
## Returns a Dictionary on success:
##   { "point":       Vector2  — world-space intersection point,
##     "distance":    float    — distance from [coords] to the intersection,
##     "on_positive": bool     — true if the hit is in the line_from→line_to direction,
##     "marker_id":   int,
##     "marker_type": String,
##     + all keys from marker.Save() }
## Returns null if no intersection was found.
##
## Parameters:
##   line_from — first point defining the infinite line
##   line_to   — second point defining the infinite line
##   coords    — world-space Vector2 centre of the search area
##   radius    — search radius in world units (default 100.0)
func find_line_intersection(line_from: Vector2, line_to: Vector2, coords: Vector2, radius: float = 100.0):
	if not _has_tool():
		return null
	var delta = line_to - line_from
	if delta.length_squared() < 1e-10:
		if LOGGER:
			LOGGER.warn("API: find_line_intersection — line_from and line_to are identical")
		return null
	var line_dir = delta.normalized()
	var tool = _tool()

	var ctx = _get_map_context(tool)
	var map_rect  = ctx[0]
	var cell_size = ctx[1]

	var best_point = null
	var best_dist  = radius
	var best_marker = null

	for marker in tool.markers:
		var candidates = []   # Vector2 intersection points to test

		match marker.marker_type:
			"Line":
				# Always test – drawn segments span the whole map
				var draw_data = marker.get_draw_data(map_rect, cell_size)
				if draw_data.has("segments"):
					for seg in draw_data["segments"]:
						var pt = GeometryUtils.line_intersect_segment(line_from, line_dir, seg[0], seg[1])
						if pt != null:
							candidates.append(pt)

			"Shape":
				var draw_data = marker.get_draw_data(map_rect, cell_size)
				if draw_data.has("primitives"):
					for prim in draw_data["primitives"]:
						if prim.type == "seg":
							var pt = GeometryUtils.line_intersect_segment(line_from, line_dir, prim.a, prim.b)
							if pt != null:
								candidates.append(pt)

			"Path":
				var pts = marker.marker_points
				if pts.size() >= 2:
					var edge_count = pts.size() - 1
					if marker.path_closed:
						edge_count = pts.size()
					for i in range(edge_count):
						var pt = GeometryUtils.line_intersect_segment(line_from, line_dir, pts[i], pts[(i + 1) % pts.size()])
						if pt != null:
							candidates.append(pt)

		# Keep only candidates within radius of coords; pick nearest to coords
		for pt in candidates:
			var dist = coords.distance_to(pt)
			if dist <= best_dist:
				best_dist   = dist
				best_point  = pt
				best_marker = marker

	if best_marker == null:
		if LOGGER:
			LOGGER.debug("API: find_line_intersection — no intersection found within radius %.1f of %s" % [radius, str(coords)])
		return null

	var result = _marker_save_with_pos(best_marker)
	result["point"]       = best_point
	result["distance"]    = best_dist
	result["on_positive"] = (best_point - line_from).dot(line_dir) >= 0.0
	result["marker_id"]   = best_marker.id
	result["marker_type"] = best_marker.marker_type
	if LOGGER:
		LOGGER.debug("API: find_line_intersection — id=%d type=%s point=%s dist=%.3f" % [
			best_marker.id, best_marker.marker_type, str(best_point), best_dist])
	return result

## Finds the nearest point on any marker's drawn geometry within [radius] world
## units of [coords].
##
## Unlike find_nearest_marker_by_geometry (which returns the marker with the
## closest geometry), this method returns the actual closest geometric point
## itself — the exact spot on the line/edge/circumference/path/shaft that is
## nearest to [coords].
##
## Returns a Dictionary on success (same format as find_line_intersection):
##   { "point":       Vector2  — world-space closest point on the geometry,
##     "distance":    float    — distance from [coords] to that point,
##     "marker_id":   int,
##     "marker_type": String,
##     + all keys from marker.Save() }
## Returns null if no marker geometry is found within the given radius.
##
## Parameters:
##   coords — world-space Vector2 origin of the search
##   radius — search radius in world units (default 100.0)
func find_nearest_geometry_point(coords: Vector2, radius: float = 100.0):
	var hit = _find_nearest_geometry(coords, radius, false)
	if hit == null:
		if LOGGER:
			LOGGER.debug("API: find_nearest_geometry_point — nothing found within radius %.1f of %s" % [radius, str(coords)])
		return null

	var best_marker = hit.marker
	var best_point = hit.point
	var best_dist = hit.distance
	var result = _marker_save_with_pos(best_marker)
	result["point"]       = best_point
	result["distance"]    = best_dist
	result["marker_id"]   = best_marker.id
	result["marker_type"] = best_marker.marker_type
	if LOGGER:
		LOGGER.debug("API: find_nearest_geometry_point — id=%d type=%s point=%s dist=%.3f" % [
			best_marker.id, best_marker.marker_type, str(best_point), best_dist])
	return result

# ============================================================================
# OVERLAY SETTINGS
# ============================================================================

## Enables or disables the proximity cross-guide overlay.
func set_cross_guides(enabled: bool) -> void:
	_mod._on_cross_guides_toggled(enabled)

## Enables or disables the permanent vertical center line.
func set_permanent_vertical(enabled: bool) -> void:
	_mod._on_perm_vertical_toggled(enabled)

## Enables or disables the permanent horizontal center line.
func set_permanent_horizontal(enabled: bool) -> void:
	_mod._on_perm_horizontal_toggled(enabled)

## Legacy setter: changes both permanent-guide and new-marker coordinate labels.
func set_show_coordinates(enabled: bool) -> void:
	# Legacy combined setter: permanent labels and new-marker labels.
	_mod._on_perm_coordinates_toggled(enabled)
	if _has_tool():
		_tool().set_show_coordinates(enabled)

## Sets only permanent-guide coordinate labels.
func set_permanent_coordinates(enabled: bool) -> void:
	_mod._on_perm_coordinates_toggled(enabled)

## Sets only coordinate labels on new Line markers.
func set_marker_coordinates(enabled: bool) -> void:
	if _has_tool():
		_tool().set_show_coordinates(enabled)

## Shows or hides all placed markers; synchronizes the tool checkbox.
func set_markers_visible(enabled: bool) -> void:
	_mod._on_markers_visible_toggled(enabled)

func get_markers_visible() -> bool:
	return _mod.markers_visible

## Sets the global opacity for all placed markers (0.0 = fully transparent, 1.0 = fully opaque).
## Sets global marker opacity in [0, 1]. Non-finite inputs are ignored.
func set_markers_opacity(value: float) -> void:
	_mod._on_markers_opacity_changed(value)

func get_markers_opacity() -> float:
	return _mod.markers_opacity

## Returns a snapshot of all current overlay/display settings.
## Dict keys: "cross_guides", "perm_vertical", "perm_horizontal",
##            "show_coordinates", "markers_visible", "markers_opacity"
## show_coordinates is the legacy permanent-guide flag; marker_coordinates is
## the independent flag for labels on new Line markers.
func get_settings() -> Dictionary:
	return {
		"cross_guides": _mod.cross_guides_enabled,
		"perm_vertical": _mod.perm_vertical_enabled,
		"perm_horizontal": _mod.perm_horizontal_enabled,
		"show_coordinates": _mod.show_coordinates_enabled, # Legacy permanent-label key
		"marker_coordinates": _tool().show_coordinates if _tool() else false,
		"markers_visible": _mod.markers_visible,
		"markers_opacity": _mod.markers_opacity,
	}

# ============================================================================
# TOOL CONTROL
# ============================================================================

## Activates the GuidesLines tool in Dungeondraft's toolset.
func activate_tool() -> void:
	if _mod.Global.Editor and _mod.Global.Editor.Toolset:
		_mod.Global.Editor.Toolset.Quickswitch("GuidesLinesTool")
		if LOGGER:
			LOGGER.debug("API: Tool activated")

## Returns true if the GuidesLines tool is currently the active tool.
func is_tool_active() -> bool:
	if not _mod.Global.Editor:
		return false
	return _mod.Global.Editor.ActiveToolName == "GuidesLinesTool"

## Returns true when the GuidesLines tool has been created and the API is ready
## to accept marker placement/deletion calls.
## This becomes true after a map is loaded and GuidesLines' update() has run.
func is_ready() -> bool:
	return _mod.guides_tool != null

# ============================================================================
# INTERNAL NOTIFICATION METHODS
# Called by GuidesLinesTool to propagate user actions to API signals
# ============================================================================

func _notify_marker_placed(marker_id: int, position: Vector2) -> void:
	emit_signal("marker_placed", marker_id, position)

func _notify_marker_deleted(marker_id: int) -> void:
	emit_signal("marker_deleted", marker_id)

func _notify_all_markers_deleted() -> void:
	emit_signal("all_markers_deleted")

# ============================================================================
# FILL POLYGON QUERIES
# ============================================================================

## Computes the fill polygon that would be produced if the user clicked at
## [coords] in Fill mode.  Uses the same logic as GuidesLinesFill:
##   - ONE shape contains coords  →  exclusive fill (primary minus overlaps)
##   - MULTIPLE shapes contain coords  →  intersection fill (A ∩ B ∩ C …)
##
## Returns a Dictionary on success:
##   { "polygon":    Array[Vector2]  — world-space polygon vertices,
##     "marker_ids": Array[int]      — ids of all Shape markers that contributed,
##     "fill_type":  String          — "exclusive" or "intersection" }
## Returns null if coords is not inside any Shape marker.
##
## Parameters:
##   coords — world-space Vector2 click position
func compute_fill_polygon(coords: Vector2):
	if not _has_tool():
		return null
	var tool = _tool()

	var cell_size = tool._get_grid_cell_size()
	if cell_size == null:
		if LOGGER:
			LOGGER.warn("API: compute_fill_polygon — cell_size unavailable (map not loaded?)")
		return null

	if tool._fill_handler == null:
		if LOGGER:
			LOGGER.warn("API: compute_fill_polygon — fill handler not ready")
		return null

	var hit_entries = tool._fill_handler._collect_hit_markers(coords, cell_size)
	if hit_entries.empty():
		if LOGGER:
			LOGGER.debug("API: compute_fill_polygon — no Shape marker hit at %s" % str(coords))
		return null

	var fill_poly = tool._fill_handler._compute_fill_polygon(coords, hit_entries)
	if fill_poly.empty():
		if LOGGER:
			LOGGER.debug("API: compute_fill_polygon — computed polygon is empty at %s" % str(coords))
		return null

	var marker_ids = []
	for entry in hit_entries:
		marker_ids.append(entry.marker.id)

	var fill_type = "exclusive" if hit_entries.size() == 1 else "intersection"

	if LOGGER:
		LOGGER.debug("API: compute_fill_polygon — type=%s hits=%d verts=%d at %s" % [
			fill_type, hit_entries.size(), fill_poly.size(), str(coords)])

	return {
		"polygon":    fill_poly,
		"marker_ids": marker_ids,
		"fill_type":  fill_type,
	}

## Returns the current polygon vertices of a Shape marker by [marker_id].
## The polygon reflects the marker's actual current outline — including any
## Clip / Cut / Difference / Merge modifications that have been applied.
##
## Returns a Dictionary on success:
##   { "polygon":     Array[Vector2]  — world-space polygon vertices (closed loop),
##     "marker_id":   int,
##     "marker_type": String }
## Returns null if the marker is not found or is not a Shape marker.
##
## Parameters:
##   marker_id — integer id of the Shape marker
func get_shape_polygon(marker_id: int):
	if not _has_tool():
		return null
	var tool = _tool()

	if not tool.markers_lookup.has(marker_id):
		if LOGGER:
			LOGGER.warn("API: get_shape_polygon — marker id %d not found" % marker_id)
		return null

	var marker = tool.markers_lookup[marker_id]
	if marker.marker_type != "Shape":
		if LOGGER:
			LOGGER.warn("API: get_shape_polygon — marker id %d is type '%s', not Shape" % [
				marker_id, marker.marker_type])
		return null

	var cell_size = tool._get_grid_cell_size()
	if cell_size == null:
		if LOGGER:
			LOGGER.warn("API: get_shape_polygon — cell_size unavailable (map not loaded?)")
		return null

	var desc = tool._get_shape_descriptor(marker, cell_size)
	if desc.empty():
		if LOGGER:
			LOGGER.warn("API: get_shape_polygon — could not build descriptor for marker id %d" % marker_id)
		return null

	if LOGGER:
		LOGGER.debug("API: get_shape_polygon — id=%d verts=%d" % [marker_id, desc.points.size()])

	return {
		"polygon":     desc.points,
		"marker_id":   marker_id,
		"marker_type": marker.marker_type,
	}

# ============================================================================
# TOOL STATE & PREVIEW
# ============================================================================

## Queues a one-frame Shape preview at [coords].
## The overlay retains it through that frame's draw passes, then clears it.
## Call this every frame (e.g. from _process) to keep the preview alive.
##
## Parameters:
##   coords — world-space Vector2 position of the shape centre
##   radius — circumradius in grid cells (default 1.0)
##   angle  — rotation in degrees (default 0.0)
##   sides  — number of polygon sides; 64 ≈ circle (default 6)
##   color  — preview color; use an alpha < 1 for transparency (default semi-transparent active color)
func set_shape_preview(coords: Vector2, radius: float = 1.0,
		angle: float = 0.0, sides: int = 6, color = null) -> void:
	if not _has_tool():
		return
	var tool = _tool()
	var c = color if color != null else Color(tool.active_color.r, tool.active_color.g, tool.active_color.b, 0.5)
	tool._api_preview_frame = Engine.get_idle_frames()
	tool._api_preview = {
		"pos":    coords,
		"radius": radius,
		"angle":  angle,
		"sides":  sides,
		"color":  c,
	}
	if tool.overlay:
		tool.overlay.update()

## Clears any pending API shape preview immediately.
func clear_shape_preview() -> void:
	if not _has_tool():
		return
	var tool = _tool()
	if not tool._api_preview.empty():
		tool._api_preview = {}
		if tool.overlay:
			tool.overlay.update()

## Returns a snapshot of the full current tool state as a Dictionary.
##
## Keys:
##   "ready"                  : bool   — false when the tool is not yet loaded
##   "active_marker_type"     : String — "Line" | "Shape" | "Path" | "Fill"
##   "active_angle"           : float  — Line angle in degrees
##   "active_mirror"          : bool   — Line mirror enabled
##   "active_shape_radius"    : float  — Shape circumradius in grid cells
##   "active_shape_angle"     : float  — Shape rotation in degrees
##   "active_shape_sides"     : int    — Shape polygon sides
##   "active_path_end_arrow"  : bool
##   "active_arrow_head_length": float — pixels
##   "active_arrow_head_angle" : float — degrees
##   "active_color"           : Color
##   "show_coordinates"       : bool
##   "delete_mode"            : bool
##   "merge_shapes"           : bool
##   "conforming_mode"        : bool
##   "wrapping_mode"          : bool
##   "difference_mode"        : bool
##   "marker_count"           : int
##   "fill_count"             : int
##   "path_placement_active"  : bool
##   "path_temp_point_count"  : int
func get_tool_state() -> Dictionary:
	if not _has_tool():
		return {"ready": false}
	var t = _tool()
	return {
		"ready":                    true,
		"active_marker_type":       t.active_marker_type,
		"active_angle":             t.active_angle,
		"active_mirror":            t.active_mirror,
		"active_shape_radius":      t.active_shape_radius,
		"active_shape_angle":       t.active_shape_angle,
		"active_shape_sides":       t.active_shape_sides,
		"active_path_end_arrow":    t.active_path_end_arrow,
		"active_arrow_head_length": t.active_arrow_head_length,
		"active_arrow_head_angle":  t.active_arrow_head_angle,
		"active_color":             t.active_color,
		"show_coordinates":         t.show_coordinates,
		"delete_mode":              t.delete_mode,
		"merge_shapes":             t.merge_shapes,
		"conforming_mode":          t.conforming_mode,
		"wrapping_mode":            t.wrapping_mode,
		"difference_mode":          t.difference_mode,
		"cut_mode":                 t.cut_mode,
		"move_mode":                t.move_mode,
		"active_shape_size_mode":   t.active_shape_size_mode,
		"active_shape_side":        t.active_shape_side,
		"active_template_index":    t.active_template_index,
		"template_capture_mode":    t.template_capture_mode,
		"marker_count":             t.markers.size(),
		"fill_count":               t.fills.size(),
		"path_placement_active":    t.path_placement_active,
		"path_temp_point_count":    t.path_temp_points.size(),
	}

# ============================================================================
# PRIVATE HELPERS
# ============================================================================

## Returns [map_rect, cell_size] for the current world, or [null, null] if no world loaded.
func _get_map_context(t) -> Array:
	if t.cached_world != null:
		return [t.cached_world.WorldRect, t._get_grid_cell_size()]
	return [null, null]

## Silent accessor — returns guides_tool or null without logging.
## Call only after _has_tool() has confirmed readiness.
func _tool():
	return _mod.guides_tool

func _has_tool() -> bool:
	if _tool() == null:
		if LOGGER:
			LOGGER.warn("API: Tool not ready yet (map not loaded?)")
		return false
	return true

## Build a public-facing marker dict from a GuideMarker instance.
## Equivalent to marker.Save() with position already as Vector2.
func _marker_save_with_pos(marker) -> Dictionary:
	var d = marker.Save()
	d["position"] = marker.position
	return d

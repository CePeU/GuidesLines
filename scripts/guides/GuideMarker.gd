extends Reference

const GeometryUtils = preload("../utils/GeometryUtils.gd")

# GuideMarker - Simple data class for guide markers
# Stored and managed by GuidesLinesTool

var position = Vector2.ZERO
var marker_type = "Line"  # Type of marker (Line, Shape, Path)
var angle = 0.0  # Line angle in degrees (0-360) [Line only]
var shape_radius = 1.0  # Shape radius in grid cells (circumradius) [Shape only]
var shape_angle = 0.0  # Shape rotation angle in degrees (0-360) [Shape only]
var shape_sides = 6  # Number of polygon sides [Shape only]
var marker_points = []  # Array of Vector2 points [Shape vertices/Path points]
var path_closed = false  # Whether path is closed (loop) [Path only]
var path_end_arrow = false  # Draw arrowhead at the last path point [Path only]
var arrow_head_length = 50.0  # Arrowhead length in pixels [Path only, when path_end_arrow]
var arrow_head_angle = 30.0  # Arrowhead angle in degrees [Path only, when path_end_arrow]
var color = Color(0, 0.7, 1, 1)  # Line/Shape/Path color
var mirror = false  # Mirror line at 180 degrees [Line only]
var id = -1  # Unique identifier
var show_coordinates = false  # Show grid coordinates on Line markers only

const MARKER_SIZE = 10.0  # Doubled size
const MARKER_COLOR = Color(1, 0, 0, 1)  # Red
const DEFAULT_LINE_COLOR = Color(0, 0.7, 1, 1)  # Blue (fully opaque)
const LINE_WIDTH = 5.0  # Thicker lines

# CACHED GEOMETRY — single source of truth for all current geometric data.
# Structure for Shape:
#   "type":        "shape"
#   "shape_type":  "poly"
#
#   "primitives":  Array[{"type":"seg","a":V2,"b":V2}]
#     The ONLY authoritative list of segments — outline AND all Difference boundary
#     segments mixed together.  Set once on fresh placement (full polygon edges)
#     and then modified IN-PLACE by each Clip / Cut / Difference op.
#     Never rebuilt from original parameters — use undo snapshots to revert.
var cached_draw_data = {}
var _dirty = true
var _cached_map_rect = Rect2()  # Tracks map_rect for Line cache invalidation

# CACHED COORDINATE POINTS — pre-computed grid intersections for show_coordinates.
# Rebuilt only when marker properties or map/snap params change.
# Each entry: { "grid_pos": Vector2, "text": String, "perp": Vector2 }
# "perp" is the normalised perpendicular to the line — text_pos = grid_pos + perp * text_offset,
# where text_offset is zoom-dependent and applied at draw time.
var cached_coord_points = []
var _coord_dirty = true
var _cached_coord_map_rect   = Rect2()
var _cached_coord_cell_size  = null
var _cached_coord_snap_enabled   = false
var _cached_coord_snap_interval  = Vector2.ZERO

# CACHED DRAW COLORS — pre-multiplied with global opacity so _draw never allocs Color.
# Call update_opacity() whenever opacity or marker.color changes.
var draw_color = Color(0, 0.7, 1, 1)        # color * opacity
var draw_marker_color = Color(1, 0, 0, 1)   # MARKER_COLOR * opacity
var draw_arc_color = Color(0, 0, 0, 1)      # black * opacity (outline arc)

# Initialize marker with position and type-specific parameters
func _init(pos = Vector2.ZERO, _angle = 0.0, _mirror = false, coords = false):
	position = pos
	angle = _angle
	shape_radius = 1.0  # Default Shape radius
	shape_angle = 0.0  # Default Shape angle
	shape_sides = 6  # Default sides
	mirror = _mirror
	show_coordinates = coords
	color = DEFAULT_LINE_COLOR
	_dirty = true
	_coord_dirty = true

# Refresh cached draw colors for the given global opacity (0.0–1.0).
# Call once after the marker is created / color is changed / opacity setting changes.
func update_opacity(opacity: float) -> void:
	draw_color        = Color(color.r, color.g, color.b, color.a * opacity)
	draw_marker_color = Color(MARKER_COLOR.r, MARKER_COLOR.g, MARKER_COLOR.b, MARKER_COLOR.a * opacity)
	draw_arc_color    = Color(0, 0, 0, opacity)

# Rebuild cached coordinate points from scratch.
# map_rect, cell_size and custom_snap come from the overlay (computed once per frame).
func rebuild_coord_cache(map_rect: Rect2, cell_size, custom_snap) -> void:
	cached_coord_points = []
	_cached_coord_map_rect  = map_rect
	_cached_coord_cell_size = cell_size
	_cached_coord_snap_enabled   = custom_snap != null and custom_snap.custom_snap_enabled
	_cached_coord_snap_interval  = custom_snap.snap_interval if _cached_coord_snap_enabled else Vector2.ZERO
	_coord_dirty = false

	if marker_type != "Line":
		return

	var angles_list = [angle]
	if mirror:
		angles_list.append(fposmod(angle + 180.0, 360.0))

	for ang in angles_list:
		var angle_rad = deg2rad(ang)
		var direction = Vector2(cos(angle_rad), sin(angle_rad))
		var perp      = Vector2(-direction.y, direction.x)  # unit perpendicular
		if _cached_coord_snap_enabled:
			_build_coord_points_custom_snap(direction, perp, map_rect, custom_snap)
		else:
			_build_coord_points_vanilla(direction, perp, map_rect, cell_size)

func _build_coord_points_vanilla(direction: Vector2, perp: Vector2, map_rect: Rect2, cell_size) -> void:
	if cell_size == null or cell_size.x <= 0 or cell_size.y <= 0:
		return
	var step     = min(cell_size.x, cell_size.y)
	var segment = GeometryUtils.get_ray_to_rect_edge(position, direction, map_rect)
	if segment[0] == segment[1]:
		return
	var max_dist = position.distance_to(segment[1])
	# Keep the sample lattice anchored at the marker, including off-map origins.
	var distance = max(1.0, ceil(position.distance_to(segment[0]) / step)) * step
	while distance <= max_dist:
		var test_pos = position + direction * distance
		if not map_rect.has_point(test_pos):
			distance += step
			continue
		var grid_x   = round(test_pos.x / cell_size.x)
		var grid_y   = round(test_pos.y / cell_size.y)
		var grid_pos = Vector2(grid_x * cell_size.x, grid_y * cell_size.y)
		if test_pos.distance_to(grid_pos) < step * 0.25:
			var grid_dist = round(distance / step)
			cached_coord_points.append({
				"grid_pos": grid_pos,
				"text":     str(int(grid_dist)),
				"perp":     perp
			})
		distance += step

func _build_coord_points_custom_snap(direction: Vector2, perp: Vector2, map_rect: Rect2, custom_snap) -> void:
	var snap_interval = custom_snap.snap_interval
	if snap_interval.x <= 0 or snap_interval.y <= 0:
		return
	var test_spacing  = min(snap_interval.x, snap_interval.y) * 0.5
	var max_dist      = map_rect.size.length()
	var checked       = {}
	var distance      = test_spacing
	while distance < max_dist:
		var test_pos = position + direction * distance
		var snapped  = custom_snap.get_snapped_position(test_pos)
		if not map_rect.has_point(snapped):
			distance += test_spacing
			continue
		var key = Vector2(int(snapped.x * 10), int(snapped.y * 10))
		if not checked.has(key):
			if GeometryUtils.is_point_on_ray(position, direction, snapped, deg2rad(5.0)):
				checked[key] = true
				var grid_dist = round(snapped.distance_to(position) / min(snap_interval.x, snap_interval.y))
				cached_coord_points.append({
					"grid_pos": snapped,
					"text":     str(int(grid_dist)),
					"perp":     perp
				})
		distance += test_spacing

# Set a property and mark geometry as dirty if needed
func set_property(prop, value):
	var changed = false
	match prop:
		"angle": 
			if angle != value: angle = value; changed = true
		"shape_radius":
			if shape_radius != value: shape_radius = value; changed = true
		"shape_angle":
			if shape_angle != value: shape_angle = value; changed = true
		"shape_sides":
			if shape_sides != value: shape_sides = value; changed = true
		"position":
			if position != value:
				var delta = value - position
				if marker_type == "Shape" and cached_draw_data.has("primitives"):
					var segments = get_primitives().duplicate(true)
					for seg in segments:
						seg.a += delta
						seg.b += delta
					set_primitives(segments)
				elif marker_type == "Path":
					for i in range(marker_points.size()):
						marker_points[i] += delta
				position = value
				changed = true
		"mirror":
			if mirror != value: mirror = value; changed = true
		"marker_type":
			if marker_type != value: marker_type = value; changed = true
		"path_closed":
			if path_closed != value: path_closed = value; changed = true
		"arrow_head_length":
			if arrow_head_length != value: arrow_head_length = value; changed = true
		"arrow_head_angle":
			if arrow_head_angle != value: arrow_head_angle = value; changed = true
		"path_end_arrow":
			if path_end_arrow != value: path_end_arrow = value; changed = true
		"show_coordinates":
			if show_coordinates != value: show_coordinates = value; changed = true
		"marker_points":
			# Arrays are passed by reference, so we assume it changed if set
			marker_points = value; changed = true
	
	if changed:
		_dirty = true
		match prop:
			"angle", "position", "mirror", "show_coordinates":
				_coord_dirty = true

# Generate geometry data based on current settings
# map_rect: Rectangle of the map (used for infinite line clipping)
# cell_size: Vector2 of grid cell size (used for shape scaling)
func get_draw_data(map_rect, cell_size):
	if _dirty or cached_draw_data.empty():
		_recalculate_geometry(map_rect, cell_size)
	elif marker_type == "Line" and map_rect != null and map_rect != _cached_map_rect:
		# map_rect changed (different map loaded) — rebuild line endpoints
		_recalculate_geometry(map_rect, cell_size)
	return cached_draw_data

## Reset to the full unclipped outline.
## Clears Clip/Cut/Difference state; the next get_draw_data() rebuilds primitives
## from shape parameters (because the primitives key is now absent).
func clear_clip():
	cached_draw_data.erase("primitives")
	cached_draw_data.erase("polygon")
	_dirty = true

## Set the current segments (outline + diff fills merged into one list).
## Called by GuidesLinesTool after any Clip / Cut / Difference operation.
func set_primitives(segs: Array):
	cached_draw_data["primitives"] = segs
	cached_draw_data.erase("polygon")
	cached_draw_data.erase("bounds")

## Get the current segments.
func get_primitives() -> Array:
	return cached_draw_data.get("primitives", [])

# Derived from actual geometry, never the original radius or current anchor.
func get_geometry_bounds(map_rect, cell_size):
	var data = get_draw_data(map_rect, cell_size)
	if not data.has("bounds"):
		var points = []
		if marker_type == "Shape":
			for primitive in get_primitives():
				if primitive.type == "seg":
					points.append(primitive.a)
					points.append(primitive.b)
		elif marker_type == "Path":
			points = marker_points
		var bounds = null
		if not points.empty():
			bounds = GeometryUtils.polygon_intersection_bounds(points)
		data["bounds"] = bounds
	return data["bounds"]

# Derived geometry only; callers replace segments through set_primitives().
func get_polygon() -> Array:
	if not cached_draw_data.has("polygon"):
		cached_draw_data["polygon"] = GeometryUtils.chain_segments_to_polygon(get_primitives())
	return cached_draw_data["polygon"]

func _recalculate_geometry(map_rect, cell_size):
	# Preserve primitives across recalculation so Clip/Cut/Difference results
	# survive unrelated property changes (e.g. colour, show_coordinates).
	# An explicit empty outline is valid after clipping; only absence means fresh.
	var has_saved_primitives = cached_draw_data.has("primitives")
	var saved_primitives = cached_draw_data.get("primitives", [])
	cached_draw_data = {}

	if marker_type == "Line" and map_rect != null:
		_cached_map_rect = map_rect
		cached_draw_data["type"] = "line"
		cached_draw_data["segments"] = []
		
		var angles_list = [angle]
		if mirror: angles_list.append(fposmod(angle + 180.0, 360.0))
		
		for ang in angles_list:
			var dir = Vector2(cos(deg2rad(ang)), sin(deg2rad(ang)))
			var segment = GeometryUtils.get_ray_to_rect_edge(position, dir, map_rect)
			if segment:
				cached_draw_data["segments"].append(segment)

	elif marker_type == "Shape":
		cached_draw_data["type"]       = "shape"
		cached_draw_data["shape_type"] = "poly"
		if cell_size:
			if has_saved_primitives:
				# Restore previously modified state (Clip / Cut / Difference applied).
				cached_draw_data["primitives"] = saved_primitives
			else:
				# Fresh shape — build full polygon outline from parameters.
				var radius_px = shape_radius * min(cell_size.x, cell_size.y)
				var angle_rad = deg2rad(shape_angle)
				var pts = GeometryUtils.calculate_polygon_vertices(position, radius_px, shape_sides, angle_rad)
				cached_draw_data["primitives"] = GeometryUtils.points_to_segs(pts)
				cached_draw_data["polygon"] = pts
		else:
			# cell_size unavailable — preserve whatever state existed.
			if has_saved_primitives:
				cached_draw_data["primitives"] = saved_primitives
	_dirty = marker_type == "Shape" and not cached_draw_data.has("primitives")

# Serialize marker data for JSON and undo snapshots.
func Save():
	var data = {
		"position": [position.x, position.y],
		"marker_type": marker_type,
		"color": "#" + color.to_html(),
		"id": id,
		"show_coordinates": show_coordinates
	}
	
	# Add type-specific parameters
	if marker_type == "Line":
		data["angle"] = angle
		data["mirror"] = mirror
	elif marker_type == "Shape":
		data["shape_radius"] = shape_radius
		data["shape_angle"] = shape_angle
		data["shape_sides"] = shape_sides
		if cached_draw_data.has("primitives"):
			data["shape_primitives"] = []
			for seg in get_primitives():
				data["shape_primitives"].append({"a": [seg.a.x, seg.a.y], "b": [seg.b.x, seg.b.y]})
	elif marker_type == "Path":
		# Serialize path points
		var points_data = []
		for point in marker_points:
			points_data.append([point.x, point.y])
		data["marker_points"] = points_data
		data["path_closed"] = path_closed
		data["path_end_arrow"] = path_end_arrow
		if path_end_arrow:
			data["arrow_head_length"] = arrow_head_length
			data["arrow_head_angle"] = arrow_head_angle
	
	return data

# Deserialize marker data from map file (current format only)
func Load(data):
	# Validate the new JSON geometry before replacing any existing marker state.
	var primitives = []
	if data.get("marker_type", "Line") == "Shape" and data.has("shape_primitives"):
		if not data["shape_primitives"] is Array:
			return false
		for seg in data["shape_primitives"]:
			if not seg is Dictionary:
				return false
			for key in ["a", "b"]:
				var point = seg.get(key)
				if not point is Array or point.size() != 2:
					return false
				for coordinate in point:
					if not (coordinate is int or coordinate is float):
						return false
					if is_nan(float(coordinate)) or is_inf(float(coordinate)):
						return false
			primitives.append({"type": "seg", "a": Vector2(seg.a[0], seg.a[1]), "b": Vector2(seg.b[0], seg.b[1])})
	cached_draw_data = {}
	if data.has("position"):
		position = Vector2(data.position[0], data.position[1])
	
	if data.has("marker_type"):
		marker_type = data.marker_type
	else:
		marker_type = "Line"
	
	# Load type-specific parameters
	if marker_type == "Line":
		if data.has("angle"):
			angle = data.angle
		else:
			angle = 0.0
		
		if data.has("mirror"):
			mirror = data.mirror
		else:
			mirror = false
	elif marker_type == "Shape":
		shape_radius  = data.get("shape_radius", 1.0)
		shape_angle   = data.get("shape_angle", 0.0)
		shape_sides   = data.get("shape_sides", 6)
		if data.has("shape_primitives"):
			set_primitives(primitives)
		marker_points = []
	elif marker_type == "Path":
		if data.has("marker_points"):
			marker_points = []
			for point_data in data.marker_points:
				marker_points.append(Vector2(point_data[0], point_data[1]))
		else:
			marker_points = []
		
		path_closed = data.get("path_closed", false)
		path_end_arrow = data.get("path_end_arrow", false)
		if path_end_arrow:
			arrow_head_length = data.get("arrow_head_length", 50.0)
			arrow_head_angle = data.get("arrow_head_angle", 30.0)
	
	# Common parameters
	if data.has("color"):
		if data.color is String:
			color = Color(data.color.lstrip("#"))
		else:
			color = data.color
	else:
		color = DEFAULT_LINE_COLOR
	
	if data.has("id"):
		id = data.id
	else:
		id = -1
	
	if data.has("show_coordinates"):
		show_coordinates = data.show_coordinates
	else:
		show_coordinates = false		
	_dirty = true       # Invalidate geometry cache
	_coord_dirty = true # Invalidate coordinate cache
	return true

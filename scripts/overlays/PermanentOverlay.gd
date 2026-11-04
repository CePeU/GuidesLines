extends Node2D

const GuidesLinesRender = preload("../render/GuidesLinesRender.gd")

# PermanentOverlay - Displays permanent guide lines
# Shows blue guide lines that can be toggled on/off

var parent_mod = null
var cached_world = null
var cached_camera = null
var cached_snappy_mod = null  # Custom_snap mod reference (if available)

# Performance optimization: only redraw when camera changes
var _last_camera_pos = Vector2.ZERO
var _last_camera_zoom = Vector2.ONE
var _last_perm_v_enabled = false
var _last_perm_h_enabled = false
var _last_show_coords = false
var _last_viewport_rect = Rect2()
var _last_grid_state = []
const CENTER_COLOR = Color(1, 0, 0, 0.8)

# Performance optimization: iteration limits
const MAX_COORD_MARKERS = 100  # Maximum coordinate markers for vanilla grid
const MAX_ITERATIONS = 1000  # Maximum iterations for custom_snap grid

var _cached_font = null # Optim: Cache font resource
var _coord_checked_v = {}  # Optim: reuse dict to avoid per-frame allocation
var _coord_checked_h = {}  # Optim: reuse dict to avoid per-frame allocation

# Optim: Cache map center — WorldRect changes rarely (like CrossOverlay pattern)
var _cached_raw_map_cx: float = 0.0
var _cached_raw_map_cy: float = 0.0
var _cached_map_rect_perm: Rect2 = Rect2(0, 0, -1, -1)

# Optim: Cache coordinate draw points — rebuilt only when world/viewport params change
var _perm_coord_cache_v = []   # Array of {pos: Vector2, text: String, text_dir: Vector2}
var _perm_coord_cache_h = []
var _perm_coord_cache_wt   = -INF  # world_top at last build
var _perm_coord_cache_wb   =  INF  # world_bottom
var _perm_coord_cache_wl   = -INF  # world_left
var _perm_coord_cache_wr   =  INF  # world_right
var _perm_coord_cache_cx   = 0.0   # map_cx
var _perm_coord_cache_cy   = 0.0   # map_cy
var _perm_coord_cache_snap_en = false
var _perm_coord_cache_snap_iv = Vector2.ZERO

func _ready():
	set_z_index(99)
	set_process(true)  # Enable _process for camera change detection
	
	# Optim: Get font once, effectively resolving memory leak
	var temp_control = Control.new()
	_cached_font = temp_control.get_font("font")
	temp_control.free()

# Update cached map center and rect — WorldRect changes rarely
# Returns true if the cache was updated (map changed)
func _update_map_cache() -> bool:
	if not cached_world:
		return false
	var rect = cached_world.WorldRect
	if rect == _cached_map_rect_perm:
		return false
	_cached_map_rect_perm = rect
	_cached_raw_map_cx = rect.position.x + rect.size.x * 0.5
	_cached_raw_map_cy = rect.position.y + rect.size.y * 0.5
	# Invalidate coord cache when map changes
	_perm_coord_cache_wt = -INF
	return true

# Check for camera changes and trigger redraw only when needed
func _process(_delta):
	if cached_camera and parent_mod:
		var cam_pos = cached_camera.get_camera_position()
		var cam_zoom = cached_camera.zoom
		var perm_v = parent_mod.perm_vertical_enabled
		var perm_h = parent_mod.perm_horizontal_enabled
		var show_coords = parent_mod.show_coordinates_enabled
		var map_changed = _update_map_cache()
		var viewport_rect = get_viewport_rect()
		var grid_state = _get_grid_state()
		var grid_changed = grid_state != _last_grid_state
		if grid_changed or perm_v != _last_perm_v_enabled or perm_h != _last_perm_h_enabled:
			_perm_coord_cache_wt = -INF
		
		# Only redraw if something changed
		if map_changed or cam_pos != _last_camera_pos or cam_zoom != _last_camera_zoom or \
		   perm_v != _last_perm_v_enabled or perm_h != _last_perm_h_enabled or \
		   show_coords != _last_show_coords or viewport_rect != _last_viewport_rect or grid_changed:
			_last_camera_pos = cam_pos
			_last_camera_zoom = cam_zoom
			_last_perm_v_enabled = perm_v
			_last_perm_h_enabled = perm_h
			_last_show_coords = show_coords
			_last_viewport_rect = viewport_rect
			_last_grid_state = grid_state
			update()

# Draw permanent guide lines at map center
# Shows blue lines that can be toggled on/off
func _draw():
	if parent_mod == null:
		return
	if not (parent_mod.perm_vertical_enabled or parent_mod.perm_horizontal_enabled):
		return
	if cached_world == null or cached_camera == null:
		return
	
	# Use cached center — WorldRect rarely changes, updated in _process via _update_map_cache()
	var map_cx = _cached_raw_map_cx
	var map_cy = _cached_raw_map_cy
	
	# Adjust center to nearest grid node if custom_snap is enabled
	var custom_snap = _get_custom_snap()
	if custom_snap and custom_snap.custom_snap_enabled:
		var center_pos = Vector2(map_cx, map_cy)
		var snapped_center = custom_snap.get_snapped_position(center_pos)
		map_cx = snapped_center.x
		map_cy = snapped_center.y
	
	var cam_pos = cached_camera.get_camera_position()
	var cam_zoom = cached_camera.zoom
	var vp_rect = get_viewport_rect()
	
	var world_width = vp_rect.size.x * cam_zoom.x
	var world_height = vp_rect.size.y * cam_zoom.y
	var world_left = cam_pos.x - world_width * 0.5
	var world_right = cam_pos.x + world_width * 0.5
	var world_top = cam_pos.y - world_height * 0.5
	var world_bottom = cam_pos.y + world_height * 0.5
	
	if parent_mod.perm_vertical_enabled:
		GuidesLinesRender.draw_adaptive_line(
			self,
			Vector2(map_cx, world_top),
			Vector2(map_cx, world_bottom),
			parent_mod.PERM_LINE_COLOR,
			parent_mod.PERM_LINE_WIDTH,
			cam_zoom
		)
	
	if parent_mod.perm_horizontal_enabled:
		GuidesLinesRender.draw_adaptive_line(
			self,
			Vector2(world_left, map_cy),
			Vector2(world_right, map_cy),
			parent_mod.PERM_LINE_COLOR,
			parent_mod.PERM_LINE_WIDTH,
			cam_zoom
		)

	
	# Draw red center marker
	if parent_mod.perm_vertical_enabled or parent_mod.perm_horizontal_enabled:
		var center_marker_size = GuidesLinesRender.get_adaptive_width(5.0, cam_zoom)
		draw_circle(Vector2(map_cx, map_cy), center_marker_size, CENTER_COLOR)
	
	# Draw grid coordinates if enabled
	if parent_mod.show_coordinates_enabled and (parent_mod.perm_vertical_enabled or parent_mod.perm_horizontal_enabled):
		_draw_grid_coordinates(map_cx, map_cy, world_left, world_right, world_top, world_bottom, cam_zoom)

# Draw grid coordinates along the guide lines
# Shows grid node markers and distance numbers from map center
func _draw_grid_coordinates(map_cx, map_cy, world_left, world_right, world_top, world_bottom, cam_zoom):
	var custom_snap   = _get_custom_snap()
	var snap_enabled  = custom_snap != null and custom_snap.custom_snap_enabled
	var snap_interval = custom_snap.snap_interval if snap_enabled else Vector2.ZERO
	
	# Rebuild coord point cache only when relevant params change
	if world_top    != _perm_coord_cache_wt  or \
	   world_bottom != _perm_coord_cache_wb  or \
	   world_left   != _perm_coord_cache_wl  or \
	   world_right  != _perm_coord_cache_wr  or \
	   map_cx       != _perm_coord_cache_cx  or \
	   map_cy       != _perm_coord_cache_cy  or \
	   snap_enabled != _perm_coord_cache_snap_en or \
	   snap_interval != _perm_coord_cache_snap_iv:
		_perm_coord_cache_wt = world_top
		_perm_coord_cache_wb = world_bottom
		_perm_coord_cache_wl = world_left
		_perm_coord_cache_wr = world_right
		_perm_coord_cache_cx = map_cx
		_perm_coord_cache_cy = map_cy
		_perm_coord_cache_snap_en = snap_enabled
		_perm_coord_cache_snap_iv = snap_interval
		_rebuild_perm_coord_cache(map_cx, map_cy, world_left, world_right, world_top, world_bottom, custom_snap, snap_enabled)
	
	if _perm_coord_cache_v.empty() and _perm_coord_cache_h.empty():
		return
	
	# Draw from cache — only zoom-dependent sizes computed here
	var marker_size  = GuidesLinesRender.get_adaptive_width(5.0, cam_zoom)
	var text_offset  = GuidesLinesRender.get_adaptive_width(20.0, cam_zoom)
	var marker_color = parent_mod.PERM_LINE_COLOR
	var text_color   = parent_mod.PERM_LINE_COLOR
	for point in _perm_coord_cache_v:
		draw_circle(point.pos, marker_size, marker_color)
		_draw_text_with_outline(point.text, point.pos + point.text_dir * text_offset, text_color)
	for point in _perm_coord_cache_h:
		draw_circle(point.pos, marker_size, marker_color)
		_draw_text_with_outline(point.text, point.pos + point.text_dir * text_offset, text_color)

# Draw text with outline for better visibility
func _draw_text_with_outline(text, position, color):
	GuidesLinesRender.draw_text_with_outline(self, text, position, color, _cached_font)


# Get custom_snap mod reference if available
func _get_custom_snap():
	return cached_snappy_mod

# Rebuild coordinate point caches for both guide lines.
# Populates _perm_coord_cache_v and _perm_coord_cache_h.
# Called only when world/viewport params change between frames.
func _rebuild_perm_coord_cache(map_cx, map_cy, world_left, world_right, world_top, world_bottom, custom_snap, snap_enabled) -> void:
	_perm_coord_cache_v.clear()
	_perm_coord_cache_h.clear()
	var center = Vector2(map_cx, map_cy)
	var low = Vector2(world_left, world_top)
	var high = Vector2(world_right, world_bottom)
	if parent_mod.perm_vertical_enabled:
		_build_coord_axis(1, center, low, high, custom_snap, snap_enabled, _perm_coord_cache_v, _coord_checked_v)
	if parent_mod.perm_horizontal_enabled:
		_build_coord_axis(0, center, low, high, custom_snap, snap_enabled, _perm_coord_cache_h, _coord_checked_h)

func _build_coord_axis(axis: int, center: Vector2, low: Vector2, high: Vector2, snap, snap_enabled: bool, points: Array, checked: Dictionary) -> void:
	var text_dir = Vector2(1, 0) if axis == 1 else Vector2(0, -1)
	var map_rect = _cached_map_rect_perm
	if snap_enabled:
		var interval = snap.snap_interval
		var spacing = min(interval.x, interval.y) * 0.5
		if spacing <= 0.0:
			return
		checked.clear()
		var coordinate = low[axis]
		var iterations = 0
		# ponytail: bound sampling to MAX_ITERATIONS; enumerate grid nodes if larger views need labels.
		while coordinate <= high[axis] and iterations < MAX_ITERATIONS:
			var test_pos = center
			test_pos[axis] = coordinate
			var snapped = snap.get_snapped_position(test_pos)
			var key = int(snapped[axis] * 10)
			if abs(snapped[1 - axis] - center[1 - axis]) < 0.5 and abs(snapped[axis] - center[axis]) > 0.5:
				if not checked.has(key) and map_rect.has_point(snapped):
					checked[key] = true
					var delta = snapped - center - snap.snap_offset
					points.append({"pos": snapped, "text": str(int(round(abs(delta[axis]) / interval[axis]))), "text_dir": text_dir})
			coordinate += spacing
			iterations += 1
		if iterations >= MAX_ITERATIONS and parent_mod.LOGGER:
			parent_mod.LOGGER.warn("Coordinate drawing exceeded iteration limit (axis %d)" % axis)
	else:
		if not cached_world or not cached_world.Level or not cached_world.Level.TileMap:
			return
		var cell = cached_world.Level.TileMap.CellSize
		if cell == null or cell.x <= 0 or cell.y <= 0:
			return
		var spacing = cell[axis]
		if int((high[axis] - low[axis]) / spacing) + 1 > MAX_COORD_MARKERS:
			return
		var coordinate = floor((low[axis] - center[axis]) / spacing) * spacing + center[axis]
		var iterations = 0
		while coordinate <= high[axis] and iterations < MAX_COORD_MARKERS:
			var point = center
			point[axis] = coordinate
			if abs(coordinate - center[axis]) > 0.1 and map_rect.has_point(point):
				points.append({"pos": point, "text": str(abs(int(round((coordinate - center[axis]) / spacing)))), "text_dir": text_dir})
			coordinate += spacing
			iterations += 1

func _get_grid_state() -> Array:
	var cell = null
	if cached_world and cached_world.Level and cached_world.Level.TileMap:
		cell = cached_world.Level.TileMap.CellSize
	var snap = _get_custom_snap()
	if snap == null or not snap.custom_snap_enabled:
		return [cell, false]
	return [cell, snap, true, snap.snap_interval, snap.snap_offset, snap.active_geometry, snap.radial_mode_to_corner]

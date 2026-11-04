extends Node2D

const GuidesLinesRender = preload("../render/GuidesLinesRender.gd")

# CrossOverlay - Displays proximity-based guide lines
# Shows red guide lines when cursor is near the map center

var parent_mod = null
var cached_world = null
var cached_camera = null

# Performance optimization: only redraw when camera or state changes
var _last_camera_pos = Vector2.ZERO
var _last_camera_zoom = Vector2.ONE
var _last_cross_show_v = false
var _last_cross_show_h = false

# Cache map dimensions and calculated lines
var _map_center = Vector2.ZERO
var _last_map_rect = Rect2(0, 0, -1, -1) # Initialize with invalid rect to force update
# Cached line coordinates (start and end points)
var _v_line_start = Vector2.ZERO
var _v_line_end = Vector2.ZERO
var _h_line_start = Vector2.ZERO
var _h_line_end = Vector2.ZERO

func _ready():
	set_z_index(100)
	set_process(true)  # Enable _process for camera change detection
	_update_map_cache()

# Update cached map dimensions
func _update_map_cache():
	if cached_world:
		var rect = cached_world.WorldRect
		# Only update if changed
		if rect != _last_map_rect:
			_last_map_rect = rect
			_map_center = rect.position + rect.size * 0.5
			# Pre-calculate line coordinates
			var cx = _map_center.x
			var cy = _map_center.y
			var top = rect.position.y
			var bottom = rect.position.y + rect.size.y
			var left = rect.position.x
			var right = rect.position.x + rect.size.x
			
			_v_line_start = Vector2(cx, top)
			_v_line_end = Vector2(cx, bottom)
			_h_line_start = Vector2(left, cy)
			_h_line_end = Vector2(right, cy)
			return true
	return false

# Check for camera changes and trigger redraw only when needed
func _process(_delta):
	if cached_camera and parent_mod:
		var cam_pos = cached_camera.get_camera_position()
		var cam_zoom = cached_camera.zoom
		var cross_v = parent_mod.cross_show_v
		var cross_h = parent_mod.cross_show_h
		
		# Check if map size changed (rare but possible)
		var map_changed = _update_map_cache()
		
		# Only redraw if something changed
		if map_changed or cam_pos != _last_camera_pos or cam_zoom != _last_camera_zoom or \
		   cross_v != _last_cross_show_v or cross_h != _last_cross_show_h:
			_last_camera_pos = cam_pos
			_last_camera_zoom = cam_zoom
			_last_cross_show_v = cross_v
			_last_cross_show_h = cross_h
			
			update()

# Draw proximity-based cross guides
# Shows red lines when cursor is near map center
func _draw():
	if parent_mod == null:
		return
	if not (parent_mod.cross_show_v or parent_mod.cross_show_h):
		return
	
	# Draw lines spanning the full map dimensions
	# Godot handles viewport culling efficiently, no need for manual clipping
	var cam_zoom = cached_camera.zoom
	
	if parent_mod.cross_show_v:
		GuidesLinesRender.draw_adaptive_line(
			self,
			_v_line_start,
			_v_line_end,
			parent_mod.CROSS_LINE_COLOR,
			parent_mod.CROSS_LINE_WIDTH,
			cam_zoom
		)
	
	if parent_mod.cross_show_h:
		GuidesLinesRender.draw_adaptive_line(
			self,
			_h_line_start,
			_h_line_end,
			parent_mod.CROSS_LINE_COLOR,
			parent_mod.CROSS_LINE_WIDTH,
			cam_zoom
		)

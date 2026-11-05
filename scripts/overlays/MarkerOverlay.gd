extends Node2D

const GeometryUtils = preload("../utils/GeometryUtils.gd")
const GuidesLinesRender = preload("../render/GuidesLinesRender.gd")

# MarkerOverlay - Handles drawing and input for guide markers

var tool = null

# Performance optimization: track when redraw is needed
var _last_camera_pos = Vector2.ZERO
var _last_camera_zoom = Vector2.ONE
var _last_marker_count = 0
var _last_fill_count = 0
var _last_path_active = false
var _last_mouse_pos = Vector2.ZERO  # Track mouse position for preview updates
var _mouse_in_ui = false  # Track if cursor is in UI area
var _api_preview_frame = -1

# Preview marker constants (matching GuideMarker constants)
const PREVIEW_MARKER_SIZE = 10.0  # Base size before zoom adaptation
const PREVIEW_LINE_WIDTH = 5.0    # Base width before zoom adaptation

# Static Color constants — avoids per-frame allocations in preview methods
const _PREVIEW_MARKER_COLOR      = Color(1, 0, 0, 0.5)
const _PREVIEW_ARC_COLOR         = Color(0, 0, 0, 0.5)
const _PATH_PREVIEW_LINE_COLOR   = Color(1, 1, 1, 0.5)
const _PATH_PREVIEW_FIRST_COLOR  = Color(0, 1, 0, 0.6)
const _PATH_PREVIEW_CURSOR_COLOR = Color(1, 1, 1, 0.3)

var _cached_font = null # Optim: Cache font resource

func _ready():
	set_process_input(true)
	set_process(true)
	
	# Optim: Get font once
	var temp_control = Control.new()
	_cached_font = temp_control.get_font("font")
	temp_control.free()

# Continuously update mouse position for path preview
func _process(_delta):
	var needs_update = false
	
	# Track mouse position for path preview
	if tool and tool.path_placement_active and tool.cached_worldui and tool.cached_worldui.IsInsideBounds:
		tool.path_preview_point = tool.cached_worldui.MousePosition
		needs_update = true  # Always update during path placement
	
	# Track mouse position for preview marker (when tool is enabled and not in delete mode)
	if tool and tool.is_enabled and not tool.delete_mode and tool.cached_worldui and tool.cached_worldui.IsInsideBounds:
		var current_mouse_pos = tool.cached_worldui.MousePosition
		var new_mouse_in_ui = not _is_mouse_over_canvas()
		
		# If mouse moved between UI and world, or position changed in world
		if new_mouse_in_ui != _mouse_in_ui:
			# Mouse crossed UI boundary - force update
			_mouse_in_ui = new_mouse_in_ui
			needs_update = true
		elif not _mouse_in_ui:
			# Mouse in world - check if position changed
			if current_mouse_pos != _last_mouse_pos:
				_last_mouse_pos = current_mouse_pos
				needs_update = true
	else:
		# Mouse left the bounds - clear preview if needed
		if not _mouse_in_ui:
			_mouse_in_ui = true  # Treat as "in UI" to hide preview
			needs_update = true
	
	# Check for camera changes
	if tool and tool.cached_camera:
		var cam_pos = tool.cached_camera.get_camera_position()
		var cam_zoom = tool.cached_camera.zoom
		
		if cam_pos != _last_camera_pos or cam_zoom != _last_camera_zoom:
			_last_camera_pos = cam_pos
			_last_camera_zoom = cam_zoom
			needs_update = true
	
	# Check if markers changed
	if tool and tool.markers.size() != _last_marker_count:
		_last_marker_count = tool.markers.size()
		needs_update = true
	
	# Check if fills changed
	if tool and tool.fills.size() != _last_fill_count:
		_last_fill_count = tool.fills.size()
		needs_update = true
	
	# Check if placement mode changed
	if tool:
		var path_active = tool.path_placement_active
		
		if path_active != _last_path_active:
			_last_path_active = path_active
			needs_update = true
	
	# Retain the request through every draw in its frame; expire before the next.
	if tool and not tool._api_preview.empty():
		if _api_preview_frame != tool._api_preview_frame:
			_api_preview_frame = tool._api_preview_frame
		elif Engine.get_idle_frames() > _api_preview_frame:
			tool._api_preview.clear()
		needs_update = true

	# Track drag position for move mode
	if tool and tool.move_mode and tool._move_selected_marker and tool.cached_worldui:
		var current = tool.cached_worldui.MousePosition
		if current != tool._move_drag_pos:
			tool._move_drag_pos = current
			needs_update = true

	# Only update when necessary
	if needs_update:
		update()

# Handle mouse input for placing markers
func _is_mouse_over_canvas() -> bool:
	if not tool or not tool.parent_mod:
		return false
	var editor = tool.parent_mod.Global.Editor
	if not editor is Node or not is_instance_valid(editor):
		return false
	var windows = editor.get("Windows")
	if windows != null:
		for window in windows.values():
			if is_instance_valid(window) and window.visible:
				return false
	# This is the host's Content.gui_input target (Editor.tscn / Editor.cs).
	# Local coordinates account for UI scale and resized side/top/bottom panels.
	var content = editor.get_node_or_null("VPartition/Panels/HSplit/Content")
	return content is Control and content.is_visible_in_tree() and Rect2(Vector2.ZERO,
		content.rect_size).has_point(content.get_local_mouse_position())

func _input(event):
	if not tool or not tool.is_enabled:
		return
	if event is InputEventMouse and not _is_mouse_over_canvas():
		# Release still finishes an existing drag after the pointer leaves the canvas.
		if not (event is InputEventMouseButton and event.button_index == BUTTON_LEFT and not event.pressed):
			return
	
	# Handle RIGHT-CLICK for Path finalization
	if event is InputEventMouseButton and event.button_index == BUTTON_RIGHT:
		if tool.path_placement_active and event.pressed:
			tool._finalize_path_marker(false)  # Finish as open path
			get_tree().set_input_as_handled()
			return
		# Shape type: RMB rotates by 45 degrees (not in delete/move mode)
		if tool.active_marker_type == tool.MARKER_TYPE_SHAPE and event.pressed and not tool.delete_mode and not tool.move_mode:
			tool.rotate_shape_45()
			get_tree().set_input_as_handled()
			return
		# Template type: RMB rotates by 45 degrees (not in delete/move mode, not in capture mode)
		if tool.active_marker_type == tool.MARKER_TYPE_TEMPLATE and event.pressed and not tool.delete_mode and not tool.move_mode and not tool.template_capture_mode:
			tool.rotate_template_45()
			get_tree().set_input_as_handled()
			return
	
	# Handle ESC key for Path cancellation
	if event is InputEventKey and event.scancode == KEY_ESCAPE and event.pressed:
		if tool.path_placement_active:
			tool._cancel_path_placement()
			get_tree().set_input_as_handled()
			return
	
	# Handle mouse wheel for parameter adjustment
	if event is InputEventMouseButton:
		# Ignore if CTRL is held (used for zoom)
		if not event.control:
			# Line type: adjust angle
			if tool.active_marker_type == tool.MARKER_TYPE_LINE:
				if event.button_index == BUTTON_WHEEL_UP and event.pressed:
					if tool.LOGGER:
						tool.LOGGER.debug("MarkerOverlay: Mouse wheel UP detected (Line)")
					tool.adjust_angle_with_wheel(1)
					get_tree().set_input_as_handled()
					return
				elif event.button_index == BUTTON_WHEEL_DOWN and event.pressed:
					if tool.LOGGER:
						tool.LOGGER.debug("MarkerOverlay: Mouse wheel DOWN detected (Line)")
					tool.adjust_angle_with_wheel(-1)
					get_tree().set_input_as_handled()
					return
			
			# Shape type: wheel rotates angle, Alt+wheel adjusts radius
			elif tool.active_marker_type == tool.MARKER_TYPE_SHAPE:
				if event.button_index == BUTTON_WHEEL_UP and event.pressed:
					if event.alt:
						if tool.LOGGER:
							tool.LOGGER.debug("MarkerOverlay: Alt+Mouse wheel UP detected (Shape radius)")
						tool.adjust_shape_radius_with_wheel(1)
					else:
						if tool.LOGGER:
							tool.LOGGER.debug("MarkerOverlay: Mouse wheel UP detected (Shape angle)")
						tool.adjust_shape_angle_with_wheel(1)
					get_tree().set_input_as_handled()
					return
				elif event.button_index == BUTTON_WHEEL_DOWN and event.pressed:
					if event.alt:
						if tool.LOGGER:
							tool.LOGGER.debug("MarkerOverlay: Alt+Mouse wheel DOWN detected (Shape radius)")
						tool.adjust_shape_radius_with_wheel(-1)
					else:
						if tool.LOGGER:
							tool.LOGGER.debug("MarkerOverlay: Mouse wheel DOWN detected (Shape angle)")
						tool.adjust_shape_angle_with_wheel(-1)
					get_tree().set_input_as_handled()
					return

			# Template type: wheel rotates the ephemeral angle offset (not in capture mode)
			elif tool.active_marker_type == tool.MARKER_TYPE_TEMPLATE and not tool.template_capture_mode:
				if event.button_index == BUTTON_WHEEL_UP and event.pressed:
					tool.adjust_template_rotation_with_wheel(1)
					get_tree().set_input_as_handled()
					return
				elif event.button_index == BUTTON_WHEEL_DOWN and event.pressed:
					tool.adjust_template_rotation_with_wheel(-1)
					get_tree().set_input_as_handled()
					return
		
		# Handle left click for placing/deleting markers
		if event.button_index == BUTTON_LEFT and event.pressed:
			# Check if click is inside world bounds
			if tool.cached_worldui and tool.cached_worldui.IsInsideBounds:
				var pos = tool.cached_worldui.MousePosition
				
				if tool.LOGGER:
					tool.LOGGER.debug("MarkerOverlay: Mouse clicked at %s, delete_mode: %s, fill_mode: %s" % [pos, str(tool.delete_mode), str(tool.active_marker_type == tool.MARKER_TYPE_FILL)])
				
				# Move mode: start dragging the marker under the cursor
				if tool.move_mode:
					var marker = tool.find_marker_at(pos, 20.0)
					if marker:
						tool._move_selected_marker = marker
						tool._move_drag_offset = pos - marker.position
						tool._move_drag_pos = pos
						update()
					get_tree().set_input_as_handled()
					return
				
				# Template capture mode: save clicked marker as a new template
				if tool.template_capture_mode:
					tool.capture_marker_as_template(pos)
					get_tree().set_input_as_handled()
					update()
					return

				# Fill mode: click fills the region under the cursor inside a Shape polygon
				if tool.active_marker_type == tool.MARKER_TYPE_FILL:
					tool.handle_fill_click(pos)
					update()
					return
				
				# If in delete mode, try to delete marker
				if tool.delete_mode:
					tool.delete_marker_at_position(pos, 20.0)
				else:
					# Otherwise place new marker
					tool.place_marker(pos)
				
				update()  # Request redraw

	# LMB released — finalize drag in move mode
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and not event.pressed:
		if tool.move_mode and tool._move_selected_marker:
			var new_pos = tool._move_drag_pos - tool._move_drag_offset
			if tool.parent_mod.Global.Editor.IsSnapping:
				new_pos = tool.snap_position_to_grid(new_pos)
			tool.move_marker(tool._move_selected_marker, new_pos)
			tool._move_selected_marker = null
			get_tree().set_input_as_handled()
			return

	# Mouse motion — live preview while dragging in move mode
	if event is InputEventMouseMotion and tool.move_mode and tool._move_selected_marker:
		update()
		return

# Draw all markers and their guide lines
# Also draws preview marker at cursor position
func _draw():
	if not tool:
		return
	
	var camera = tool.cached_camera
	if not camera:
		return
	
	var cam_pos = camera.get_camera_position()
	var cam_zoom = camera.zoom
	var vp_rect = get_viewport_rect()
	
	var world_width = vp_rect.size.x * cam_zoom.x
	var world_height = vp_rect.size.y * cam_zoom.y
	var world_left = cam_pos.x - world_width * 0.5
	var world_right = cam_pos.x + world_width * 0.5
	var world_top = cam_pos.y - world_height * 0.5
	var world_bottom = cam_pos.y + world_height * 0.5

	# Compute once — shared by all markers this frame
	var map_rect: Rect2
	if tool.cached_world:
		map_rect = tool.cached_world.WorldRect
	else:
		map_rect = Rect2(world_left, world_top, world_right - world_left, world_bottom - world_top)
	var cell_size = _get_grid_cell_size()
	var custom_snap = _get_custom_snap()
	var marker_size_draw    = GuidesLinesRender.get_adaptive_width(10.0, cam_zoom)
	var line_width_draw     = GuidesLinesRender.get_adaptive_width(5.0, cam_zoom)
	var preview_line_width  = GuidesLinesRender.get_adaptive_width(PREVIEW_LINE_WIDTH, cam_zoom)
	var preview_marker_size = GuidesLinesRender.get_adaptive_width(PREVIEW_MARKER_SIZE, cam_zoom)
	var coord_marker_size   = GuidesLinesRender.get_adaptive_width(5.0, cam_zoom)
	var coord_text_offset   = GuidesLinesRender.get_adaptive_width(20.0, cam_zoom)
	var active_arrow_length_px = GuidesLinesRender.get_adaptive_width(tool.active_arrow_head_length, cam_zoom)

	# Draw fill regions under marker outlines (respects markers_opacity)
	_draw_fills()

	# Draw all markers (hidden when markers_visible is false)
	if not tool.parent_mod or tool.parent_mod.markers_visible:
		for marker in tool.markers:
			if not marker:
				continue
			
			_draw_custom_marker(marker, world_left, world_right, world_top, world_bottom, cam_zoom, map_rect, cell_size, custom_snap, marker_size_draw, line_width_draw, coord_marker_size, coord_text_offset)
	
	# Draw API-requested shape preview (external callers; rendered regardless of tool state)
	if not tool._api_preview.empty():
		_draw_api_shape_preview(tool._api_preview, cam_zoom, cell_size, preview_line_width, preview_marker_size)

	# Draw move mode drag preview
	if tool.move_mode and tool._move_selected_marker:
		var drag_pos = tool._move_drag_pos - tool._move_drag_offset
		if tool.parent_mod.Global.Editor.IsSnapping:
			drag_pos = tool.snap_position_to_grid(drag_pos)
		_draw_move_drag_preview(tool._move_selected_marker, drag_pos, world_left, world_right, world_top, world_bottom, cam_zoom, map_rect, cell_size, custom_snap, preview_line_width, preview_marker_size)
		return

	# Draw preview marker at cursor (disabled in delete mode, move mode, fill mode, and template mode)
	if tool.is_enabled and not tool.delete_mode and not tool.move_mode and tool.active_marker_type != tool.MARKER_TYPE_FILL and tool.active_marker_type != tool.MARKER_TYPE_TEMPLATE and tool.cached_worldui and tool.cached_worldui.IsInsideBounds:
		# Don't draw preview if mouse is in UI area
		if _mouse_in_ui:
			return
		
		# Special preview for Path type
		if tool.active_marker_type == tool.MARKER_TYPE_PATH:
			_draw_path_preview(world_left, world_right, world_top, world_bottom, cam_zoom, preview_line_width, preview_marker_size, active_arrow_length_px)
		else:
			var preview_pos = tool.cached_worldui.MousePosition
			_draw_custom_marker_preview(preview_pos, world_left, world_right, world_top, world_bottom, cam_zoom, map_rect, cell_size, preview_line_width, preview_marker_size)

	# Draw template preview at cursor (Template mode with a selected template, not in capture mode)
	if tool.is_enabled and not tool.delete_mode and not tool.move_mode \
			and tool.active_marker_type == tool.MARKER_TYPE_TEMPLATE \
			and not tool.template_capture_mode \
			and tool.active_template_index >= 0 \
			and tool.cached_worldui and tool.cached_worldui.IsInsideBounds:
		if not _mouse_in_ui:
			var preview_pos = tool.cached_worldui.MousePosition
			_draw_template_preview(preview_pos, world_left, world_right, world_top, world_bottom, cam_zoom, map_rect, cell_size, preview_line_width, preview_marker_size)

# Draw all fill regions stored in the tool.
# Fills are drawn below marker outlines and respect the global markers_opacity.
func _draw_fills() -> void:
	if not tool or tool.fills.empty():
		return
	for fill in tool.fills:
		if fill.polygon.size() < 3:
			continue
		draw_colored_polygon(PoolVector2Array(fill.polygon), fill.draw_color)

# Draw a single custom marker with its line(s) or circle
func _draw_custom_marker(marker, world_left, world_right, world_top, world_bottom, cam_zoom, map_rect: Rect2, cell_size, custom_snap, marker_size_draw: float, line_width_draw: float, coord_marker_size: float, coord_text_offset: float):
	var MARKER_SIZE = marker_size_draw
	var LINE_WIDTH  = line_width_draw

	var line_color   = marker.draw_color
	var MARKER_COLOR = marker.draw_marker_color

	# map_rect and cell_size come from _draw — computed once per frame
	var draw_data = marker.get_draw_data(map_rect, cell_size)
	
	# Draw based on marker type
	if marker.marker_type == "Line":
		if draw_data.has("segments"):
			for segment in draw_data.segments:
				draw_line(segment[0], segment[1], line_color, LINE_WIDTH)
	
	elif marker.marker_type == "Shape":
		if draw_data.has("type") and draw_data.type == "shape":
			# Single primitives list holds the complete current visual state:
			# original outline minus clipped/diff zones, plus diff boundary segments.
			var primitives = draw_data.get("primitives", [])
			for item in primitives:
				if item.type == "seg":
					draw_line(item.a, item.b, line_color, LINE_WIDTH)


	elif marker.marker_type == "Path":
		_draw_path_points(marker.marker_points, marker.path_closed, marker.path_end_arrow, marker.arrow_head_length, marker.arrow_head_angle, cam_zoom, line_color, LINE_WIDTH)

	# Draw marker circle on top (only if marker is visible on screen)
	# Optimized visibility check using Godot's built-in Rect2 methods if possible, 
	# but simple AABB check is fast enough.
	var is_marker_visible = marker.position.x >= world_left and marker.position.x <= world_right and \
	                        marker.position.y >= world_top and marker.position.y <= world_bottom
	
	if is_marker_visible:
		_draw_marker_anchor(marker.position, MARKER_SIZE, MARKER_COLOR, marker.draw_arc_color)
	
	# Draw coordinates if enabled for this marker
	if marker.show_coordinates:
		var snap_enabled  = custom_snap != null and custom_snap.custom_snap_enabled
		var snap_interval = custom_snap.snap_interval if snap_enabled else Vector2.ZERO
		if marker._coord_dirty \
				or map_rect != marker._cached_coord_map_rect \
				or cell_size != marker._cached_coord_cell_size \
				or snap_enabled  != marker._cached_coord_snap_enabled \
				or snap_interval != marker._cached_coord_snap_interval:
			marker.rebuild_coord_cache(map_rect, cell_size, custom_snap)
		_draw_marker_coordinates_cached(marker, coord_marker_size, coord_text_offset)


## Render a one-frame Shape preview requested via GuidesLinesApi.set_shape_preview().
## [p] is the dict stored in tool._api_preview.
func _draw_api_shape_preview(p: Dictionary, cam_zoom: Vector2, cell_size, preview_line_width: float, preview_marker_size: float) -> void:
	if cell_size == null:
		return
	var pos    = p.get("pos",    Vector2.ZERO)
	var radius = p.get("radius", 1.0)
	var angle  = p.get("angle",  0.0)
	var sides  = p.get("sides",  6)
	var color  = p.get("color",  Color(0, 0.7, 1, 0.5))
	var radius_px = radius * min(cell_size.x, cell_size.y)
	var angle_rad = deg2rad(angle)
	var vertices  = GeometryUtils.calculate_polygon_vertices(pos, radius_px, sides, angle_rad)
	GuidesLinesRender.draw_polygon_outline(self, vertices, color, preview_line_width)
	_draw_marker_anchor(pos, preview_marker_size, Color(color.r, color.g, color.b, 0.5), _PREVIEW_ARC_COLOR)

# Draw semi-transparent preview of marker at cursor position
func _draw_custom_marker_preview(pos, world_left, world_right, world_top, world_bottom, cam_zoom, map_rect, cell_size, preview_line_width: float, preview_marker_size: float):
	var MARKER_COLOR = _PREVIEW_MARKER_COLOR
	var LINE_COLOR = Color(tool.active_color.r, tool.active_color.g, tool.active_color.b, 0.7)

	# Sizes pre-computed in _draw — no re-fetch needed
	var LINE_WIDTH  = preview_line_width
	var MARKER_SIZE = preview_marker_size
	
	# Draw preview based on active marker type
	if tool.active_marker_type == tool.MARKER_TYPE_LINE:
		# Draw preview line(s)
		var angles = [tool.active_angle]
		if tool.active_mirror:
			angles.append(fposmod(tool.active_angle + 180.0, 360.0))
		
		for angle in angles:
			var line_points = _calculate_line_endpoints(
				pos,
				angle,
				world_left,
				world_right,
				world_top,
				world_bottom,
				map_rect
			)
			
			# Only draw if line segment is valid (within map bounds)
			if line_points[0] != line_points[1]:
				draw_line(
					line_points[0],
					line_points[1],
					LINE_COLOR,
					LINE_WIDTH
				)
	
	elif tool.active_marker_type == tool.MARKER_TYPE_SHAPE:
		# Draw preview shape — cell_size comes from _draw
		if cell_size:
			var radius_px = tool.active_shape_radius * min(cell_size.x, cell_size.y)
			var angle_rad = deg2rad(tool.active_shape_angle)
			var vertices = GeometryUtils.calculate_polygon_vertices(pos, radius_px, tool.active_shape_sides, angle_rad)
			GuidesLinesRender.draw_polygon_outline(self, vertices, LINE_COLOR, LINE_WIDTH)

	
	# Draw preview marker
	_draw_marker_anchor(pos, MARKER_SIZE, MARKER_COLOR, _PREVIEW_ARC_COLOR)

# Draw semi-transparent preview of the selected template at cursor position.
func _draw_template_preview(preview_pos: Vector2, world_left: float, world_right: float, world_top: float, world_bottom: float, cam_zoom: Vector2, map_rect: Rect2, cell_size, preview_line_width: float, preview_marker_size: float) -> void:
	if tool.active_template_index < 0 or tool.active_template_index >= tool.templates.size():
		return
	var data = tool.templates[tool.active_template_index]["data"]
	var ALPHA        = 0.55
	var c            = data.get("color", Color(0, 0.7, 1, 1))
	var line_color   = Color(c.r, c.g, c.b, ALPHA)
	var marker_color = Color(1, 0, 0, ALPHA)
	var arc_color    = Color(0, 0, 0, ALPHA)
	var LINE_WIDTH   = preview_line_width
	var MARKER_SIZE  = preview_marker_size

	match data.get("marker_type", ""):
		"Line":
			var base_angle = data.get("angle", 0.0)
			var eff_angle = fposmod(base_angle + tool.template_rotation_offset, 360.0)
			var angles = [eff_angle]
			if data.get("mirror", false):
				angles.append(fposmod(eff_angle + 180.0, 360.0))
			for ang in angles:
				var line_points = _calculate_line_endpoints(preview_pos, ang, world_left, world_right, world_top, world_bottom, map_rect)
				if line_points[0] != line_points[1]:
					draw_line(line_points[0], line_points[1], line_color, LINE_WIDTH)
		"Shape":
			if data.has("shape_primitives"):
				# Modified shape — draw stored segments translated + rotated to cursor
				var rot_rad = deg2rad(tool.template_rotation_offset)
				for rel_seg in data["shape_primitives"]:
					var a = preview_pos + rel_seg["a"].rotated(rot_rad)
					var b = preview_pos + rel_seg["b"].rotated(rot_rad)
					draw_line(a, b, line_color, LINE_WIDTH)
			elif cell_size:
				# Standard unmodified shape — regenerate from parameters
				var radius_px = data.get("shape_radius", 1.0) * min(cell_size.x, cell_size.y)
				var eff_angle = fposmod(data.get("shape_angle", 0.0) + tool.template_rotation_offset, 360.0)
				var angle_rad = deg2rad(eff_angle)
				var vertices  = GeometryUtils.calculate_polygon_vertices(preview_pos, radius_px, data.get("shape_sides", 6), angle_rad)
				GuidesLinesRender.draw_polygon_outline(self, vertices, line_color, LINE_WIDTH)
		"Path":
			var rel_pts = data.get("relative_points", [])
			if rel_pts.size() >= 2:
				var rot_rad = deg2rad(tool.template_rotation_offset)
				var pts = []
				for rp in rel_pts:
					pts.append(preview_pos + rp.rotated(rot_rad))
				_draw_path_points(pts, data.get("path_closed", false), data.get("path_end_arrow", false), data.get("arrow_head_length", 50.0), data.get("arrow_head_angle", 30.0), cam_zoom, line_color, LINE_WIDTH)

	_draw_marker_anchor(preview_pos, MARKER_SIZE, marker_color, arc_color)

# Draw the selected marker semi-transparently at the dragged position during Move Mode.
func _draw_move_drag_preview(marker, drag_pos: Vector2, world_left, world_right, world_top, world_bottom, cam_zoom, map_rect: Rect2, cell_size, custom_snap, preview_line_width: float, preview_marker_size: float):
	var ALPHA = 0.55
	var line_color   = Color(marker.draw_color.r, marker.draw_color.g, marker.draw_color.b, ALPHA)
	var marker_color = Color(marker.draw_marker_color.r, marker.draw_marker_color.g, marker.draw_marker_color.b, ALPHA)
	var arc_color    = Color(marker.draw_arc_color.r, marker.draw_arc_color.g, marker.draw_arc_color.b, ALPHA)
	var LINE_WIDTH   = preview_line_width
	var MARKER_SIZE  = preview_marker_size

	if marker.marker_type == "Line":
		var angles = [marker.angle]
		if marker.mirror:
			angles.append(fposmod(marker.angle + 180.0, 360.0))
		for ang in angles:
			var line_points = _calculate_line_endpoints(drag_pos, ang, world_left, world_right, world_top, world_bottom, map_rect)
			if line_points[0] != line_points[1]:
				draw_line(line_points[0], line_points[1], line_color, LINE_WIDTH)

	elif marker.marker_type == "Shape":
		var offset = drag_pos - marker.position
		var data = marker.get_draw_data(map_rect, cell_size)
		for seg in data.get("primitives", []):
			draw_line(seg.a + offset, seg.b + offset, line_color, LINE_WIDTH)

	elif marker.marker_type == "Path":
		if marker.marker_points.size() >= 2:
			var offset = drag_pos - marker.position
			var pts = []
			for p in marker.marker_points:
				pts.append(p + offset)
			_draw_path_points(pts, marker.path_closed, marker.path_end_arrow, marker.arrow_head_length, marker.arrow_head_angle, cam_zoom, line_color, LINE_WIDTH)

	_draw_marker_anchor(drag_pos, MARKER_SIZE, marker_color, arc_color)

# Draw preview for Path type (temp points + line to cursor)
func _draw_path_preview(world_left, world_right, world_top, world_bottom, cam_zoom, preview_line_width: float, preview_marker_size: float, active_arrow_length_px: float):
	if not tool.path_placement_active or tool.path_temp_points.size() == 0:
		return
	
	var MARKER_COLOR       = _PREVIEW_MARKER_COLOR
	var LINE_COLOR         = Color(tool.active_color.r, tool.active_color.g, tool.active_color.b, 0.7)
	var PREVIEW_LINE_COLOR = _PATH_PREVIEW_LINE_COLOR
	
	# Sizes pre-computed in _draw — no re-fetch needed
	var LINE_WIDTH  = preview_line_width
	var MARKER_SIZE = preview_marker_size
	
	# Draw all placed points
	for i in range(tool.path_temp_points.size()):
		var point = tool.path_temp_points[i]
		
		# First point is slightly larger and different color
		if i == 0:
			draw_circle(point, MARKER_SIZE / 1.5, _PATH_PREVIEW_FIRST_COLOR)
		else:
			draw_circle(point, MARKER_SIZE / 2.0, MARKER_COLOR)
		
		# Draw outline
		draw_arc(point, MARKER_SIZE / 2.0, 0, TAU, 32, _PREVIEW_ARC_COLOR, 2)
	
	# Draw lines between placed points
	if tool.path_temp_points.size() >= 2:
		for i in range(tool.path_temp_points.size() - 1):
			draw_line(
				tool.path_temp_points[i],
				tool.path_temp_points[i + 1],
				LINE_COLOR,
				LINE_WIDTH
			)
	
	# Draw preview line from last point to cursor
	if tool.path_preview_point != null and tool.path_temp_points.size() > 0:
		var last_point = tool.path_temp_points[tool.path_temp_points.size() - 1]
		draw_line(
			last_point,
			tool.path_preview_point,
			PREVIEW_LINE_COLOR,
			LINE_WIDTH * 0.7
		)
		
		# Draw cursor preview circle
		draw_circle(tool.path_preview_point, MARKER_SIZE / 3.0, _PATH_PREVIEW_CURSOR_COLOR)
		
		# Draw arrow preview at cursor if path_end_arrow is enabled
		if tool.active_path_end_arrow:
			var arrow_length = active_arrow_length_px  # Pre-computed in _draw
			var head_points = GeometryUtils.calculate_arrowhead_points(
				tool.path_preview_point, last_point, arrow_length, tool.active_arrow_head_angle)
			GuidesLinesRender.draw_arrow(self, last_point, tool.path_preview_point, head_points,
				Color(tool.active_color.r, tool.active_color.g, tool.active_color.b, 0.5), LINE_WIDTH * 0.7)
	
	# Draw "close path" indicator if near first point
	if tool.path_temp_points.size() >= 3 and tool.path_preview_point != null:
		var first_point = tool.path_temp_points[0]
		if tool.path_preview_point.distance_to(first_point) < 30.0:
			# Draw pulsing circle around first point
			var pulse = sin(OS.get_ticks_msec() * 0.005) * 0.5 + 0.5
			draw_arc(first_point, MARKER_SIZE, 0, TAU, 32, Color(0, 1, 0, 0.5 + pulse * 0.3), 4)

# Calculate line endpoints - always draws to map boundaries
func _calculate_line_endpoints(origin, angle_deg, world_left, world_right, world_top, world_bottom, map_rect):
	var angle_rad = deg2rad(angle_deg)
	var direction = Vector2(cos(angle_rad), sin(angle_rad))
	var bounds = map_rect if map_rect else Rect2(world_left, world_top, world_right - world_left, world_bottom - world_top)
	return GeometryUtils.get_ray_to_rect_edge(origin, direction, bounds)

func _get_custom_snap():
	if not tool:
		return null
	return tool.cached_snappy_mod

# Get grid cell size (accounting for custom_snap mod if active)
func _get_grid_cell_size():
	if not tool:
		return null
	# Single source of truth — delegate to the tool so all modes use identical cell_size.
	return tool._get_grid_cell_size()

# Draw cached coordinate points for a Line marker.
# All grid positions and texts are pre-computed in GuideMarker.rebuild_coord_cache().
# Sizes are pre-computed in _draw() — no per-call get_adaptive_width needed.
func _draw_marker_coordinates_cached(marker, marker_size: float, text_offset: float) -> void:
	if marker.cached_coord_points.empty():
		return
	var color = marker.draw_color
	for point in marker.cached_coord_points:
		draw_circle(point.grid_pos, marker_size, color)
		_draw_text_with_outline(point.text, point.grid_pos + point.perp * text_offset, color)

# Draw text with outline for better visibility
func _draw_text_with_outline(text, position, color):
	GuidesLinesRender.draw_text_with_outline(self, text, position, color, _cached_font)


func _draw_marker_anchor(pos: Vector2, size: float, fill_color: Color, arc_color: Color) -> void:
	draw_circle(pos, size / 2.0, fill_color)
	draw_arc(pos, size / 2.0, 0, TAU, 32, arc_color, 2)

func _draw_path_points(points: Array, closed: bool, end_arrow: bool, arrow_length: float, arrow_angle: float, zoom: Vector2, color: Color, width: float) -> void:
	if points.size() < 2:
		return
	for index in range(points.size() - 1):
		draw_line(points[index], points[index + 1], color, width)
	if closed and points.size() >= 3:
		draw_line(points[points.size() - 1], points[0], color, width)
	if end_arrow:
		var start = points[points.size() - 2]
		var end = points[points.size() - 1]
		var head = GeometryUtils.calculate_arrowhead_points(end, start, GuidesLinesRender.get_adaptive_width(arrow_length, zoom), arrow_angle)
		GuidesLinesRender.draw_arrow(self, start, end, head, color, width)

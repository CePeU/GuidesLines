extends Reference

# Map-scoped JSON serialization and host save lifecycle. Models retain their
# Save/Load methods for history snapshots; only this class owns the map format.
const CLASS_NAME = "GuidesLinesPersistence"
const DATA_KEY = "Choson.GuidesLines"
const DATA_VERSION = 1

var _mod = null
var _world = null
var _editor = null
var _signaling = null


func attach(mod):
	_mod = mod
	update()


func update():
	if _mod == null or _mod.guides_tool == null:
		return
	var global = _mod.Global
	if global.Editor != _editor:
		_disconnect_editor()
		_editor = global.Editor
		if is_instance_valid(_editor) and _editor.has_signal("OnSaveBegin"):
			_editor.connect("OnSaveBegin", self, "_on_save_begin")
	if _signaling == null and global.API and global.API.has("ModSignalingApi"):
		_signaling = global.API.ModSignalingApi
		if not _signaling.is_connected("unload", self, "_unload"):
			_signaling.connect("unload", self, "_unload")
	if global.World == null or global.WorldUI == null:
		if _world != null:
			_world = null
			_reset()
		return
	if global.World != _world:
		_world = global.World
		load_map(global.ModMapData)


func _disconnect_editor():
	if is_instance_valid(_editor) and _editor.is_connected("OnSaveBegin", self, "_on_save_begin"):
		_editor.disconnect("OnSaveBegin", self, "_on_save_begin")
	_editor = null


func _unload():
	_disconnect_editor()
	if is_instance_valid(_signaling) and _signaling.is_connected("unload", self, "_unload"):
		_signaling.disconnect("unload", self, "_unload")
	_signaling = null
	_world = null
	_mod = null


func _on_save_begin(_path, _is_backup):
	update()
	if _mod != null and _world != null:
		save_map(_mod.Global.ModMapData)


func save_map(map_data: Dictionary):
	var tool = _mod.guides_tool
	var data = {"version": DATA_VERSION, "markers": [], "fills": [], "templates": [],
		"next_id": tool.next_id, "next_fill_id": tool.next_fill_id,
		"template_next_id": tool.template_next_id}
	for marker in tool.markers:
		data.markers.append(marker.Save())
	for fill in tool.fills:
		data.fills.append(fill.Save())
	for template in tool.templates:
		var saved = template.duplicate(true)
		var params = saved.data
		params.color = "#" + params.color.to_html()
		for key in ["relative_points", "shape_primitives"]:
			if params.has(key):
				params[key] = _encode_points(params[key], key == "shape_primitives")
		data.templates.append(saved)
	# Replace the entire owned block, including incompatible/unknown old fields.
	map_data[DATA_KEY] = data


func _encode_points(points, segments):
	var result = []
	for point in points:
		if segments:
			result.append({"a": [point.a.x, point.a.y], "b": [point.b.x, point.b.y]})
		else:
			result.append([point.x, point.y])
	return result


func load_map(map_data: Dictionary) -> bool:
	_reset()
	if not map_data.has(DATA_KEY):
		return true
	var data = map_data[DATA_KEY]
	if not data is Dictionary or not _number(data.get("version")) or data.version != DATA_VERSION:
		_warn("Map data version is incompatible; GuidesLines data was not loaded.")
		return false
	if not _valid_data(data):
		_warn("Invalid map data; GuidesLines data was not loaded.")
		return false
	var tool = _mod.guides_tool
	for saved in data.markers:
		var marker = tool.GuideMarkerClass.new()
		marker.Load(saved)
		marker.id = int(marker.id)
		marker.update_opacity(_mod.markers_opacity)
		tool.markers.append(marker)
		tool.markers_lookup[marker.id] = marker
		tool.next_id = max(tool.next_id, int(marker.id) + 1)
	for saved in data.fills:
		var fill = tool.FillMarkerClass.new()
		fill.Load(saved)
		fill.id = int(fill.id)
		fill.update_opacity(_mod.markers_opacity)
		tool.fills.append(fill)
		tool.fills_lookup[fill.id] = fill
		tool.next_fill_id = max(tool.next_fill_id, int(fill.id) + 1)
	for saved in data.templates:
		var template = saved.duplicate(true)
		template.id = int(template.id)
		var params = template.data
		params.color = Color(params.color.lstrip("#"))
		if params.has("relative_points"):
			var points = []
			for point in params.relative_points:
				points.append(Vector2(point[0], point[1]))
			params.relative_points = points
		if params.has("shape_primitives"):
			var segments = []
			for segment in params.shape_primitives:
				segments.append({"a": Vector2(segment.a[0], segment.a[1]), "b": Vector2(segment.b[0], segment.b[1])})
			params.shape_primitives = segments
		tool.templates.append(template)
		tool.template_next_id = max(tool.template_next_id, int(template.id) + 1)
	tool.next_id = max(tool.next_id, int(data.next_id))
	tool.next_fill_id = max(tool.next_fill_id, int(data.next_fill_id))
	tool.template_next_id = max(tool.template_next_id, int(data.template_next_id))
	_refresh_ui()
	return true


func _reset():
	var tool = _mod.guides_tool
	tool.markers = []
	tool.markers_lookup = {}
	tool.fills = []
	tool.fills_lookup = {}
	tool.templates = []
	tool.next_id = 0
	tool.next_fill_id = 0
	tool.template_next_id = 0
	tool.active_template_index = -1
	tool.template_rotation_offset = 0.0
	tool.template_capture_mode = false
	tool.path_placement_active = false
	tool.path_temp_points = []
	tool.path_preview_point = null
	tool._move_selected_marker = null
	tool._move_drag_offset = Vector2.ZERO
	tool._move_drag_pos = Vector2.ZERO
	tool._api_preview = {}
	tool._api_preview_frame = -1
	_refresh_ui()


func _refresh_ui():
	var tool = _mod.guides_tool
	if tool.ui:
		tool.ui.rebuild_template_list()
		tool.ui._update_template_capture_button(false)
	tool.update_ui()
	if tool.overlay:
		tool.overlay.update()


func _warn(message):
	if _mod.LOGGER:
		_mod.LOGGER.warn(message)


func _number(value) -> bool:
	# Godot 3 Vector2 components are 32-bit floats, even when JSON numbers are doubles.
	return (value is int or value is float) and not is_nan(float(value)) and not is_inf(float(value)) and abs(value) <= 3.402823e38


func _id(value) -> bool:
	return _number(value) and value >= 0 and value < 9007199254740991 and floor(value) == value


func _point(value) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1])


func _color(value) -> bool:
	if not value is String or value.length() != 9 or not value.begins_with("#"):
		return false
	for character in value.substr(1).to_lower():
		if not character in "0123456789abcdef":
			return false
	return true


func _marker(data) -> bool:
	if not data is Dictionary or not _id(data.get("id")) or not _point(data.get("position")) or not _color(data.get("color")):
		return false
	var kind = data.get("marker_type")
	if not kind in ["Line", "Shape", "Path"]:
		return false
	var numbers = ["angle"] if kind == "Line" else (["shape_radius", "shape_angle", "shape_sides"] if kind == "Shape" else ["arrow_head_length", "arrow_head_angle"])
	var booleans = ["mirror"] if kind == "Line" else ([] if kind == "Shape" else ["path_closed", "path_end_arrow"])
	for key in numbers:
		if not _number(data.get(key, 0)):
			return false
	for key in booleans + ["show_coordinates"]:
		if not data.get(key, false) is bool:
			return false
	if kind == "Shape":
		if data.get("shape_radius", 1) <= 0 or not _id(data.get("shape_sides", 6)) or data.get("shape_sides", 6) < 3 or data.get("shape_sides", 6) > 64:
			return false
	if data.has("shape_primitives"):
		if not data.shape_primitives is Array:
			return false
		for segment in data.shape_primitives:
			if not segment is Dictionary or not _point(segment.get("a")) or not _point(segment.get("b")):
				return false
	if kind == "Path":
		if not _points(data.get("marker_points"), 2) or data.get("arrow_head_length", 0) < 0:
			return false
	return true


func _points(points, minimum) -> bool:
	if not points is Array or points.size() < minimum:
		return false
	for point in points:
		if not _point(point):
			return false
	return true


func _valid_data(data) -> bool:
	for key in ["next_id", "next_fill_id", "template_next_id"]:
		if not _id(data.get(key)):
			return false
	for key in ["markers", "fills", "templates"]:
		if not data.get(key) is Array:
			return false
		var ids = {}
		for saved in data[key]:
			if not saved is Dictionary or not _id(saved.get("id")) or ids.has(int(saved.id)):
				return false
			ids[int(saved.id)] = true
			if key == "markers" and not _marker(saved):
				return false
			if key == "fills" and (not _color(saved.get("color")) or not _points(saved.get("polygon"), 3)):
				return false
			if key == "templates":
				if not saved.get("name") is String or not saved.get("data") is Dictionary:
					return false
				var params = saved.data.duplicate(true)
				if params.has("relative_points") and not _points(params.relative_points, 0):
					return false
				params["id"] = saved.id
				params["position"] = [0, 0]
				params["marker_points"] = params.get("relative_points")
				if not _marker(params):
					return false
	return true

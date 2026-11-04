extends "res://addons/gut/test.gd"

var mod_root = ProjectSettings.globalize_path("res://").plus_file("..").simplify_path()
var tool
var mod
var persistence
var editor
var world
var world_ui
var signaling


func before_each():
	editor = Node.new()
	editor.add_user_signal("OnSaveBegin", [{"name": "path"}, {"name": "backup"}])
	signaling = Reference.new()
	signaling.add_user_signal("unload")
	world = Node.new()
	world_ui = Node.new()
	mod = {"LOGGER": null, "markers_opacity": 0.7, "guides_lines_api": null,
		"Global": {"API": {"ModSignalingApi": signaling}, "Editor": editor,
			"World": world, "WorldUI": world_ui, "ModMapData": {"other_mod": {"untouched": true}}}}
	tool = load(mod_root.plus_file("scripts/tool/GuidesLinesTool.gd")).new(mod)
	tool.GuideMarkerClass = load(mod_root.plus_file("scripts/guides/GuideMarker.gd"))
	tool.FillMarkerClass = load(mod_root.plus_file("scripts/guides/FillMarker.gd"))
	mod["guides_tool"] = tool
	persistence = load(mod_root.plus_file("scripts/tool/GuidesLinesPersistence.gd")).new()
	persistence.attach(mod)


func after_each():
	persistence._unload()
	tool.ui.tool = null
	tool.placement.tool = null
	tool._fill_handler.tool = null
	tool.parent_mod = null
	mod.clear()
	editor.free()
	world.free()
	world_ui.free()
	persistence = null
	tool = null


func populate():
	for kind in ["Line", "Shape", "Path"]:
		var marker = tool.GuideMarkerClass.new(Vector2(10, 20), 37.0, true, true)
		marker.id = tool.markers.size() + 3
		marker.marker_type = kind
		if kind == "Shape":
			marker.set_primitives([{"type": "seg", "a": Vector2(1, 2), "b": Vector2(3, 4)}])
		if kind == "Path":
			marker.marker_points = [Vector2(1, 2), Vector2(3, 4), Vector2(4, 1)]
			marker.path_closed = true
			marker.path_end_arrow = true
		tool.markers.append(marker)
		tool.markers_lookup[marker.id] = marker
	var fill = tool.FillMarkerClass.new()
	fill.id = 9
	fill.polygon = [Vector2.ZERO, Vector2(10, 0), Vector2(0, 10)]
	tool.fills = [fill]
	tool.fills_lookup = {9: fill}
	tool.templates = [
		{"id": 2, "name": "Line", "data": {"marker_type": "Line", "color": Color.red, "angle": 20.0, "mirror": true, "show_coordinates": true}},
		{"id": 4, "name": "Shape", "data": {"marker_type": "Shape", "color": Color.green, "shape_radius": 2.0, "shape_sides": 4, "shape_angle": 25.0,
			"shape_primitives": [{"a": Vector2(1, 2), "b": Vector2(3, 4)}]}},
		{"id": 6, "name": "Path", "data": {"marker_type": "Path", "color": Color.blue, "path_closed": false, "path_end_arrow": true,
			"arrow_head_length": 10.0, "arrow_head_angle": 30.0, "relative_points": [Vector2.ZERO, Vector2(10, 0)]}}]
	tool.next_id = 50
	tool.next_fill_id = 60
	tool.template_next_id = 70


func saved_json():
	persistence.save_map(mod.Global.ModMapData)
	var parsed = JSON.parse(JSON.print(mod.Global.ModMapData))
	assert_eq(parsed.error, OK)
	return parsed.result


func test_complete_map_round_trip_and_transient_state_reset():
	populate()
	var expected = saved_json()
	tool.path_placement_active = true
	tool.path_temp_points = [Vector2.ONE]
	tool._move_selected_marker = tool.markers[0]
	tool.template_capture_mode = true
	tool.active_template_index = 1
	tool.template_rotation_offset = 45.0
	tool._api_preview = {"test": true}
	assert_true(persistence.load_map(expected))
	assert_eq(tool.markers.size(), 3)
	assert_eq(tool.markers_lookup.size(), 3)
	assert_true(tool.markers_lookup.has(3), "JSON IDs must support integer API lookups")
	assert_eq(tool.fills_lookup.size(), 1)
	assert_eq(tool.templates.size(), 3)
	assert_eq(tool.next_id, 50)
	assert_eq(tool.next_fill_id, 60)
	assert_eq(tool.template_next_id, 70)
	assert_eq(tool.templates[2].data.relative_points[1], Vector2(10, 0))
	assert_eq(tool.templates[1].data.shape_primitives[0].a, Vector2(1, 2))
	assert_eq(tool.templates[0].data.color, Color.red)
	assert_almost_eq(tool.markers[0].draw_color.a, 0.7, 0.001)
	assert_almost_eq(tool.fills[0].draw_color.a, 0.175, 0.001)
	assert_false(tool.path_placement_active)
	assert_eq(tool.path_temp_points, [])
	assert_null(tool._move_selected_marker)
	assert_false(tool.template_capture_mode)
	assert_eq(tool.active_template_index, -1)
	assert_eq(tool.template_rotation_offset, 0.0)
	assert_eq_deep(tool._api_preview, {})
	assert_eq(JSON.print(saved_json()), JSON.print(expected))


func test_versions_are_rejected_whole_and_next_save_replaces_all_old_fields():
	populate()
	var valid = saved_json()
	for version in [0, 2, 1.5, "1", null, true]:
		var data = valid.duplicate(true)
		data[persistence.DATA_KEY].version = version
		data[persistence.DATA_KEY]["old_unknown_field"] = "discard me"
		assert_false(persistence.load_map(data))
		assert_eq(tool.markers.size(), 0)
		assert_eq(tool.fills.size(), 0)
		assert_eq(tool.templates.size(), 0)
		persistence.save_map(data)
		assert_eq(data[persistence.DATA_KEY].version, persistence.DATA_VERSION)
		assert_false(data[persistence.DATA_KEY].has("old_unknown_field"))
		assert_true(data.other_mod.untouched)
		assert_true(persistence.load_map(data))
	assert_true(persistence.load_map({}))
	assert_eq_deep(tool.markers_lookup, {})


func test_malformed_data_rejected_atomically_before_any_load():
	populate()
	var valid = saved_json()
	var mutations = [
		["markers", 2, "marker_points", [[0, "bad"], [1, 2]]],
		["markers", 0, "position", [1]],
		["markers", 0, "position", [1e100, 0]],
		["markers", 0, "angle", INF],
		["markers", 1, "shape_radius", -1],
		["markers", 1, "shape_sides", 3.5],
		["markers", 1, "shape_primitives", [{"a": [1, 2]}]],
		["markers", 0, "color", "#invalid!"],
		["markers", 0, "mirror", 1],
		["markers", 0, "marker_type", "Other"],
		["markers", 2, "id", 3],
		["fills", 0, "polygon", [[0, 0]]],
		["templates", 0, "data", {"color": "#ff0000ff"}],
		["templates", 0, "data", {"marker_type": "Line", "color": "#ff0000ff", "relative_points": false}],
		["templates", 0, "data", {"marker_type": "Line", "color": "#ff0000ff", "shape_primitives": [null]}],
		["templates", 0, "name", 42]]
	for mutation in mutations:
		var data = valid.duplicate(true)
		data[persistence.DATA_KEY][mutation[0]][mutation[1]][mutation[2]] = mutation[3]
		assert_false(persistence.load_map(data), str(mutation))
		assert_eq(tool.markers, [])
		assert_eq_deep(tool.markers_lookup, {})
		assert_eq_deep(tool.fills_lookup, {})
		assert_eq(tool.templates, [])
	for malformed in [null, [], {"version": 1}, {"version": 1, "markers": false}]:
		assert_false(persistence.load_map({persistence.DATA_KEY: malformed}))


func test_native_save_signal_snapshot_is_independent_and_unload_disconnects():
	populate()
	assert_eq(editor.get_signal_connection_list("OnSaveBegin").size(), 1)
	persistence.update()
	assert_eq(editor.get_signal_connection_list("OnSaveBegin").size(), 1)
	editor.emit_signal("OnSaveBegin", "scratch.dungeondraft_map", false)
	var first = JSON.print(mod.Global.ModMapData)
	tool.markers[1].set_primitives([])
	tool.templates[2].data.relative_points[0] = Vector2(100, 200)
	assert_eq(JSON.print(mod.Global.ModMapData), first)
	editor.emit_signal("OnSaveBegin", "backup.dungeondraft_map", true)
	assert_ne(JSON.print(mod.Global.ModMapData), first)
	assert_true(mod.Global.ModMapData.other_mod.untouched)
	signaling.emit_signal("unload")
	assert_eq(editor.get_signal_connection_list("OnSaveBegin").size(), 0)
	assert_eq(signaling.get_signal_connection_list("unload").size(), 0)


func test_map_switch_missing_data_clears_previous_map_and_late_world_restores():
	populate()
	var saved = saved_json()
	mod.Global.World = null
	persistence.update()
	assert_eq(tool.markers, [])
	mod.Global.ModMapData = saved
	mod.Global.World = world
	mod.Global.WorldUI = null
	persistence.update()
	assert_eq(tool.markers, [])
	mod.Global.WorldUI = world_ui
	persistence.update()
	assert_eq(tool.markers.size(), 3)
	tool.markers[0].angle = 99.0
	persistence.update()
	assert_eq(tool.markers[0].angle, 99.0, "Normal updates must not reload saved data")
	var other_world = Node.new()
	mod.Global.World = other_world
	mod.Global.ModMapData = {}
	persistence.update()
	assert_eq(tool.markers, [])
	assert_eq(tool.fills, [])
	assert_eq(tool.templates, [])
	other_world.free()


func test_counter_repair_and_explicit_empty_shape_outline():
	populate()
	tool.markers[1].set_primitives([])
	var data = saved_json()
	for key in ["next_id", "next_fill_id", "template_next_id"]:
		data[persistence.DATA_KEY][key] = 0
	assert_true(persistence.load_map(data))
	assert_eq(tool.next_id, 6)
	assert_eq(tool.next_fill_id, 10)
	assert_eq(tool.template_next_id, 7)
	assert_eq(tool.markers[1].get_primitives(), [])


func test_loaded_markers_and_fills_keep_delete_undo_redo_and_template_placement():
	populate()
	assert_true(persistence.load_map(saved_json()))
	var history = load(mod_root.plus_file("scripts/tool/GuidesLinesHistory.gd"))
	var saved = tool.markers_lookup[4].Save()
	var deletion = history.DeleteMarkerRecord.new(tool, saved, 1)
	deletion.redo()
	assert_false(tool.markers_lookup.has(4))
	deletion.undo()
	assert_eq_deep(tool.markers_lookup[4].Save(), saved)
	deletion.redo()
	assert_false(tool.markers_lookup.has(4))
	deletion.undo()
	var fill = tool.fills_lookup[9].Save()
	var fill_deletion = history.DeleteAllFillsRecord.new(tool, [fill])
	fill_deletion.redo()
	assert_false(tool.fills_lookup.has(9))
	fill_deletion.undo()
	assert_eq_deep(tool.fills_lookup[9].Save(), fill)
	# The real placement path consumes decoded template vectors/colors.
	mod.Global.Editor = {"IsSnapping": false}
	tool.cached_world = {"WorldRect": Rect2(-1000, -1000, 2000, 2000), "Level": {"TileMap": {"CellSize": Vector2(100, 100)}}}
	for index in range(tool.templates.size()):
		tool.select_template(index)
		var id = tool.next_id
		tool._place_template_marker(Vector2(100, 200))
		assert_true(tool.markers_lookup.has(id))
		assert_eq(tool.markers_lookup[id].position, Vector2(100, 200))
		assert_eq(tool.markers_lookup[id].marker_type, tool.templates[index].data.marker_type)
	assert_eq(tool.markers_lookup[51].get_primitives()[0].a, Vector2(101, 202))
	assert_eq(tool.markers_lookup[52].marker_points[1], Vector2(110, 200))

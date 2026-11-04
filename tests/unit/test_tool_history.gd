extends "res://addons/gut/test.gd"

var mod_root = ProjectSettings.globalize_path("res://").plus_file("..").simplify_path()
var tool
var api
var last_record
var deleted_ids = []


func before_each():
	var mod = {"markers_opacity": 0.7, "guides_lines_api": null,
		"Global": {"API": {"HistoryApi": self}, "Editor": {"IsSnapping": false}}}
	tool = load(mod_root.plus_file("scripts/tool/GuidesLinesTool.gd")).new(mod)
	tool.GuideMarkerClass = load(mod_root.plus_file("scripts/guides/GuideMarker.gd"))
	tool.cached_world = {"WorldRect": Rect2(-2000, -2000, 4000, 4000),
		"Level": {"TileMap": {"CellSize": Vector2(100, 100)}}}
	mod["guides_tool"] = tool
	api = load(mod_root.plus_file("scripts/api/guides_lines_api.gd")).new(mod, null)
	mod.guides_lines_api = api


func after_each():
	# Break the real constructor's collaborator cycles explicitly.
	last_record = null
	api._unload()
	tool.parent_mod.clear()
	tool.ui.tool = null
	tool.placement.tool = null
	tool._fill_handler.tool = null
	tool = null
	api = null


func record(value, _max_count):
	last_record = value


func on_marker_deleted(id):
	deleted_ids.append(id)


func shape_data(id, pos = Vector2.ZERO):
	return {"id": id, "position": pos, "marker_type": "Shape", "coordinates": true,
		"color": Color(0.2, 0.4, 0.6), "shape_radius": 2.0, "shape_angle": 45.0, "shape_sides": 4}


func add_shape(id, pos = Vector2.ZERO):
	tool._do_place_marker(shape_data(id, pos))
	var marker = tool.markers_lookup[id]
	marker.get_draw_data(tool.cached_world.WorldRect, tool._get_grid_cell_size())
	return marker


func test_delete_undo_restores_exact_geometry_without_applying_current_modes():
	var marker = add_shape(7)
	marker.set_primitives([{"type": "seg", "a": Vector2(4, 8), "b": Vector2(16, 8)}])
	var saved = marker.Save()
	var neighbor = add_shape(8)
	var neighbor_saved = neighbor.Save()
	tool.api_delete_marker_by_id(7)
	tool.conforming_mode = true
	tool.wrapping_mode = true
	last_record.undo()
	assert_eq_deep(tool.markers_lookup[7].Save(), saved)
	assert_eq_deep(neighbor.Save(), neighbor_saved)
	assert_eq(tool.markers.size(), tool.markers_lookup.size())
	tool.delete_all_markers()
	last_record.undo()
	assert_eq_deep(tool.markers_lookup[7].Save(), saved)
	assert_eq(tool.markers.size(), tool.markers_lookup.size())


func test_template_redo_keeps_rotated_primitives_and_original_overlap_mode():
	var relative = [{"type": "seg", "a": Vector2(0, 10), "b": Vector2(20, 10)}]
	var data = shape_data(0)
	data["shape_primitives"] = relative
	tool.templates = [{"data": data}]
	tool.active_template_index = 0
	tool.template_rotation_offset = 90.0
	tool._place_template_marker(Vector2(500, 500))
	var saved = tool.markers[0].Save()
	var placement_record = last_record
	placement_record.undo()
	tool.wrapping_mode = true
	tool.active_shape_radius = 50.0
	placement_record.redo()
	assert_eq_deep(tool.markers[0].Save(), saved)
	assert_true(tool.wrapping_mode, "Redo restores the current UI mode after using the recorded mode")
	var seg = tool.markers[0].get_primitives()[0]
	assert_almost_eq(seg.a.x, 490.0, 0.0001)
	assert_almost_eq(seg.b.y, 520.0, 0.0001)
	assert_eq_deep(relative, [{"type": "seg", "a": Vector2(0, 10), "b": Vector2(20, 10)}])


func test_conforming_redo_uses_stored_shape_not_active_settings():
	var existing = add_shape(8)
	var original = existing.get_primitives().duplicate(true)
	tool.conforming_mode = true
	tool.api_place_marker(shape_data(9, Vector2(140, 0)))
	var clipped = existing.get_primitives().duplicate(true)
	assert_ne(clipped, original)
	var placement_record = last_record
	placement_record.undo()
	assert_eq_deep(existing.get_primitives(), original)
	tool.conforming_mode = false
	tool.active_shape_radius = 0.1
	placement_record.redo()
	assert_eq_deep(existing.get_primitives(), clipped)
	placement_record.undo()
	assert_eq_deep(existing.get_primitives(), original)
	assert_false(tool.conforming_mode)


func test_cut_undo_restores_metadata_for_deleted_and_converted_shapes():
	for radius in [1.0, 5.0]:
		tool._do_delete_all()
		var marker = add_shape(5)
		marker.color = Color(0.12345, 0.54321, 0.98765)
		var saved = marker.Save()
		var original_polygon = marker.get_polygon().duplicate()
		var cutter = shape_data(6, Vector2(120, 0))
		cutter.shape_radius = radius
		var desc = tool._get_shape_descriptor_from_marker_data(cutter)
		var snapshots = tool._take_cut_snapshot(desc)
		assert_true(snapshots.has(5))
		var result = tool._do_apply_cut(desc)
		tool._undo_cut(snapshots, result.deleted_ids, result.created_markers_data)
		assert_eq_deep(tool.markers_lookup[5].Save(), saved)
		assert_eq_deep(tool._get_shape_descriptor(tool.markers_lookup[5], Vector2(100, 100)).points, original_polygon)
		assert_eq(tool.markers_lookup[5].color, marker.color)
		assert_eq(tool.markers.size(), tool.markers_lookup.size())


func test_merge_undo_restores_absorbed_shape_metadata():
	deleted_ids = []
	api.connect("marker_deleted", self, "on_marker_deleted")
	var first = add_shape(1, Vector2(-150, 0))
	var second = add_shape(2, Vector2(150, 0))
	second.color = Color(0.12345, 0.54321, 0.98765)
	var saved_first = first.Save()
	var saved_second = second.Save()
	var first_polygon = first.get_polygon().duplicate()
	var second_polygon = second.get_polygon().duplicate()
	var desc = tool._get_shape_descriptor_from_marker_data(shape_data(3))
	var snapshots = tool._snapshot_potential_merge_targets(desc)
	var absorbed = tool._do_apply_merge(desc, Vector2.ZERO)
	assert_eq_deep(absorbed, [2])
	assert_eq_deep(deleted_ids, [2])
	var history = load(mod_root.plus_file("scripts/tool/GuidesLinesHistory.gd"))
	var merge_record = history.MergeShapeRecord.new(tool, desc, Vector2.ZERO, snapshots, absorbed)
	merge_record.undo()
	assert_eq_deep(tool.markers_lookup[1].Save(), saved_first)
	assert_eq_deep(tool.markers_lookup[2].Save(), saved_second)
	assert_eq_deep(tool._get_shape_descriptor(tool.markers_lookup[1], Vector2(100, 100)).points, first_polygon)
	assert_eq_deep(tool._get_shape_descriptor(tool.markers_lookup[2], Vector2(100, 100)).points, second_polygon)
	assert_eq(tool.markers_lookup[2].color, second.color)
	assert_eq(tool.markers.size(), tool.markers_lookup.size())


func test_spatial_queries_find_shape_and_path_edges_far_from_anchor():
	for kind in ["Shape", "Path"]:
		tool._do_delete_all()
		var data = shape_data(1)
		data.marker_type = kind
		data["shape_primitives"] = [{"type": "seg", "a": Vector2(500, -50), "b": Vector2(500, 50)}]
		data["marker_points"] = [Vector2.ZERO, Vector2(500, -50), Vector2(500, 50)]
		data["path_closed"] = false
		tool._do_place_marker(data)
		var point = api.find_nearest_geometry_point(Vector2(505, 0), 10.0)
		assert_not_null(point, kind)
		if point != null:
			assert_eq(point.point, Vector2(500, 0))
			assert_eq(point.distance, 5.0)
		var crossing = api.find_line_intersection(Vector2(490, 0), Vector2(510, 0), Vector2(505, 0), 10.0)
		assert_not_null(crossing, kind)
		if crossing != null:
			assert_eq(crossing.point, Vector2(500, 0))
		assert_null(api.find_nearest_geometry_point(Vector2(900, 900), 1.0))


func test_wrapping_contract_includes_causing_markers_without_changing_them():
	var marker = add_shape(1)
	var saved = marker.Save()
	var result = tool.api_place_shape_wrapping(shape_data(2, Vector2(140, 0)))
	assert_eq_deep(result.dented_by, [1])
	assert_eq(result.affected_markers.size(), 1)
	assert_eq(result.affected_markers[0].marker_id, 1)
	assert_eq(result.affected_markers[0].new_polygon.size(), 4)
	assert_eq_deep(marker.Save(), saved)
	assert_true(result.marker_polygon.size() >= 3)
	tool.cached_world = null
	assert_eq_deep(tool.api_place_shape_wrapping(shape_data(3)).affected_markers, [])


func test_side_callbacks_apply_hex_edge_correction_immediately():
	tool.cached_snappy_mod = {"custom_snap_enabled": true, "active_geometry": 1,
		"radial_mode_to_corner": false, "snap_interval": Vector2(100, 100)}
	tool.active_marker_type = "Shape"
	tool.active_shape_size_mode = "side"
	tool.active_shape_sides = 6
	tool.ui._on_shape_side_changed(2.0)
	assert_almost_eq(tool.active_shape_radius, 4.0 / sqrt(3.0), 0.00001)
	tool.ui.adjust_shape_radius_with_wheel(1)
	assert_almost_eq(tool.active_shape_radius, 4.2 / sqrt(3.0), 0.00001)
	tool.ui._on_shape_sides_changed(4)
	assert_almost_eq(tool.active_shape_radius, 2.1 / sqrt(2.0) * 2.0 / sqrt(3.0), 0.00001)
	tool.cached_snappy_mod.radial_mode_to_corner = true
	assert_almost_eq(tool.recompute_radius_from_side(), 2.1 / sqrt(2.0), 0.00001)


func test_switching_radius_to_side_preserves_hex_shape_size():
	tool.cached_snappy_mod = {"custom_snap_enabled": true, "active_geometry": 2,
		"radial_mode_to_corner": false, "snap_interval": Vector2(100, 100)}
	tool.active_shape_sides = 6
	tool.active_shape_radius = 2.0
	var container = VBoxContainer.new()
	var option = OptionButton.new()
	option.name = "ShapeSizeModeOption"
	option.add_item("Side")
	option.set_item_metadata(0, "side")
	container.add_child(option)
	tool.ui.shape_settings_container = container
	tool.ui._controls["ShapeSizeModeOption"] = option
	tool.ui._on_shape_size_mode_changed(0)
	assert_almost_eq(tool.active_shape_side, sqrt(3.0), 0.00001)
	assert_almost_eq(tool.recompute_radius_from_side(), 2.0, 0.00001)
	tool.ui.shape_settings_container = null
	container.free()


func test_tool_state_exposes_current_move_cut_size_and_template_settings():
	tool.move_mode = true
	tool.cut_mode = true
	tool.active_shape_size_mode = "side"
	tool.active_shape_side = 3.5
	tool.active_template_index = 2
	tool.template_capture_mode = true
	var state = api.get_tool_state()
	for key in ["move_mode", "cut_mode", "active_shape_size_mode", "active_shape_side",
			"active_template_index", "template_capture_mode"]:
		assert_eq(state[key], tool.get(key), key)

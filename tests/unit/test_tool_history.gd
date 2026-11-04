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


func test_shared_nearest_queries_keep_anchor_edge_and_tie_contracts():
	var marker = add_shape(1)
	marker.set_primitives([
		{"type": "seg", "a": Vector2(-10, -10), "b": Vector2(10, -10)},
		{"type": "seg", "a": Vector2(-10, 10), "b": Vector2(10, 10)}])
	var anchored = api.find_nearest_marker_by_geometry(Vector2.ZERO, 0.0)
	assert_eq(anchored.id, 1)
	assert_eq(anchored.point, Vector2.ZERO)
	assert_null(api.find_nearest_geometry_point(Vector2.ZERO, 0.0))
	var edge = api.find_nearest_geometry_point(Vector2.ZERO, 10.0)
	assert_eq(edge.point, Vector2(0, 10), "Edge query selects the last equally distant segment")
	assert_eq(edge.marker_id, 1)
	assert_eq(edge.distance, 10.0)
	var other = add_shape(2)
	other.set_primitives(marker.get_primitives().duplicate(true))
	assert_eq(api.find_nearest_geometry_point(Vector2.ZERO, 10.0).marker_id, 2)
	assert_eq(api.find_nearest_marker_by_geometry(Vector2.ZERO, 0.0).id, 2)
	assert_null(api.find_nearest_geometry_point(Vector2(1000, 1000), 1.0))
	marker.set_primitives([])
	other.set_primitives([])
	assert_null(api.find_nearest_geometry_point(Vector2.ZERO, 100.0))


func test_explicit_api_placement_modes_restore_ui_flags_and_redo_exactly():
	for wrapping in [false, true]:
		tool.markers.clear()
		tool.markers_lookup.clear()
		var neighbor = add_shape(100)
		var original = neighbor.Save()
		tool.conforming_mode = wrapping
		tool.wrapping_mode = not wrapping
		var result
		if wrapping:
			result = tool.api_place_shape_wrapping(shape_data(101, Vector2(150, 0)))
		else:
			result = tool.api_place_shape_conforming(shape_data(101, Vector2(150, 0)))
		assert_eq(result.marker_id, 101)
		var placed = tool.markers_lookup[101].Save()
		var changed_neighbor = neighbor.Save()
		var placement = last_record
		assert_eq(placement.record_type(), "GuidesLines.PlaceMarker")
		assert_eq(tool.conforming_mode, wrapping)
		assert_eq(tool.wrapping_mode, not wrapping)
		placement.undo()
		assert_eq_deep(neighbor.Save(), original)
		placement.redo()
		assert_eq_deep(tool.markers_lookup[101].Save(), placed)
		assert_eq_deep(neighbor.Save(), changed_neighbor)
		assert_eq(tool.conforming_mode, wrapping)
		assert_eq(tool.wrapping_mode, not wrapping)


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
	tool.next_id = 1
	merge_record.undo()
	assert_true(tool.next_id > 2, "Restored IDs must be reserved before another placement")
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
		tool.parent_mod.guides_lines_api = null
		assert_eq(tool.find_marker_at(Vector2(505, 0), 10.0).id, 1, "UI picking works before API registration")
		assert_true(tool.delete_marker_at_position(Vector2(505, 0), 10.0))
		assert_false(tool.markers_lookup.has(1))
		last_record.undo()
		assert_true(tool.markers_lookup.has(1))
		tool.parent_mod.guides_lines_api = api


func test_merge_partial_failures_preserve_skipped_markers_including_first_candidate():
	var original_script = load(mod_root.plus_file("scripts/tool/GuidesLinesTool.gd"))
	for failed_ids in [[1], [2], [1, 2, 3]]:
		for failure in ["outline", "chain"]:
			var script = GDScript.new()
			var source = original_script.source_code
			for relative in ["../utils/GeometryUtils.gd", "GuidesLinesHistory.gd", "GuidesLinesToolUI.gd", "GuidesLinesPlacement.gd", "GuidesLinesFill.gd"]:
				source = source.replace('preload("' + relative + '")', 'preload("' + mod_root.plus_file("scripts/tool").plus_file(relative).simplify_path() + '")')
			var expression = "GeometryUtils.merge_polygons_outline(running_pts, desc.points)" if failure == "outline" else "GeometryUtils.chain_segments_to_polygon(merged_segs)"
			assert_true(source.find(expression) >= 0, "Fault injection must target the real merge step")
			script.source_code = source.replace(expression, "([] if " + str(failed_ids) + ".has(marker.id) else " + expression + ")")
			assert_eq(script.reload(), OK)
			var subject = script.new(tool.parent_mod)
			subject.GuideMarkerClass = tool.GuideMarkerClass
			subject.cached_world = tool.cached_world
			var saved = {}
			for id in [1, 2, 3]:
				subject._do_place_marker(shape_data(id, Vector2((id - 2) * 100, 0)))
				subject.markers_lookup[id].get_draw_data(subject.cached_world.WorldRect, subject._get_grid_cell_size())
				saved[id] = subject.markers_lookup[id].Save()
			var desc = subject._get_shape_descriptor_from_marker_data(shape_data(4, Vector2(0, 50)))
			var absorbed = subject._do_apply_merge(desc, Vector2(0, 50))
			for id in failed_ids:
				assert_false(absorbed.has(id), failure)
				assert_true(subject.markers_lookup.has(id), failure)
				if subject.markers_lookup.has(id):
					assert_eq_deep(subject.markers_lookup[id].Save(), saved[id])
			assert_eq(subject.markers.size(), subject.markers_lookup.size())
			if failed_ids.size() == 3:
				assert_eq(subject.markers.size(), 3)
			else:
				assert_eq(subject.markers.size(), 2)
				assert_eq(absorbed.size(), 1)
			subject.ui.tool = null
			subject.placement.tool = null
			subject._fill_handler.tool = null
			subject.parent_mod = null


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
	tool.set_shape_side(2.0)
	assert_almost_eq(tool.active_shape_radius, 4.0 / sqrt(3.0), 0.00001)
	tool.adjust_shape_radius_with_wheel(1)
	assert_almost_eq(tool.active_shape_radius, 4.2 / sqrt(3.0), 0.00001)
	tool.set_shape_sides(4)
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


func test_parameter_actions_and_type_memory_work_without_ui():
	var sidebar = tool.ui
	tool.ui = null
	tool.set_angle(359.0)
	tool.set_mirror(true)
	tool.adjust_angle_with_wheel(1)
	assert_eq(tool.active_angle, 0.0)
	tool.adjust_angle_with_wheel(-1)
	assert_eq(tool.active_angle, 359.0)
	tool.set_marker_type("Shape")
	tool.set_shape_preset("Square")
	assert_eq(tool.active_shape_sides, 4)
	assert_eq(tool.active_shape_angle, 45.0)
	tool.set_shape_radius(2.0)
	tool.set_shape_size_mode("side")
	assert_almost_eq(tool.active_shape_side, 2.0 * sqrt(2.0), 0.00001)
	tool.set_shape_side(0.1)
	tool.adjust_shape_radius_with_wheel(-1)
	assert_eq(tool.active_shape_side, 0.1)
	tool.set_shape_side(2.0)
	tool.set_shape_angle(358.0)
	tool.adjust_shape_angle_with_wheel(1)
	assert_eq(tool.active_shape_angle, 3.0)
	tool.rotate_shape_45()
	assert_eq(tool.active_shape_angle, 48.0)
	tool.set_marker_type("Path")
	tool.set_path_end_arrow(true)
	tool.set_path_arrow_head_length(23.0)
	tool.set_path_arrow_head_angle(17.0)
	tool.path_placement_active = true
	tool.path_temp_points = [Vector2.ZERO]
	tool.set_marker_type("Fill")
	assert_false(tool.path_placement_active)
	assert_eq(tool.path_temp_points, [])
	tool.set_delete_mode(true)
	assert_eq(tool.active_marker_type, "Line")
	assert_eq(tool.active_angle, 359.0)
	assert_true(tool.active_mirror)
	tool.set_marker_type("Template")
	tool.template_capture_mode = true
	tool.set_marker_type("Shape")
	assert_false(tool.template_capture_mode)
	assert_eq(tool.active_shape_size_mode, "side")
	assert_eq(tool.active_shape_side, 2.0)
	assert_eq(tool.active_shape_angle, 48.0)
	assert_eq(tool.active_shape_sides, 4)
	tool.set_shape_preset("Circle")
	assert_eq(tool.active_shape_size_mode, "radius")
	assert_eq(tool.active_shape_sides, 64)
	tool.set_marker_type("Path")
	assert_true(tool.active_path_end_arrow)
	assert_eq(tool.active_arrow_head_length, 23.0)
	assert_eq(tool.active_arrow_head_angle, 17.0)
	tool.set_marker_type("unsupported")
	assert_eq(tool.active_marker_type, "Path")
	tool.ui = sidebar


func test_shape_intersections_keep_endpoint_tolerance_after_bounds_filter():
	var a = {"shape_type": "poly", "points": [Vector2.ZERO, Vector2(100000, 0)]}
	var near = {"shape_type": "poly", "points": [Vector2(100000.05, -10), Vector2(100000.05, 10)]}
	var far = {"shape_type": "poly", "points": [Vector2(200000, -10), Vector2(200000, 10)]}
	assert_true(tool._shapes_intersect(a, near))
	assert_false(tool._shapes_intersect(a, far))
	assert_false(tool._shapes_intersect({"shape_type": "poly", "points": []}, near))


func test_type_setting_restoration_retains_legacy_missing_field_defaults():
	tool.type_settings["Shape"] = {"radius": 3.0}
	tool.load_type_settings("Shape")
	assert_eq(tool.active_shape_radius, 3.0)
	assert_eq(tool.active_shape_sides, 6)
	assert_eq(tool.active_shape_angle, 0.0)
	assert_eq(tool.active_shape_size_mode, "radius")
	assert_eq(tool.active_shape_side, 1.0)
	tool.type_settings["Path"] = {"end_arrow": true}
	tool.load_type_settings("Path")
	assert_true(tool.active_path_end_arrow)
	assert_eq(tool.active_arrow_head_length, 50.0)
	assert_eq(tool.active_arrow_head_angle, 30.0)


func test_placement_coordinate_alias_precedence_and_absence():
	for flags in [{}, {"show_coordinates": true}, {"coordinates": false, "show_coordinates": true}]:
		var data = {"id": 1, "position": Vector2.ZERO, "marker_type": "Line", "color": Color.blue}
		for key in flags:
			data[key] = flags[key]
		tool._do_place_marker(data)
		assert_eq(tool.markers_lookup[1].show_coordinates,
			flags.get("coordinates", flags.get("show_coordinates", false)))
		tool._undo_place_marker(1)


func test_new_placement_records_use_line_only_canonical_coordinate_flag():
	tool.show_coordinates = true
	for kind in ["Line", "Shape", "Path"]:
		tool.set_marker_type(kind)
		tool.place_marker(Vector2.ZERO)
		if kind == "Path":
			tool.place_marker(Vector2(100, 0))
			tool._finalize_path_marker(false)
		assert_false(last_record.marker_data.has("coordinates"))
		assert_eq(last_record.marker_data.has("show_coordinates"), kind == "Line")
		assert_eq(tool.markers.back().show_coordinates, kind == "Line")
	var id = api.place_line_marker(Vector2(0, 200))
	assert_true(last_record.marker_data.show_coordinates)
	assert_true(tool.markers_lookup[id].show_coordinates)
	for other_id in [api.place_shape_marker(Vector2(200, 200)), api.place_path_marker([Vector2(300, 0), Vector2(300, 100)])]:
		assert_false(tool.markers_lookup[other_id].show_coordinates)
	assert_false(last_record.marker_data.has("show_coordinates"))
	assert_false(last_record.marker_data.has("coordinates"))


func test_move_mode_exits_fill_and_preserves_line_settings():
	tool.set_angle(37.0)
	tool.set_marker_type("Fill")
	tool.set_move_mode(true)
	assert_eq(tool.active_marker_type, "Line")
	assert_eq(tool.active_angle, 37.0)
	assert_true(tool.move_mode)
	tool.set_move_mode(false)
	assert_false(tool.move_mode)
	assert_eq(tool.active_marker_type, "Line")


func test_virtual_descriptors_match_model_without_instantiating_markers():
	var marker = tool.GuideMarkerClass.new(Vector2(30, 40))
	marker.marker_type = "Shape"
	marker.shape_radius = 3.0
	marker.shape_sides = 5
	marker.shape_angle = -90.0
	var expected = tool._get_shape_descriptor(marker, tool._get_grid_cell_size())
	var data = {"position": marker.position, "shape_radius": 3.0, "shape_sides": 5, "shape_angle": -90.0}
	tool.GuideMarkerClass = null
	assert_eq_deep(tool._get_shape_descriptor_from_marker_data(data), expected)
	data["shape_primitives"] = []
	assert_eq_deep(tool._get_shape_descriptor_from_marker_data(data), {})
	data.erase("shape_primitives")
	data.erase("shape_sides")
	assert_eq(tool._get_shape_descriptor_from_marker_data(data).points.size(), 6)
	tool.active_shape_radius = 3.0
	tool.active_shape_sides = 5
	tool.active_shape_angle = -90.0
	assert_eq_deep(tool._build_shape_descriptor_at(marker.position), expected)
	tool.templates = [{"data": {"marker_type": "Shape", "shape_radius": 3.0, "shape_sides": 5, "shape_angle": -90.0}}]
	tool.active_template_index = 0
	assert_eq_deep(tool._build_shape_descriptor_from_template(marker.position), expected)

extends "res://addons/gut/test.gd"

var mod_root = ProjectSettings.globalize_path("res://").plus_file("..").simplify_path()


func test_line_shape_and_path_round_trip_through_json():
	var script = load(mod_root.plus_file("scripts/guides/GuideMarker.gd"))
	for kind in ["Line", "Shape", "Path"]:
		var marker = script.new(Vector2(10, 20), 37.0, true, true)
		marker.marker_type = kind
		marker.shape_radius = 3.0
		marker.shape_angle = 27.0
		marker.shape_sides = 5
		marker.marker_points = [Vector2(1, 2), Vector2(3, 4), Vector2(5, 1)]
		marker.path_closed = true
		marker.path_end_arrow = true
		marker.arrow_head_length = 17.0
		marker.arrow_head_angle = 24.0
		var restored = script.new()
		restored.Load(JSON.parse(JSON.print(marker.Save())).result)
		assert_eq(restored.marker_type, kind)
		assert_eq(restored.position, Vector2(10, 20))
		assert_true(restored.show_coordinates)
		if kind == "Line":
			assert_eq(restored.angle, 37.0)
			assert_true(restored.mirror)
		elif kind == "Shape":
			assert_eq(restored.shape_radius, 3.0)
			assert_eq(restored.shape_angle, 27.0)
			assert_eq(int(restored.shape_sides), 5)
			assert_eq(restored.marker_points.size(), 0)
		else:
			assert_eq_deep(restored.marker_points, marker.marker_points)
			assert_true(restored.path_closed)
			assert_true(restored.path_end_arrow)
			assert_eq(restored.arrow_head_length, 17.0)
			assert_eq(restored.arrow_head_angle, 24.0)


func test_shape_preserves_modified_primitives_until_clear_clip():
	var script = load(mod_root.plus_file("scripts/guides/GuideMarker.gd"))
	var marker = script.new()
	marker.marker_type = "Shape"
	marker.shape_sides = 4
	var rect = Rect2(-100, -100, 200, 200)
	marker.get_draw_data(rect, Vector2(10, 10))
	var modified = [{"type": "seg", "a": Vector2(1, 2), "b": Vector2(3, 4)}]
	marker.set_primitives(modified)
	marker.set_property("show_coordinates", true)
	assert_eq_deep(marker.get_draw_data(rect, Vector2(10, 10)).primitives, modified)
	marker.clear_clip()
	assert_eq(marker.get_draw_data(rect, Vector2(10, 10)).primitives.size(), 4)


func test_malformed_saved_shape_geometry_does_not_replace_existing_state():
	var script = load(mod_root.plus_file("scripts/guides/GuideMarker.gd"))
	var marker = script.new(Vector2(10, 20))
	var saved = marker.Save()
	for invalid in [null, {}, [null], [{"a": [1], "b": [2, 3]}],
			[{"a": ["bad", 1], "b": [2, 3]}], [{"a": [INF, 1], "b": [2, 3]}]]:
		assert_false(marker.Load({"marker_type": "Shape", "shape_primitives": invalid}))
		assert_eq_deep(marker.Save(), saved)


func test_fill_marker_runs_serialization_and_opacity_workflow():
	var script = load(mod_root.plus_file("scripts/guides/FillMarker.gd"))
	var marker = script.new()
	marker.id = 42
	marker.polygon = [Vector2(1, 2), Vector2(5, 2), Vector2(1, 6)]
	marker.color = Color(1, 0, 0, 0.25)
	var saved = marker.Save()
	assert_eq(saved.id, 42)
	assert_eq_deep(saved.polygon, [[1.0, 2.0], [5.0, 2.0], [1.0, 6.0]])
	var restored = script.new()
	# Exercise the actual JSON data boundary rather than passing live objects.
	restored.Load(JSON.parse(JSON.print(saved)).result)
	assert_eq(restored.id, 42.0)
	assert_eq_deep(restored.polygon, [Vector2(1, 2), Vector2(5, 2), Vector2(1, 6)])
	assert_eq(restored.color, Color(1, 0, 0, 0.25))
	restored.update_opacity(0.5)
	assert_almost_eq(restored.draw_color.a, 0.125, 0.00001)


func test_modified_and_empty_shape_outlines_survive_json_and_cache_rebuild():
	var script = load(mod_root.plus_file("scripts/guides/GuideMarker.gd"))
	var marker = script.new()
	marker.marker_type = "Shape"
	var modified = [{"type": "seg", "a": Vector2(1, 2), "b": Vector2(3, 4)}]
	var rect = Rect2(-100, -100, 200, 200)
	for primitives in [modified, []]:
		marker.set_primitives(primitives)
		var restored = script.new()
		restored.Load(JSON.parse(JSON.print(marker.Save())).result)
		restored.set_property("show_coordinates", true)
		assert_eq_deep(restored.get_draw_data(rect, Vector2(10, 10)).primitives, primitives)
		restored.clear_clip()
		assert_eq(restored.get_draw_data(rect, Vector2(10, 10)).primitives.size(), 6)
	# Old maps omit primitives and must still regenerate from parameters.
	marker.Load({"marker_type": "Shape", "shape_sides": 4})
	assert_eq(marker.get_draw_data(rect, Vector2(10, 10)).primitives.size(), 4)

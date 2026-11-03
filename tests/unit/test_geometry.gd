extends "res://addons/gut/test.gd"

# Tests the original mod script in an autonomous Godot CLI environment.
# An absolute path derived from this test root avoids res:// parent clamping.
var geometry = load(ProjectSettings.globalize_path("res://").plus_file("../scripts/utils/GeometryUtils.gd").simplify_path())


func test_square_vertices_use_world_coordinates_and_radians():
	var points = geometry.calculate_shape_vertices(Vector2(10, 20), 2.0, 4, PI / 2.0)
	var expected = [Vector2(10, 22), Vector2(8, 20), Vector2(10, 18), Vector2(12, 20)]
	assert_eq(points.size(), expected.size())
	for i in range(min(points.size(), expected.size())):
		assert_almost_eq(points[i], expected[i], Vector2(0.0001, 0.0001))


func test_side_and_circumradius_match_a_square():
	assert_almost_eq(geometry.side_to_circumradius(2.0, 4), sqrt(2.0), 0.0001)
	assert_almost_eq(geometry.circumradius_to_side(sqrt(2.0), 4), 2.0, 0.0001)


func test_closest_point_clamps_to_segment_and_handles_zero_length():
	assert_eq(geometry.closest_point_on_segment(Vector2(5, 3), Vector2.ZERO, Vector2(10, 0)), Vector2(5, 0))
	assert_eq(geometry.closest_point_on_segment(Vector2(-2, 3), Vector2.ZERO, Vector2(10, 0)), Vector2.ZERO)
	assert_eq(geometry.closest_point_on_segment(Vector2(12, 3), Vector2.ZERO, Vector2(10, 0)), Vector2(10, 0))
	assert_eq(geometry.closest_point_on_segment(Vector2(8, 9), Vector2(2, 3), Vector2(2, 3)), Vector2(2, 3))


func test_segment_intersection_accepts_crossing_and_shared_endpoint():
	assert_eq(geometry.segment_segment_intersect(Vector2.ZERO, Vector2(10, 10), Vector2(0, 10), Vector2(10, 0)), Vector2(5, 5))
	assert_eq(geometry.segment_segment_intersect(Vector2.ZERO, Vector2(10, 0), Vector2(10, 0), Vector2(10, 10)), Vector2(10, 0))


func test_segment_intersection_rejects_parallel_and_outside_segments():
	assert_null(geometry.segment_segment_intersect(Vector2.ZERO, Vector2(10, 0), Vector2(0, 2), Vector2(10, 2)))
	assert_null(geometry.segment_segment_intersect(Vector2.ZERO, Vector2(1, 0), Vector2(2, -1), Vector2(2, 1)))


func test_circle_intersection_distinguishes_secant_tangent_and_miss():
	assert_eq(geometry.line_intersect_circle(Vector2.ZERO, Vector2.RIGHT, Vector2.ZERO, 2.0), [Vector2(-2, 0), Vector2(2, 0)])
	assert_eq(geometry.line_intersect_circle(Vector2(0, 2), Vector2.RIGHT, Vector2.ZERO, 2.0), [Vector2(0, 2)])
	assert_eq(geometry.line_intersect_circle(Vector2(0, 3), Vector2.RIGHT, Vector2.ZERO, 2.0), [])


func test_segment_clipping_distinguishes_crossing_and_parallel_miss():
	var bounds = Rect2(0, 0, 10, 10)
	assert_eq(geometry.clip_line_segment_to_rect(Vector2(-5, 5), Vector2(15, 5), bounds), [Vector2(0, 5), Vector2(10, 5)])
	assert_eq(geometry.clip_line_segment_to_rect(Vector2(-5, -1), Vector2(15, -1), bounds), [])


func test_ray_clipping_does_not_extend_behind_its_origin():
	var bounds = Rect2(0, 0, 10, 10)
	assert_eq(geometry.clip_ray_to_rect(Vector2(5, 5), Vector2.RIGHT, bounds), [Vector2(5, 5), Vector2(10, 5)])
	assert_null(geometry.clip_ray_to_rect(Vector2(15, 5), Vector2.RIGHT, bounds))


func test_polygon_segments_close_the_last_edge():
	var points = [Vector2.ZERO, Vector2(10, 0), Vector2(0, 10)]
	var segments = geometry.points_to_segs(points)
	assert_eq(segments.size(), 3)
	assert_eq_deep(segments[2], {"type": "seg", "a": Vector2(0, 10), "b": Vector2.ZERO})
	assert_eq(geometry.points_to_segs([]), [])


func test_chaining_reversed_unordered_edges_preserves_square():
	var segments = [
		{"type": "seg", "a": Vector2(10, 0), "b": Vector2(10, 10)},
		{"type": "seg", "a": Vector2.ZERO, "b": Vector2(0, 10)},
		{"type": "seg", "a": Vector2.ZERO, "b": Vector2(10, 0)},
		{"type": "seg", "a": Vector2(0, 10), "b": Vector2(10, 10)},
	]
	var polygon = geometry.chain_segments_to_polygon(segments)
	assert_eq(polygon.size(), 4)
	for point in [Vector2.ZERO, Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)]:
		assert_has(polygon, point)


func test_cut_chains_extend_backward_without_joining_disconnected_edges():
	var segments = [
		{"type": "seg", "a": Vector2(10, 0), "b": Vector2(20, 0)},
		{"type": "seg", "a": Vector2.ZERO, "b": Vector2(10, 0)},
		{"type": "seg", "a": Vector2(100, 0), "b": Vector2(110, 0)},
	]
	var chains = geometry.split_segments_into_chains(segments)
	assert_eq(chains.size(), 2)
	assert_has(chains, [Vector2.ZERO, Vector2(10, 0), Vector2(20, 0)])
	assert_has(chains, [Vector2(100, 0), Vector2(110, 0)])
	assert_eq(geometry.split_segments_into_chains([]), [])


func test_merge_keeps_containing_outline_and_rejects_separate_shapes():
	var outer = [Vector2.ZERO, Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]
	var inner = [Vector2(10, 10), Vector2(20, 10), Vector2(20, 20), Vector2(10, 20)]
	var merged = geometry.chain_segments_to_polygon(geometry.merge_polygons_outline(outer, inner))
	assert_eq(merged.size(), 4)
	for point in outer:
		assert_has(merged, point)
	var separate = [Vector2(200, 200), Vector2(210, 200), Vector2(210, 210)]
	assert_eq(geometry.merge_polygons_outline(outer, separate), [])

extends "res://addons/gut/test.gd"

var mod_root = ProjectSettings.globalize_path("res://").plus_file("..").simplify_path()
var geometry = load(mod_root.plus_file("scripts/utils/GeometryUtils.gd"))
var unfiltered


func before_all():
	# Run the same original algorithms with only the broad-phase additions removed.
	# This preserves the old intersection tolerances and boundary behavior as oracle.
	var source = geometry.source_code.replace("\r\n", "\n")
	var start = source.find("\tvar shape_bounds = []")
	var end = source.find("\tfor prim in primitives:", start)
	assert(start > 0)
	source = source.substr(0, start) + source.substr(end)
	start = source.find("\t\t\tvar bounds = polygon_intersection_bounds([a, b])")
	end = source.find("\t\t\tvar ts = [0.0, 1.0]", start)
	assert(start > 0)
	source = source.substr(0, start) + source.substr(end)
	source = source.replace("for shape in nearby_shapes:", "for shape in shapes:")
	var merge_guard = "\tif not polygon_intersection_bounds(pts_a).intersects(polygon_intersection_bounds(pts_b), true):\n\t\treturn []\n"
	assert(source.find(merge_guard) >= 0)
	source = source.replace(merge_guard, "")
	unfiltered = GDScript.new()
	unfiltered.source_code = source
	assert(unfiltered.reload() == OK)


func cases():
	return [[], [Vector2.ZERO], [Vector2.ZERO, Vector2(10, 0)],
		[Vector2.ZERO, Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)],
		[Vector2(10, 0), Vector2(20, 0), Vector2(20, 10), Vector2(10, 10)],
		[Vector2(10, 10), Vector2(20, 10), Vector2(10, 20)],
		[Vector2(2, 2), Vector2(4, 2), Vector2(3, 4)],
		[Vector2(100, 100), Vector2(110, 100), Vector2(110, 110)],
		[Vector2(10.000005, -1), Vector2(20, -1), Vector2(10.000005, 1)],
		geometry.calculate_polygon_vertices(Vector2(100000, -100000), 5000.0, 64),
		geometry.calculate_polygon_vertices(Vector2(102000, -100000), 5000.0, 64)]


func test_bounds_preserve_boolean_outputs_including_degenerate_and_tangent_cases():
	for a in cases():
		for b in cases():
			var shapes = [{"shape_type": "poly", "points": b}]
			assert_eq_deep(geometry.clip_polygon_against_shapes(a, shapes),
				unfiltered.clip_polygon_against_shapes(a, shapes))
			assert_eq_deep(geometry.clip_polygon_inside_shape(a, shapes[0]),
				unfiltered.clip_polygon_inside_shape(a, shapes[0]))
			assert_eq_deep(geometry.merge_polygons_outline(a, b),
				unfiltered.merge_polygons_outline(a, b))
	var a = geometry.points_to_segs(cases()[3])
	var mixed = [{"shape_type": "poly", "points": cases()[6]},
		{"shape_type": "poly", "points": cases()[7]}]
	assert_eq_deep(geometry.clip_primitives_against_shapes(a, mixed),
		unfiltered.clip_primitives_against_shapes(a, mixed))


func test_bounds_include_intersection_endpoint_tolerance():
	var a = [Vector2.ZERO, Vector2(100000, 0)]
	var b = [Vector2(100000.05, -10), Vector2(100000.05, 10)]
	assert_not_null(geometry.segment_segment_intersect(a[0], a[1], b[0], b[1]))
	assert_true(geometry.polygon_intersection_bounds(a).intersects(
		geometry.polygon_intersection_bounds(b), true))
	assert_true(geometry.polygon_intersection_bounds([Vector2.ZERO]).has_point(Vector2.ZERO))


func timed_clip(script, points, shapes, iterations):
	var start = OS.get_ticks_usec()
	for _i in range(iterations):
		script.clip_polygon_against_shapes(points, shapes)
	return OS.get_ticks_usec() - start


func test_benchmark_separate_and_overlapping_64_sided_shapes():
	var a = geometry.calculate_polygon_vertices(Vector2.ZERO, 100.0, 64)
	for center in [Vector2(1000, 1000), Vector2(50, 0)]:
		var shapes = [{"shape_type": "poly", "points":
			geometry.calculate_polygon_vertices(center, 100.0, 64)}]
		assert_eq_deep(geometry.clip_polygon_against_shapes(a, shapes),
			unfiltered.clip_polygon_against_shapes(a, shapes))
		# Timings are diagnostic, never a flaky acceptance threshold or an FPS claim.
		var baseline = timed_clip(unfiltered, a, shapes, 30)
		var optimized = timed_clip(geometry, a, shapes, 30)
		print("AABB clip 64x64, center=%s, 30 iterations: baseline=%dus optimized=%dus" %
			[center, baseline, optimized])

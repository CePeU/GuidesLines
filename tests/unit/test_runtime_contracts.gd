extends "res://addons/gut/test.gd"

var mod_root = ProjectSettings.globalize_path("res://").plus_file("..").simplify_path()


func test_api_rejects_placement_before_tool_initialization():
	var script = load(mod_root.plus_file("scripts/api/guides_lines_api.gd"))
	var api = script.new({"guides_tool": null}, null)
	assert_false(api.is_ready())
	assert_eq(api.place_line_marker(Vector2.ZERO), -1)
	assert_eq(api.place_shape_marker(Vector2.ZERO), -1)
	assert_eq(api.place_path_marker([]), -1)
	api._unload()


func test_render_width_scales_and_clamps_without_drawing():
	var script = load(mod_root.plus_file("scripts/render/GuidesLinesRender.gd"))
	assert_eq(script.get_adaptive_width(2.0, Vector2(3, 3)), 6.0)
	assert_eq(script.get_adaptive_width(2.0, Vector2(0.5, 0.5)), 2.0)
	assert_eq(script.get_adaptive_width(0.2, Vector2.ONE), 1.0)


func test_entry_loads_classes_without_lib_and_waits_for_editor():
	var file = File.new()
	assert_eq(file.open(mod_root.plus_file("GuidesLines.gd"), File.READ), OK)
	var script = GDScript.new()
	script.source_code = "var Global = {}\nvar Script=null\n\n" + file.get_as_text()
	file.close()
	assert_eq(script.reload(), OK)
	var mod = script.new()
	mod.Global = {"Root": mod_root + "/", "API": {}, "Editor": null, "World": null, "WorldUI": null}
	# Exercise early initialization with explicitly unavailable dependencies.
	mod.start()
	for name in ["GuideMarkerClass", "FillMarkerClass", "GuidesLinesToolClass", "MarkerOverlayClass", "CrossOverlay", "PermanentOverlay", "GuidesLinesApiClass"]:
		assert_not_null(mod.get(name), "Loaded by real start(): " + name)
	mod.update(0.016)
	assert_false(mod.tool_created)
	assert_null(mod.guides_tool)

extends "res://addons/gut/test.gd"

# Reusable load/constructor smoke test. Keep mod policy in runtime_files.json.
var mod_root = ProjectSettings.globalize_path("res://").plus_file("..").simplify_path()
var config = {}
var files = []


func _inventory():
	files = []
	var file = File.new()
	assert_eq(file.open("res://runtime_files.json", File.READ), OK, "Inventory config opens")
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	assert_eq(parsed.error, OK, "Inventory config is valid JSON")
	if parsed.error != OK:
		return
	config = parsed.result
	if config.get("root_scripts", false):
		var directory = Directory.new()
		assert_eq(directory.open(mod_root), OK)
		directory.list_dir_begin(true, true)
		var name = directory.get_next()
		while name != "":
			if not directory.current_is_dir() and name.ends_with(".gd"):
				_collect(name)
			name = directory.get_next()
		directory.list_dir_end()
	for path in config.roots:
		assert_false(path.is_abs_path() or ".." in path.split("/"), "Source roots stay in the mod")
		if path.is_abs_path() or ".." in path.split("/"):
			continue
		_collect(path)
	files.sort()
	return files


func _load_script(path):
	var absolute = mod_root.plus_file(path)
	if path in config.get("injected_globals", []):
		# Inject the globals required to compile standalone entry scripts.
		# These declarations supply names only; dependencies remain explicit test inputs.
		var file = File.new()
		if file.open(absolute, File.READ) != OK:
			return null
		var source = file.get_as_text()
		file.close()
		# ponytail: current entries have no extends; reject rather than rewrite
		# an unfamiliar source form. Add an explicit insertion rule if needed.
		if source.begins_with("extend"):
			fail_test("Global declarations require an entry without extends: " + path)
			return null
		var script = GDScript.new()
		script.resource_path = absolute
		script.source_code = "var Global = {}\nvar Script=null\n\n" + source
		assert_eq(script.reload(), OK, "Compile entry with injected globals: " + path)
		return script
	return ResourceLoader.load(absolute, "GDScript", false)


func _collect(relative_path):
	var absolute = mod_root.plus_file(relative_path)
	var directory = Directory.new()
	assert_true(directory.dir_exists(absolute) or File.new().file_exists(absolute), "Inventory path exists: " + relative_path)
	if directory.dir_exists(absolute):
		assert_eq(directory.open(absolute), OK, "Open source directory: " + relative_path)
		directory.list_dir_begin(true, true)
		var name = directory.get_next()
		while name != "":
			_collect(relative_path.plus_file(name))
			name = directory.get_next()
		directory.list_dir_end()
	elif relative_path.ends_with(".gd"):
		assert_true(File.new().file_exists(absolute), "Source exists: " + relative_path)
		assert_false(relative_path in files, "No duplicate source: " + relative_path)
		files.append(relative_path)


func test_all_runtime_scripts_compile():
	_inventory()
	assert_gt(files.size(), 0, "A source inventory must not be empty")
	var classified = config.get("load_only", {}).keys()
	for item in config.get("construct", []):
		assert_false(item.path in classified, "One constructor policy per source: " + item.path)
		classified.append(item.path)
	classified.sort()
	assert_eq_deep(classified, files)
	for path in config.get("injected_globals", []):
		assert_true(path in files, "Configured entry belongs to the source inventory: " + path)
	for reason in config.get("load_only", {}).values():
		assert_true(reason is String and not reason.empty(), "Load-only files need a reason")
	for path in files:
		var script = _load_script(path)
		assert_not_null(script, "Load: " + path)
		if script != null:
			assert_true(script.can_instance(), "Compiled: " + path)


func test_allowed_runtime_objects_construct():
	_inventory()
	assert_gt(config.get("construct", []).size(), 0, "Constructor policy must not be empty")
	for item in config.get("construct", []):
		assert_true(item.path in files, "Constructor belongs to source inventory: " + item.path)
		if not item.path in files:
			continue
		var script = _load_script(item.path)
		if script == null or not script.can_instance():
			fail_test("Cannot construct invalid script: " + item.path)
			continue
		# ponytail: only explicitly reviewed constructors; lifecycle and method
		# arguments needing engine objects belong in a dedicated behavior test.
		var instance = script.callv("new", item.args)
		assert_true(is_instance_valid(instance), "Construct: " + item.path)
		if is_instance_valid(instance) and config.get("entry_contract", {}).has(item.path):
			assert_eq(instance.get("script_class"), config.entry_contract[item.path], "Entry script type: " + item.path)
		if is_instance_valid(instance) and not instance is Reference:
			instance.free()


func test_runtime_entry_sources_match_policy():
	_inventory()
	assert_gt(files.size(), 0)
	for path in files:
		var file = File.new()
		assert_eq(file.open(mod_root.plus_file(path), File.READ), OK)
		var source = file.get_as_text()
		file.close()
		# Standalone entries omit extends; ordinary modules must begin with it.
		assert_eq(not source.begins_with("extend"), path in config.get("injected_globals", []), "Entry source classification: " + path)


func test_runtime_manifest_and_required_resources_exist():
	_inventory()
	var file = File.new()
	assert_eq(file.open(mod_root.plus_file(config.manifest), File.READ), OK)
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	assert_eq(parsed.error, OK, "Manifest JSON")
	if parsed.error == OK:
		for key in ["name", "unique_id", "version", "dd_version"]:
			assert_true(parsed.result.get(key, "") is String and not parsed.result.get(key, "").empty(), "Manifest field: " + key)
		assert_true(parsed.result.get("dependencies", []) is Array)
	for path in config.get("required_resources", []):
		assert_true(File.new().file_exists(mod_root.plus_file(path)), "Required resource: " + path)

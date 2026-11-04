extends Reference

# GuidesLinesToolUI - UI panel creation, callbacks, and widget helpers for GuidesLinesTool.
# Holds all UI node references and handles user input from the tool panel.
# Parameter controls call tool actions; this class synchronizes their presentation.

const CLASS_NAME = "GuidesLinesToolUI"


var _controls = {}
var _icon_cache = {}

var tool = null  # Reference to GuidesLinesTool

# UI node references (owned by this class)
var type_selector = null              # OptionButton for marker type selection
var type_specific_container = null    # Container for type-specific settings
var line_settings_container = null    # Settings for Line type
var shape_settings_container = null   # Settings for Shape type
var path_settings_container = null    # Settings for Path type
var fill_settings_container = null    # Settings for Fill type
var template_settings_container = null   # Settings for Template type
var _template_list_container = null      # VBoxContainer inside scroll for template rows
var _add_template_btn = null             # "Add Template" / "Cancel" button
var _template_overlap_modes_container = null  # Overlap mode buttons row (Shape templates only)

func _init(tool_ref):
	tool = tool_ref

# ============================================================================
# PANEL STATE UPDATES
# ============================================================================

func update_ui():
	if not tool.tool_panel:
		return
	var container = tool.tool_panel.Align.get_child(0)
	if container:
		# Update cancel button visibility for Path mode
		if tool.active_marker_type == tool.MARKER_TYPE_PATH:
			var path_container = type_specific_container.get_node_or_null("PathSettings")
			if path_container:
				var cancel_btn = path_container.get_node_or_null("PathCancelButton")
				if cancel_btn:
					cancel_btn.visible = tool.path_placement_active

func update_ui_checkboxes_state():
	if not tool.tool_panel:
		return
	var container = tool.tool_panel.Align.get_child(0)
	if container:
		# Sync move/delete checkboxes to current state
		_set_control_value("MoveModeCheckbox", tool.move_mode, "pressed")
		_set_control_value("DeleteModeCheckbox", tool.delete_mode, "pressed")

		# Disable controls when delete mode or move mode is on
		var any_special_mode = tool.delete_mode or tool.move_mode
		for child in container.get_children():
			if child is CheckButton:
				if child.name == "DeleteModeCheckbox" or child.name == "MoveModeCheckbox":
					continue  # Don't disable mode checkboxes themselves
				child.disabled = any_special_mode
			# Also disable spinboxes, color picker, and buttons
			elif child is HBoxContainer:
				for subchild in child.get_children():
					if subchild is SpinBox or subchild is ColorPickerButton:
						subchild.editable = not any_special_mode
			elif child is Button:
				if child.name == "DeleteAllMarkersButton":
					child.disabled = not tool.delete_mode
				else:
					child.disabled = any_special_mode
			elif child is GridContainer:
				for btn in child.get_children():
					if btn is Button:
						btn.disabled = any_special_mode

# ============================================================================
# PANEL CREATION
# ============================================================================

# Create the UI panel for the tool with all controls
# Includes marker type selector and type-specific settings
func create_ui_panel():
	if not tool.tool_panel:
		return

	_controls.clear()
	var container = VBoxContainer.new()

	# Title
	var title = Label.new()
	title.text = "Guide Markers"
	title.align = Label.ALIGN_CENTER
	container.add_child(title)

	container.add_child(_create_spacer(10))

	# === MARKER TYPE SELECTOR ===
	var type_label = Label.new()
	type_label.text = "Marker Type:"
	container.add_child(type_label)

	type_selector = OptionButton.new()
	type_selector.add_item("Line")
	type_selector.set_item_metadata(0, tool.MARKER_TYPE_LINE)
	type_selector.add_item("Shape")
	type_selector.set_item_metadata(1, tool.MARKER_TYPE_SHAPE)
	type_selector.add_item("Path")
	type_selector.set_item_metadata(2, tool.MARKER_TYPE_PATH)
	type_selector.add_item("Fill")
	type_selector.set_item_metadata(3, tool.MARKER_TYPE_FILL)
	type_selector.add_item("Template")
	type_selector.set_item_metadata(4, tool.MARKER_TYPE_TEMPLATE)
	type_selector.selected = 0
	type_selector.name = "TypeSelector"
	_controls["TypeSelector"] = type_selector
	type_selector.connect("item_selected", self, "_on_marker_type_changed")
	container.add_child(type_selector)

	container.add_child(_create_spacer(15))

	# === TYPE-SPECIFIC SETTINGS CONTAINER ===
	type_specific_container = VBoxContainer.new()
	type_specific_container.name = "TypeSpecificContainer"
	_controls["TypeSpecificContainer"] = type_specific_container

	# Create Line settings UI
	line_settings_container = _create_line_settings_ui()
	line_settings_container.name = "LineSettings"
	_controls["LineSettings"] = line_settings_container
	type_specific_container.add_child(line_settings_container)

	# Create Shape settings UI
	shape_settings_container = _create_shape_settings_ui()
	shape_settings_container.name = "ShapeSettings"
	_controls["ShapeSettings"] = shape_settings_container
	shape_settings_container.visible = false
	type_specific_container.add_child(shape_settings_container)

	# Create Path settings UI
	path_settings_container = _create_path_settings_ui()
	path_settings_container.name = "PathSettings"
	_controls["PathSettings"] = path_settings_container
	path_settings_container.visible = false
	type_specific_container.add_child(path_settings_container)

	# Create Fill settings UI
	fill_settings_container = _create_fill_settings_ui()
	fill_settings_container.name = "FillSettings"
	_controls["FillSettings"] = fill_settings_container
	fill_settings_container.visible = false
	type_specific_container.add_child(fill_settings_container)

	# Create Template settings UI
	template_settings_container = _create_template_settings_ui()
	template_settings_container.name = "TemplateSettings"
	_controls["TemplateSettings"] = template_settings_container
	template_settings_container.visible = false
	type_specific_container.add_child(template_settings_container)

	container.add_child(type_specific_container)

	container.add_child(_create_spacer(20))

	# === COMMON SETTINGS ===
	var common_container = _create_common_settings_ui()
	container.add_child(common_container)

	container.add_child(_create_spacer(20))

	# === DELETE MODE ===
	var delete_check = CheckButton.new()
	delete_check.text = "Delete Markers Mode"
	delete_check.pressed = tool.delete_mode
	delete_check.name = "DeleteModeCheckbox"
	_controls["DeleteModeCheckbox"] = delete_check
	delete_check.connect("toggled", tool, "set_delete_mode")
	container.add_child(delete_check)

	var delete_all_btn = Button.new()
	delete_all_btn.text = "Delete All Markers"
	delete_all_btn.disabled = not tool.delete_mode
	delete_all_btn.name = "DeleteAllMarkersButton"
	_controls["DeleteAllMarkersButton"] = delete_all_btn
	delete_all_btn.connect("pressed", tool, "delete_all_markers")
	container.add_child(delete_all_btn)

	# === MOVE MODE ===
	var move_check = CheckButton.new()
	move_check.text = "Move Markers Mode"
	move_check.pressed = tool.move_mode
	move_check.name = "MoveModeCheckbox"
	_controls["MoveModeCheckbox"] = move_check
	move_check.connect("toggled", tool, "set_move_mode")
	container.add_child(move_check)

	tool.tool_panel.Align.add_child(container)

# ============================================================================
# UI CREATION HELPERS FOR MARKER TYPES
# ============================================================================

# Create UI for Line marker type
func _create_line_settings_ui():
	var container = VBoxContainer.new()

	# Quick Angle Buttons
	var quick_label = Label.new()
	quick_label.text = "Quick Angles:"
	container.add_child(quick_label)

	var quick_grid = GridContainer.new()
	quick_grid.columns = 4

	var quick_angles = [0, 45, 90, 135, 180, 225, 270, 315]
	var angle_names = ["0°", "45°", "90°", "135°", "180°", "225°", "270°", "315°"]

	for i in range(quick_angles.size()):
		var btn = Button.new()
		btn.text = angle_names[i]
		btn.connect("pressed", tool, "set_angle", [quick_angles[i]])
		quick_grid.add_child(btn)

	container.add_child(quick_grid)
	container.add_child(_create_spacer(10))

	# Angle SpinBox
	var angle_hbox = _create_spinbox_row("Angle (°):", "AngleSpinBox",
		0, 360, 1, tool.active_angle, tool, "set_angle", false)
	container.add_child(angle_hbox)

	# Mirror CheckBox
	var mirror_check = CheckButton.new()
	mirror_check.text = "Mirror"
	mirror_check.pressed = tool.active_mirror
	mirror_check.name = "MirrorCheckbox"
	_controls["MirrorCheckbox"] = mirror_check
	mirror_check.connect("toggled", tool, "set_mirror")
	container.add_child(mirror_check)

	# Show Coordinates CheckBox (Line-only)
	var coords_check = CheckButton.new()
	coords_check.text = "Show Coordinates"
	coords_check.pressed = tool.show_coordinates
	coords_check.name = "CoordinatesCheckbox"
	_controls["CoordinatesCheckbox"] = coords_check
	coords_check.connect("toggled", tool, "set_show_coordinates")
	container.add_child(coords_check)

	return container

# Create UI for Shape marker type
func _create_shape_settings_ui():
	var container = VBoxContainer.new()

	# Shape Subtype Selector
	var subtype_label = Label.new()
	subtype_label.text = "Shape Type:"
	container.add_child(subtype_label)

	var subtype_option = OptionButton.new()
	subtype_option.add_item("Circle")
	subtype_option.set_item_metadata(0, tool.SHAPE_CIRCLE)
	subtype_option.add_item("Square")
	subtype_option.set_item_metadata(1, tool.SHAPE_SQUARE)
	subtype_option.add_item("Pentagon (5-sided)")
	subtype_option.set_item_metadata(2, tool.SHAPE_PENTAGON)
	subtype_option.add_item("Hexagon (6-sided)")
	subtype_option.set_item_metadata(3, tool.SHAPE_HEXAGON)
	subtype_option.add_item("Octagon (8-sided)")
	subtype_option.set_item_metadata(4, tool.SHAPE_OCTAGON)
	subtype_option.add_item("Custom (N-sided)")
	subtype_option.set_item_metadata(5, tool.SHAPE_CUSTOM)

	# Default to Circle preset (index 0)
	subtype_option.selected = 0

	subtype_option.name = "ShapeSubtypeSelector"
	_controls["ShapeSubtypeSelector"] = subtype_option
	subtype_option.connect("item_selected", self, "_on_shape_subtype_changed")
	container.add_child(subtype_option)

	container.add_child(_create_spacer(10))

	# Size Mode row (Radius vs Side) — hidden for Circle
	var size_mode_hbox = HBoxContainer.new()
	size_mode_hbox.name = "SizeModeRow"
	_controls["SizeModeRow"] = size_mode_hbox
	var size_mode_label = Label.new()
	size_mode_label.text = "Size by:"
	size_mode_label.rect_min_size = Vector2(80, 0)
	size_mode_hbox.add_child(size_mode_label)

	var size_mode_option = OptionButton.new()
	size_mode_option.add_item("Radius")
	size_mode_option.set_item_metadata(0, "radius")
	size_mode_option.add_item("Side")
	size_mode_option.set_item_metadata(1, "side")
	size_mode_option.selected = 0
	size_mode_option.name = "ShapeSizeModeOption"
	_controls["ShapeSizeModeOption"] = size_mode_option
	size_mode_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_mode_option.connect("item_selected", self, "_on_shape_size_mode_changed")
	size_mode_hbox.add_child(size_mode_option)
	# Circle is selected by default — hide until a non-circle preset is chosen
	size_mode_hbox.visible = false
	container.add_child(size_mode_hbox)

	container.add_child(_create_spacer(5))

	# Radius SpinBox
	var radius_hbox = _create_spinbox_row("Radius:", "ShapeRadiusSpinBox",
		0.1, 100, 0.1, tool.active_shape_radius, tool, "set_shape_radius", true)
	radius_hbox.name = "RadiusRow"
	_controls["RadiusRow"] = radius_hbox
	radius_hbox.hint_tooltip = "Radius in grid cells (circumradius — distance from center to vertex)"
	container.add_child(radius_hbox)

	# Side SpinBox (shown only when Size mode = Side)
	var side_hbox = _create_spinbox_row("Side:", "ShapeSideSpinBox",
		0.1, 100, 0.1, tool.active_shape_side, tool, "set_shape_side", true)
	side_hbox.name = "SideRow"
	_controls["SideRow"] = side_hbox
	side_hbox.hint_tooltip = "Side length in grid cells — the shape is sized so its edges equal this value"
	side_hbox.visible = false
	container.add_child(side_hbox)

	container.add_child(_create_spacer(5))

	# Angle SpinBox
	var angle_hbox = _create_spinbox_row("Angle (°):", "ShapeAngleSpinBox",
		0, 360, 1, tool.active_shape_angle, tool, "set_shape_angle", false)
	container.add_child(angle_hbox)

	container.add_child(_create_spacer(5))

	# Sides SpinBox (only visible for Custom subtype)
	var sides_hbox = _create_spinbox_row("Sides:", "ShapeSidesSpinBox",
		3, 64, 1, tool.active_shape_sides, tool, "set_shape_sides", false)
	sides_hbox.name = "SidesRow"
	_controls["SidesRow"] = sides_hbox
	container.add_child(sides_hbox)

	# Only show sides row for Custom subtype (hidden by default)
	sides_hbox.visible = false

	container.add_child(_create_spacer(10))

	# Shape Interaction Modes - Row of icon buttons
	var modes_label = Label.new()
	modes_label.text = "Overlap Mode:"
	container.add_child(modes_label)
	container.add_child(_create_spacer(5))

	container.add_child(_create_overlap_modes_row("ShapeModesRow", Vector2(48, 48)))

	return container

# Create UI for Fill type (shown when Fill is selected in the type dropdown)
func _create_fill_settings_ui():
	var container = VBoxContainer.new()

	var hint = Label.new()
	hint.text = "Click inside a Shape to fill\nthe region with the active color."
	hint.autowrap = true
	container.add_child(hint)

	container.add_child(_create_spacer(8))

	var delete_fills_btn = Button.new()
	delete_fills_btn.text = "Delete All Fills"
	delete_fills_btn.connect("pressed", self, "_on_delete_all_fills")
	container.add_child(delete_fills_btn)

	return container

# Create UI for Path marker type
func _create_path_settings_ui():
	var container = VBoxContainer.new()

	# Cancel button (only visible during placement)
	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel Path"
	cancel_btn.name = "PathCancelButton"
	_controls["PathCancelButton"] = cancel_btn
	cancel_btn.connect("pressed", tool, "_cancel_path_placement")
	cancel_btn.visible = false
	container.add_child(cancel_btn)

	container.add_child(_create_spacer(5))

	# End with Arrow checkbox
	var end_arrow_check = CheckButton.new()
	end_arrow_check.text = "End with Arrow"
	end_arrow_check.pressed = tool.active_path_end_arrow
	end_arrow_check.name = "PathEndArrowCheckbox"
	_controls["PathEndArrowCheckbox"] = end_arrow_check
	end_arrow_check.connect("toggled", tool, "set_path_end_arrow")
	container.add_child(end_arrow_check)

	# Arrow head settings container (only visible when checkbox is active)
	var arrow_settings = VBoxContainer.new()
	arrow_settings.name = "PathArrowSettings"
	_controls["PathArrowSettings"] = arrow_settings
	arrow_settings.visible = tool.active_path_end_arrow

	# Head Length SpinBox
	var head_length_hbox = _create_spinbox_row("Head Length:", "PathArrowHeadLengthSpinBox",
		10.0, 200.0, 5.0, tool.active_arrow_head_length, tool, "set_path_arrow_head_length", true)
	arrow_settings.add_child(head_length_hbox)

	arrow_settings.add_child(_create_spacer(5))

	# Head Angle SpinBox
	var head_angle_hbox = _create_spinbox_row("Head Angle:", "PathArrowHeadAngleSpinBox",
		10.0, 60.0, 5.0, tool.active_arrow_head_angle, tool, "set_path_arrow_head_angle", false)
	arrow_settings.add_child(head_angle_hbox)

	container.add_child(arrow_settings)

	return container

# Create UI for Template type
func _create_template_settings_ui():
	var container = VBoxContainer.new()

	var hint = Label.new()
	hint.text = "Click a marker on the map\nto save it as a template."
	hint.autowrap = true
	container.add_child(hint)

	container.add_child(_create_spacer(8))

	_add_template_btn = Button.new()
	_add_template_btn.text = "Add Template"
	_add_template_btn.name = "AddTemplateButton"
	_controls["AddTemplateButton"] = _add_template_btn
	_add_template_btn.connect("pressed", self, "_on_add_template_pressed")
	container.add_child(_add_template_btn)

	container.add_child(_create_spacer(10))

	var list_label = Label.new()
	list_label.text = "Templates:"
	container.add_child(list_label)

	container.add_child(_create_spacer(4))

	var scroll = ScrollContainer.new()
	scroll.rect_min_size = Vector2(0, 150)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.name = "TemplateScroll"
	_controls["TemplateScroll"] = scroll

	_template_list_container = VBoxContainer.new()
	_template_list_container.name = "TemplateListContainer"
	_controls["TemplateListContainer"] = _template_list_container
	_template_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_template_list_container)

	container.add_child(scroll)

	# === OVERLAP MODE (Shape templates only) ===
	_template_overlap_modes_container = VBoxContainer.new()
	_template_overlap_modes_container.name = "TemplateOverlapModesContainer"
	_controls["TemplateOverlapModesContainer"] = _template_overlap_modes_container
	_template_overlap_modes_container.visible = false

	var sep = HSeparator.new()
	_template_overlap_modes_container.add_child(sep)
	_template_overlap_modes_container.add_child(_create_spacer(4))

	var overlap_label = Label.new()
	overlap_label.text = "Overlap Mode:"
	_template_overlap_modes_container.add_child(overlap_label)
	_template_overlap_modes_container.add_child(_create_spacer(4))

	_template_overlap_modes_container.add_child(_create_overlap_modes_row("TemplateShapeModesRow", Vector2(40, 40)))
	container.add_child(_template_overlap_modes_container)

	return container

# Rebuild the template list UI from tool.templates[]
func rebuild_template_list() -> void:
	if not _template_list_container:
		return

	# Clear existing rows
	for child in _template_list_container.get_children():
		child.queue_free()

	for i in range(tool.templates.size()):
		var tmpl = tool.templates[i]

		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var lbl = Label.new()
		lbl.text = tmpl["name"]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.clip_text = true
		row.add_child(lbl)

		var select_btn = Button.new()
		select_btn.text = "Select"
		select_btn.disabled = (tool.active_template_index == i)
		select_btn.connect("pressed", self, "_on_template_select_pressed", [i])
		row.add_child(select_btn)

		var delete_btn = Button.new()
		delete_btn.text = "Delete"
		delete_btn.connect("pressed", self, "_on_template_delete_pressed", [i])
		row.add_child(delete_btn)

		_template_list_container.add_child(row)

	# Show overlap modes panel only when the selected template is a Shape
	if _template_overlap_modes_container:
		var is_shape = false
		if tool.active_template_index >= 0 and tool.active_template_index < tool.templates.size():
			is_shape = tool.templates[tool.active_template_index]["data"].get("marker_type", "") == tool.MARKER_TYPE_SHAPE
		_template_overlap_modes_container.visible = is_shape
		if is_shape:
			_sync_template_overlap_mode_buttons()

# Update the Add Template button text/disabled state during capture mode
func _update_template_capture_button(capturing: bool) -> void:
	if not _add_template_btn:
		return
	if capturing:
		_add_template_btn.text = "Click a marker..."
		_add_template_btn.disabled = true
	else:
		_add_template_btn.text = "Add Template"
		_add_template_btn.disabled = false

# Sync the overlap mode buttons in the Template panel to the current tool state.
func _sync_template_overlap_mode_buttons() -> void:
	_sync_overlap_buttons(get_control("TemplateShapeModesRow"), _active_overlap_mode())

func _on_add_template_pressed() -> void:
	tool.start_template_capture()

func _on_template_select_pressed(index: int) -> void:
	tool.select_template(index)
	rebuild_template_list()

func _on_template_delete_pressed(index: int) -> void:
	tool.delete_template(index)

# Create common settings UI (Color picker + Map Display controls)
func _create_common_settings_ui():
	var container = VBoxContainer.new()

	var common_label = Label.new()
	common_label.text = "Common Settings:"
	common_label.align = Label.ALIGN_CENTER
	container.add_child(common_label)

	container.add_child(_create_spacer(5))

	# Color Picker
	var color_hbox = HBoxContainer.new()
	var color_label = Label.new()
	color_label.text = "Color:"
	color_label.rect_min_size = Vector2(80, 0)
	color_hbox.add_child(color_label)

	var color_picker = ColorPickerButton.new()
	color_picker.color = tool.active_color
	color_picker.name = "ColorPicker"
	_controls["ColorPicker"] = color_picker
	color_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_picker.connect("color_changed", tool, "set_color")
	color_hbox.add_child(color_picker)
	container.add_child(color_hbox)

	container.add_child(_create_spacer(10))

	# === MAP DISPLAY ===
	var display_label = Label.new()
	display_label.text = "Map Display:"
	display_label.align = Label.ALIGN_CENTER
	container.add_child(display_label)

	container.add_child(_create_spacer(5))

	# Show Markers toggle
	var visible_check = CheckButton.new()
	visible_check.text = "Show Markers"
	visible_check.pressed = tool.parent_mod.markers_visible
	visible_check.name = "MarkersVisibleCheckbox"
	_controls["MarkersVisibleCheckbox"] = visible_check
	visible_check.connect("toggled", self, "_on_markers_visible_toggled")
	container.add_child(visible_check)

	# Opacity row
	var opacity_hbox = _create_spinbox_row("Opacity (%):", "MarkersOpacitySpinBox",
		0, 100, 5, tool.parent_mod.markers_opacity * 100.0, self, "_on_markers_opacity_changed", false)
	container.add_child(opacity_hbox)

	return container

func _create_spinbox_row(label_text, control_name, minimum, maximum, step, value, target, method, allow_greater = false):
	var row = HBoxContainer.new()
	var label = Label.new()
	label.text = label_text
	label.rect_min_size = Vector2(80, 0)
	row.add_child(label)
	var spin = SpinBox.new()
	spin.name = control_name
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = value
	spin.allow_greater = allow_greater
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.connect("value_changed", target, method)
	_controls[control_name] = spin
	row.add_child(spin)
	return row

func _create_spacer(height):
	var spacer = Control.new()
	spacer.rect_min_size = Vector2(0, height)
	return spacer

# ============================================================================
# UI CALLBACKS — LINE SETTINGS
# ============================================================================

func _on_markers_visible_toggled(enabled):
	tool.parent_mod._on_markers_visible_toggled(enabled)

func _on_markers_opacity_changed(value):
	tool.parent_mod._on_markers_opacity_changed(value / 100.0)

# ============================================================================
# UI CALLBACKS — FILL MODE
# ============================================================================

func _on_delete_all_fills() -> void:
	tool.delete_all_fills()

# ============================================================================
# UI CALLBACKS — SHAPE SETTINGS
# ============================================================================

# Helper to update the pressed state of all shape mode buttons
func _update_shape_mode_buttons(active_mode: String):
	_sync_overlap_buttons(get_control("ShapeModesRow"), active_mode)

# ============================================================================
# MARKER TYPE SWITCHING
# ============================================================================

# Sync the type_selector dropdown to match tool.active_marker_type.
# Called by the tool when it changes active_marker_type externally
# (e.g. when Delete Mode forces a reset away from Fill).
func sync_type_selector_to_active_type() -> void:
	if not type_selector:
		return
	for i in range(type_selector.get_item_count()):
		if type_selector.get_item_metadata(i) == tool.active_marker_type:
			type_selector.selected = i
			_switch_type_ui(tool.active_marker_type)
			break

# Switch visible type-specific UI container
func _switch_type_ui(marker_type):
	# Hide all type-specific containers
	for child in type_specific_container.get_children():
		child.visible = false

	# Show the selected type's container
	match marker_type:
		tool.MARKER_TYPE_LINE:
			if line_settings_container:
				line_settings_container.visible = true
		tool.MARKER_TYPE_SHAPE:
			if shape_settings_container:
				shape_settings_container.visible = true
		tool.MARKER_TYPE_PATH:
			if path_settings_container:
				path_settings_container.visible = true
		tool.MARKER_TYPE_FILL:
			if fill_settings_container:
				fill_settings_container.visible = true
		tool.MARKER_TYPE_TEMPLATE:
			if template_settings_container:
				template_settings_container.visible = true

# ============================================================================
# WIDGET VALUE HELPERS
# ============================================================================

# Helper: set value on a named SpinBox inside the tool panel.
func _set_spinbox_value(node_name: String, value: float) -> void:
	_set_control_value(node_name, value, "value")

func _update_angle_spinbox():
	_set_spinbox_value("AngleSpinBox", tool.active_angle)


func _update_markers_visible_checkbox():
	_set_control_value("MarkersVisibleCheckbox", tool.parent_mod.markers_visible, "pressed")

func _update_markers_opacity_spinbox():
	_set_spinbox_value("MarkersOpacitySpinBox", tool.parent_mod.markers_opacity * 100.0)

func _update_mirror_checkbox():
	_set_control_value("MirrorCheckbox", tool.active_mirror, "pressed")

func _update_shape_radius_spinbox():
	_set_spinbox_value("ShapeRadiusSpinBox", tool.active_shape_radius)

func _update_shape_side_spinbox():
	_set_spinbox_value("ShapeSideSpinBox", tool.active_shape_side)

# Update the size mode OptionButton and show/hide Radius/Side rows accordingly.
func _update_shape_size_mode_ui():
	if not shape_settings_container:
		return
	var subtype_selector = get_control("ShapeSubtypeSelector")
	var is_circle = false
	if subtype_selector:
		var preset = subtype_selector.get_item_metadata(subtype_selector.selected)
		is_circle = (preset == tool.SHAPE_CIRCLE)
	var size_mode_row = get_control("SizeModeRow")
	var radius_row = get_control("RadiusRow")
	var side_row = get_control("SideRow")
	var mode_option   = get_control("ShapeSizeModeOption")
	if size_mode_row:
		size_mode_row.visible = not is_circle
	if radius_row:
		radius_row.visible = (is_circle or tool.active_shape_size_mode == "radius")
	if side_row:
		side_row.visible = (not is_circle and tool.active_shape_size_mode == "side")
	if mode_option:
		mode_option.set_block_signals(true)
		mode_option.selected = 0 if tool.active_shape_size_mode == "radius" else 1
		mode_option.set_block_signals(false)

func _update_shape_angle_spinbox():
	_set_spinbox_value("ShapeAngleSpinBox", tool.active_shape_angle)

func _update_shape_sides_spinbox():
	_set_spinbox_value("ShapeSidesSpinBox", tool.active_shape_sides)

func _update_path_end_arrow_checkbox():
	if not path_settings_container:
		return
	var checkbox = get_control("PathEndArrowCheckbox")
	if checkbox:
		checkbox.pressed = tool.active_path_end_arrow
	var arrow_settings = get_control("PathArrowSettings")
	if arrow_settings:
		arrow_settings.visible = tool.active_path_end_arrow

func _update_path_arrow_head_length_spinbox():
	_set_spinbox_value("PathArrowHeadLengthSpinBox", tool.active_arrow_head_length)

func _update_path_arrow_head_angle_spinbox():
	_set_spinbox_value("PathArrowHeadAngleSpinBox", tool.active_arrow_head_angle)

# Load an optional icon from the mod root; return null if unavailable.
func _load_icon(filename: String, scale: float = 1.0):
	var path = tool.parent_mod.Global.Root + "icons/" + filename
	var key = path + ":" + str(scale)
	if _icon_cache.has(key):
		return _icon_cache[key]
	var image = Image.new()
	if image.load(path) != OK:
		return null
	
	# Apply scaling if needed
	if scale != 1.0 and scale > 0.0:
		var new_width = int(image.get_width() * scale)
		var new_height = int(image.get_height() * scale)
		if new_width > 0 and new_height > 0:
			image.resize(new_width, new_height, Image.INTERPOLATE_LANCZOS)
	
	var texture = ImageTexture.new()
	texture.create_from_image(image, 0)
	_icon_cache[key] = texture
	return texture

func get_control(control_name: String):
	var control = _controls.get(control_name)
	return control if is_instance_valid(control) else null

func _set_control_value(control_name: String, value, property: String) -> void:
	var control = get_control(control_name)
	if control:
		var blocked = control.is_blocking_signals()
		control.set_block_signals(true)
		control.set(property, value)
		control.set_block_signals(blocked)

func _create_overlap_modes_row(row_name: String, button_size: Vector2):
	var modes_hbox = HBoxContainer.new()
	modes_hbox.name = row_name
	modes_hbox.alignment = BoxContainer.ALIGN_CENTER
	_controls[row_name] = modes_hbox
	var btn_defs = [
		["NormalModeButton",     "normal64.png",     "Normal Mode - place shapes without interaction"],
		["MergeModeButton",      "merge64.png",      "Merge Mode - new shape is merged (union) into any intersecting existing shapes"],
		["ConformingModeButton", "conforming64.png", "Conforming Mode - new shape dents the outlines of existing shapes"],
		["WrappingModeButton",   "wrapping64.png",   "Wrapping Mode - new shape is dented by existing shapes' outlines"],
		["DifferenceModeButton", "difference64.png", "Difference Mode - fills the overlapping area into existing shapes without placing a new shape"],
		["CutModeButton",        "cut64.png",        "Cut Mode - clips existing shapes with the new shape outline; intersected shapes become Path markers"],
	]
	var mode_keys = ["normal", "merge", "conforming", "wrapping", "difference", "cut"]

	for i in range(btn_defs.size()):
		var def = btn_defs[i]
		var btn = Button.new()
		btn.name = def[0]
		btn.toggle_mode = true
		btn.hint_tooltip = def[2]
		btn.rect_min_size = button_size
		var icon = _load_icon(def[1], 0.5)
		if icon:
			btn.icon = icon
		btn.connect("pressed", tool, "set_shape_mode", [mode_keys[i]])
		modes_hbox.add_child(btn)

	_sync_overlap_buttons(modes_hbox, _active_overlap_mode())
	return modes_hbox

func _active_overlap_mode() -> String:
	if tool.merge_shapes: return "merge"
	if tool.conforming_mode: return "conforming"
	if tool.wrapping_mode: return "wrapping"
	if tool.difference_mode: return "difference"
	if tool.cut_mode: return "cut"
	return "normal"

func _sync_overlap_buttons(row, active_mode: String) -> void:
	if not row:
		return
	var modes = ["normal", "merge", "conforming", "wrapping", "difference", "cut"]
	for index in range(row.get_child_count()):
		var button = row.get_child(index)
		button.set_block_signals(true)
		button.pressed = modes[index] == active_mode
		button.set_block_signals(false)

func sync_type_settings_controls(marker_type):
	if marker_type == tool.MARKER_TYPE_LINE:
		_update_angle_spinbox()
		_update_mirror_checkbox()

	elif marker_type == tool.MARKER_TYPE_SHAPE:
		_update_shape_radius_spinbox()
		_update_shape_angle_spinbox()
		_update_shape_sides_spinbox()
		_update_shape_side_spinbox()
		_update_shape_size_mode_ui()

	elif marker_type == tool.MARKER_TYPE_PATH:
		_update_path_end_arrow_checkbox()
		_update_path_arrow_head_length_spinbox()
		_update_path_arrow_head_angle_spinbox()

func _on_marker_type_changed(type_index):
	tool.set_marker_type(type_selector.get_item_metadata(type_index))

func _on_shape_size_mode_changed(mode_index):
	var option = get_control("ShapeSizeModeOption")
	if option:
		tool.set_shape_size_mode(option.get_item_metadata(mode_index))

func _on_shape_subtype_changed(subtype_index):
	var option = get_control("ShapeSubtypeSelector")
	if option:
		tool.set_shape_preset(option.get_item_metadata(subtype_index))

func sync_shape_preset(preset):
	var option = get_control("ShapeSubtypeSelector")
	if option:
		for index in range(option.get_item_count()):
			if option.get_item_metadata(index) == preset:
				_set_control_value("ShapeSubtypeSelector", index, "selected")
				break
	var sides_row = get_control("SidesRow")
	if sides_row:
		sides_row.visible = preset == tool.SHAPE_CUSTOM

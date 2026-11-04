extends Reference

const GeometryUtils = preload("../utils/GeometryUtils.gd")

# GuidesLinesToolUI - UI panel creation, callbacks, and widget helpers for GuidesLinesTool.
# Holds all UI node references and handles user input from the tool panel.
# Accesses and mutates tool state exclusively through the `tool` reference.

const CLASS_NAME = "GuidesLinesToolUI"


# Default values used for type-switching fallbacks
const DEFAULT_ARROW_HEAD_LENGTH = 50.0
const DEFAULT_ARROW_HEAD_ANGLE = 30.0

var _controls = {}

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
		btn.connect("pressed", self, "_on_quick_angle_pressed", [quick_angles[i]])
		quick_grid.add_child(btn)

	container.add_child(quick_grid)
	container.add_child(_create_spacer(10))

	# Angle SpinBox
	var angle_hbox = HBoxContainer.new()
	var angle_label = Label.new()
	angle_label.text = "Angle (°):"
	angle_label.rect_min_size = Vector2(80, 0)
	angle_hbox.add_child(angle_label)

	var angle_spin = SpinBox.new()
	angle_spin.min_value = 0
	angle_spin.max_value = 360
	angle_spin.step = 1
	angle_spin.value = tool.active_angle
	angle_spin.name = "AngleSpinBox"
	_controls["AngleSpinBox"] = angle_spin
	angle_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	angle_spin.connect("value_changed", self, "_on_angle_changed")
	angle_hbox.add_child(angle_spin)
	container.add_child(angle_hbox)

	# Mirror CheckBox
	var mirror_check = CheckButton.new()
	mirror_check.text = "Mirror"
	mirror_check.pressed = tool.active_mirror
	mirror_check.name = "MirrorCheckbox"
	_controls["MirrorCheckbox"] = mirror_check
	mirror_check.connect("toggled", self, "_on_mirror_toggled")
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
	var radius_hbox = HBoxContainer.new()
	radius_hbox.name = "RadiusRow"
	_controls["RadiusRow"] = radius_hbox
	var radius_label = Label.new()
	radius_label.text = "Radius:"
	radius_label.rect_min_size = Vector2(80, 0)
	radius_hbox.add_child(radius_label)

	var radius_spin = SpinBox.new()
	radius_spin.min_value = 0.1  # Minimum 0.1 cell
	radius_spin.max_value = 100
	radius_spin.step = 0.1
	radius_spin.value = tool.active_shape_radius
	radius_spin.name = "ShapeRadiusSpinBox"
	_controls["ShapeRadiusSpinBox"] = radius_spin
	radius_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	radius_spin.connect("value_changed", self, "_on_shape_radius_changed")
	radius_spin.allow_greater = true
	radius_spin.allow_lesser = false
	radius_hbox.add_child(radius_spin)
	radius_hbox.hint_tooltip = "Radius in grid cells (circumradius — distance from center to vertex)"
	container.add_child(radius_hbox)

	# Side SpinBox (shown only when Size mode = Side)
	var side_hbox = HBoxContainer.new()
	side_hbox.name = "SideRow"
	_controls["SideRow"] = side_hbox
	var side_label = Label.new()
	side_label.text = "Side:"
	side_label.rect_min_size = Vector2(80, 0)
	side_hbox.add_child(side_label)

	var side_spin = SpinBox.new()
	side_spin.min_value = 0.1
	side_spin.max_value = 100
	side_spin.step = 0.1
	side_spin.value = tool.active_shape_side
	side_spin.name = "ShapeSideSpinBox"
	_controls["ShapeSideSpinBox"] = side_spin
	side_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_spin.connect("value_changed", self, "_on_shape_side_changed")
	side_spin.allow_greater = true
	side_spin.allow_lesser = false
	side_hbox.add_child(side_spin)
	side_hbox.hint_tooltip = "Side length in grid cells — the shape is sized so its edges equal this value"
	side_hbox.visible = false
	container.add_child(side_hbox)

	container.add_child(_create_spacer(5))

	# Angle SpinBox
	var angle_hbox = HBoxContainer.new()
	var angle_label = Label.new()
	angle_label.text = "Angle (°):"
	angle_label.rect_min_size = Vector2(80, 0)
	angle_hbox.add_child(angle_label)

	var angle_spin = SpinBox.new()
	angle_spin.min_value = 0
	angle_spin.max_value = 360
	angle_spin.step = 1
	angle_spin.value = tool.active_shape_angle
	angle_spin.name = "ShapeAngleSpinBox"
	_controls["ShapeAngleSpinBox"] = angle_spin
	angle_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	angle_spin.connect("value_changed", self, "_on_shape_angle_changed")
	angle_hbox.add_child(angle_spin)
	container.add_child(angle_hbox)

	container.add_child(_create_spacer(5))

	# Sides SpinBox (only visible for Custom subtype)
	var sides_hbox = HBoxContainer.new()
	sides_hbox.name = "SidesRow"
	_controls["SidesRow"] = sides_hbox
	var sides_label = Label.new()
	sides_label.text = "Sides:"
	sides_label.rect_min_size = Vector2(80, 0)
	sides_hbox.add_child(sides_label)

	var sides_spin = SpinBox.new()
	sides_spin.min_value = 3
	sides_spin.max_value = 64
	sides_spin.step = 1
	sides_spin.value = tool.active_shape_sides
	sides_spin.name = "ShapeSidesSpinBox"
	_controls["ShapeSidesSpinBox"] = sides_spin
	sides_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sides_spin.connect("value_changed", self, "_on_shape_sides_changed")
	sides_spin.allow_greater = false
	sides_spin.allow_lesser = false
	sides_hbox.add_child(sides_spin)
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
	end_arrow_check.connect("toggled", self, "_on_path_end_arrow_toggled")
	container.add_child(end_arrow_check)

	# Arrow head settings container (only visible when checkbox is active)
	var arrow_settings = VBoxContainer.new()
	arrow_settings.name = "PathArrowSettings"
	_controls["PathArrowSettings"] = arrow_settings
	arrow_settings.visible = tool.active_path_end_arrow

	# Head Length SpinBox
	var head_length_hbox = HBoxContainer.new()
	var head_length_label = Label.new()
	head_length_label.text = "Head Length:"
	head_length_label.rect_min_size = Vector2(80, 0)
	head_length_hbox.add_child(head_length_label)

	var head_length_spin = SpinBox.new()
	head_length_spin.min_value = 10.0
	head_length_spin.max_value = 200.0
	head_length_spin.step = 5.0
	head_length_spin.value = tool.active_arrow_head_length
	head_length_spin.name = "PathArrowHeadLengthSpinBox"
	_controls["PathArrowHeadLengthSpinBox"] = head_length_spin
	head_length_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_length_spin.connect("value_changed", self, "_on_path_arrow_head_length_changed")
	head_length_spin.allow_greater = true
	head_length_spin.allow_lesser = false
	head_length_hbox.add_child(head_length_spin)
	arrow_settings.add_child(head_length_hbox)

	arrow_settings.add_child(_create_spacer(5))

	# Head Angle SpinBox
	var head_angle_hbox = HBoxContainer.new()
	var head_angle_label = Label.new()
	head_angle_label.text = "Head Angle:"
	head_angle_label.rect_min_size = Vector2(80, 0)
	head_angle_hbox.add_child(head_angle_label)

	var head_angle_spin = SpinBox.new()
	head_angle_spin.min_value = 10.0
	head_angle_spin.max_value = 60.0
	head_angle_spin.step = 5.0
	head_angle_spin.value = tool.active_arrow_head_angle
	head_angle_spin.name = "PathArrowHeadAngleSpinBox"
	_controls["PathArrowHeadAngleSpinBox"] = head_angle_spin
	head_angle_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_angle_spin.connect("value_changed", self, "_on_path_arrow_head_angle_changed")
	head_angle_hbox.add_child(head_angle_spin)
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
	color_picker.connect("color_changed", self, "_on_color_changed")
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
	var opacity_hbox = HBoxContainer.new()
	var opacity_label = Label.new()
	opacity_label.text = "Opacity (%):"
	opacity_label.rect_min_size = Vector2(80, 0)
	opacity_hbox.add_child(opacity_label)

	var opacity_spin = SpinBox.new()
	opacity_spin.min_value = 0
	opacity_spin.max_value = 100
	opacity_spin.step = 5
	opacity_spin.value = tool.parent_mod.markers_opacity * 100.0
	opacity_spin.name = "MarkersOpacitySpinBox"
	_controls["MarkersOpacitySpinBox"] = opacity_spin
	opacity_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opacity_spin.connect("value_changed", self, "_on_markers_opacity_changed")
	opacity_hbox.add_child(opacity_spin)
	container.add_child(opacity_hbox)

	return container

func _create_spacer(height):
	var spacer = Control.new()
	spacer.rect_min_size = Vector2(0, height)
	return spacer

# ============================================================================
# UI CALLBACKS — LINE SETTINGS
# ============================================================================

func _on_quick_angle_pressed(angle_value):
	tool.active_angle = angle_value
	_update_angle_spinbox()
	if tool.LOGGER:
		tool.LOGGER.debug("Quick angle set to: %.1f°" % [angle_value])

func _on_angle_changed(value):
	tool.active_angle = value
	if tool.overlay:
		tool.overlay.update()
	if tool.LOGGER:
		tool.LOGGER.debug("Angle changed to: %.1f°" % [value])

func _on_color_changed(new_color):
	tool.active_color = new_color
	if tool.overlay:
		tool.overlay.update()
	if tool.LOGGER:
		tool.LOGGER.debug("Color changed to: %s" % [new_color.to_html()])

func _on_markers_visible_toggled(enabled):
	tool.parent_mod._on_markers_visible_toggled(enabled)

func _on_markers_opacity_changed(value):
	tool.parent_mod._on_markers_opacity_changed(value / 100.0)

func _on_mirror_toggled(enabled):
	tool.active_mirror = enabled
	if tool.overlay:
		tool.overlay.update()
	if tool.LOGGER:
		tool.LOGGER.debug("Mirror toggled: %s" % [str(enabled)])

# ============================================================================
# UI CALLBACKS — FILL MODE
# ============================================================================

func _on_delete_all_fills() -> void:
	tool.delete_all_fills()

# ============================================================================
# UI CALLBACKS — SHAPE SETTINGS
# ============================================================================

# UI callback for shape preset selector.
# Selecting a preset sets the canonical starting sides and angle for that shape;
# subtype is no longer stored on the marker — only sides/angle matter.
func _on_shape_subtype_changed(subtype_index):
	if not type_selector:
		return

	var subtype_selector = get_control("ShapeSubtypeSelector")
	if subtype_selector:
		var preset = subtype_selector.get_item_metadata(subtype_index)

		# Apply canonical defaults for the selected preset
		match preset:
			tool.SHAPE_CIRCLE:
				tool.active_shape_sides = 64
				tool.active_shape_angle = 0.0
			tool.SHAPE_SQUARE:
				tool.active_shape_sides = 4
				tool.active_shape_angle = 45.0
			tool.SHAPE_PENTAGON:
				tool.active_shape_sides = 5
				tool.active_shape_angle = -90.0
			tool.SHAPE_HEXAGON:
				tool.active_shape_sides = 6
				tool.active_shape_angle = 0.0
			tool.SHAPE_OCTAGON:
				tool.active_shape_sides = 8
				tool.active_shape_angle = 0.0
			tool.SHAPE_CUSTOM:
				tool.active_shape_angle = 0.0

		tool.type_settings[tool.MARKER_TYPE_SHAPE]["angle"] = tool.active_shape_angle
		tool.type_settings[tool.MARKER_TYPE_SHAPE]["sides"] = tool.active_shape_sides

		# Show/hide sides spinbox — visible only for Custom
		var sides_row = get_control("SidesRow")
		if sides_row:
			sides_row.visible = (preset == tool.SHAPE_CUSTOM)

		# Circle has no meaningful side — force radius mode and hide the size toggle
		var is_circle = (preset == tool.SHAPE_CIRCLE)
		if is_circle and tool.active_shape_size_mode == "side":
			tool.active_shape_size_mode = "radius"
			tool.type_settings[tool.MARKER_TYPE_SHAPE]["size_mode"] = "radius"
		_update_shape_size_mode_ui()

		# In side mode with a non-circle preset, keep the user's side value and
		# recompute the circumradius for the new number of sides.
		if tool.active_shape_size_mode == "side" and not is_circle:
			tool.recompute_radius_from_side()
			_update_shape_radius_spinbox()

		_update_shape_angle_spinbox()
		_update_shape_sides_spinbox()

		if tool.overlay:
			tool.overlay.update()

		if tool.LOGGER:
			tool.LOGGER.info("Shape preset changed to: %s (sides=%d, angle=%.1f)" % [preset, tool.active_shape_sides, tool.active_shape_angle])

func _on_shape_radius_changed(value):
	if value < 0.1:
		value = 0.1
	tool.active_shape_radius = value
	_update_shape_radius_spinbox()
	if tool.overlay:
		tool.overlay.update()
	if tool.LOGGER:
		tool.LOGGER.debug("Shape radius changed to: %.1f cells" % [value])

func _on_shape_angle_changed(value):
	tool.active_shape_angle = value
	if tool.overlay:
		tool.overlay.update()
	if tool.LOGGER:
		tool.LOGGER.debug("Shape angle changed to: %.1f°" % [value])

func _on_shape_sides_changed(value):
	tool.active_shape_sides = int(value)
	tool.type_settings[tool.MARKER_TYPE_SHAPE]["sides"] = tool.active_shape_sides
	# In side mode, recompute circumradius from the kept side value with the new sides count
	if tool.active_shape_size_mode == "side":
		tool.recompute_radius_from_side()
		_update_shape_radius_spinbox()
	if tool.overlay:
		tool.overlay.update()
	if tool.LOGGER:
		tool.LOGGER.debug("Shape sides changed to: %d" % [tool.active_shape_sides])

# Called when the user toggles between Radius and Side size mode
func _on_shape_size_mode_changed(mode_index):
	if not shape_settings_container:
		return
	var size_mode_option = get_control("ShapeSizeModeOption")
	if not size_mode_option:
		return
	var mode = size_mode_option.get_item_metadata(mode_index)
	tool.active_shape_size_mode = mode
	tool.type_settings[tool.MARKER_TYPE_SHAPE]["size_mode"] = mode
	if mode == "side":
		# Compute equivalent side from the current circumradius
		var computed_side = GeometryUtils.circumradius_to_side(tool.active_shape_radius / tool._get_hex_edge_correction(), tool.active_shape_sides)
		if computed_side < 0.1:
			computed_side = 0.1
		tool.active_shape_side = computed_side
		tool.type_settings[tool.MARKER_TYPE_SHAPE]["side"] = computed_side
		_update_shape_side_spinbox()
	_update_shape_size_mode_ui()
	if tool.overlay:
		tool.overlay.update()
	if tool.LOGGER:
		tool.LOGGER.debug("Shape size mode changed to: %s" % [mode])

# Called when the user edits the Side spinbox directly
func _on_shape_side_changed(value):
	if value < 0.1:
		value = 0.1
	tool.active_shape_side = value
	tool.type_settings[tool.MARKER_TYPE_SHAPE]["side"] = value
	_update_shape_side_spinbox()
	var new_radius = tool.recompute_radius_from_side()
	_update_shape_radius_spinbox()
	if tool.overlay:
		tool.overlay.update()
	if tool.LOGGER:
		tool.LOGGER.debug("Shape side changed to: %.2f cells (radius=%.3f)" % [value, new_radius])

# Unified callback for shape interaction mode button presses
func _on_shape_mode_button_pressed(mode: String):
	# Set all modes to false first
	tool.merge_shapes = false
	tool.conforming_mode = false
	tool.wrapping_mode = false
	tool.difference_mode = false
	tool.cut_mode = false

	# Activate the selected mode (normal means all stay false)
	match mode:
		"merge":
			tool.merge_shapes = true
		"conforming":
			tool.conforming_mode = true
		"wrapping":
			tool.wrapping_mode = true
		"difference":
			tool.difference_mode = true
		"cut":
			tool.cut_mode = true
		"normal":
			pass  # All modes already false

	# Update button pressed states
	_update_shape_mode_buttons(mode)
	_sync_template_overlap_mode_buttons()

	if tool.LOGGER:
		tool.LOGGER.info("Shape interaction mode changed to: %s" % [mode])

# Helper to update the pressed state of all shape mode buttons
func _update_shape_mode_buttons(active_mode: String):
	_sync_overlap_buttons(get_control("ShapeModesRow"), active_mode)

func _on_path_end_arrow_toggled(enabled):
	tool.active_path_end_arrow = enabled
	tool.type_settings[tool.MARKER_TYPE_PATH]["end_arrow"] = enabled
	# Show/hide arrow head settings
	if path_settings_container:
		var arrow_settings = get_control("PathArrowSettings")
		if arrow_settings:
			arrow_settings.visible = enabled
	if tool.overlay:
		tool.overlay.update()
	if tool.LOGGER:
		tool.LOGGER.debug("Path end_arrow toggled: %s" % [str(enabled)])

func _on_path_arrow_head_length_changed(value):
	if value < 10.0:
		value = 10.0
	tool.active_arrow_head_length = value
	tool.type_settings[tool.MARKER_TYPE_PATH]["head_length"] = value
	_update_path_arrow_head_length_spinbox()
	if tool.overlay:
		tool.overlay.update()
	if tool.LOGGER:
		tool.LOGGER.debug("Path arrow head length changed to: %.1f px" % [value])

func _on_path_arrow_head_angle_changed(value):
	tool.active_arrow_head_angle = value
	tool.type_settings[tool.MARKER_TYPE_PATH]["head_angle"] = value
	if tool.overlay:
		tool.overlay.update()
	if tool.LOGGER:
		tool.LOGGER.debug("Path arrow head angle changed to: %.1f°" % [value])

# ============================================================================
# MARKER TYPE SWITCHING
# ============================================================================

# Handle marker type selection change
func _on_marker_type_changed(type_index):
	var selected_type = type_selector.get_item_metadata(type_index)

	# Save current type settings before switching (not applicable for Fill/Template)
	if tool.active_marker_type != tool.MARKER_TYPE_FILL and tool.active_marker_type != tool.MARKER_TYPE_TEMPLATE:
		_save_current_type_settings()

	# Cancel path placement if switching away from Path
	if tool.active_marker_type == tool.MARKER_TYPE_PATH and selected_type != tool.MARKER_TYPE_PATH:
		tool._cancel_path_placement()

	# Cancel template capture if switching away from Template
	if tool.active_marker_type == tool.MARKER_TYPE_TEMPLATE and selected_type != tool.MARKER_TYPE_TEMPLATE:
		tool.template_capture_mode = false
		_update_template_capture_button(false)

	# Switch to new type
	tool.active_marker_type = selected_type

	# Load settings for new type (not applicable for Fill/Template)
	if selected_type != tool.MARKER_TYPE_FILL and selected_type != tool.MARKER_TYPE_TEMPLATE:
		_load_type_settings(selected_type)

	# Switch visible UI container
	_switch_type_ui(selected_type)

	if tool.overlay:
		tool.overlay.update()

	if tool.LOGGER:
		tool.LOGGER.debug("Marker type changed to: %s" % [selected_type])

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

# Load settings for specific marker type
func _load_type_settings(marker_type):
	if not tool.type_settings.has(marker_type):
		return

	var settings = tool.type_settings[marker_type]

	if marker_type == tool.MARKER_TYPE_LINE:
		tool.active_angle = settings["angle"]
		tool.active_mirror = settings["mirror"]
		_update_angle_spinbox()
		_update_mirror_checkbox()

	elif marker_type == tool.MARKER_TYPE_SHAPE:
		tool.active_shape_radius = settings["radius"]
		tool.active_shape_angle = settings.get("angle", 0.0)
		tool.active_shape_sides = settings.get("sides", tool.DEFAULT_SHAPE_SIDES)
		tool.active_shape_size_mode = settings.get("size_mode", "radius")
		tool.active_shape_side = settings.get("side", 1.0)
		_update_shape_radius_spinbox()
		_update_shape_angle_spinbox()
		_update_shape_sides_spinbox()
		_update_shape_side_spinbox()
		_update_shape_size_mode_ui()

	elif marker_type == tool.MARKER_TYPE_PATH:
		tool.active_path_end_arrow = settings.get("end_arrow", false)
		tool.active_arrow_head_length = settings.get("head_length", DEFAULT_ARROW_HEAD_LENGTH)
		tool.active_arrow_head_angle = settings.get("head_angle", DEFAULT_ARROW_HEAD_ANGLE)
		_update_path_end_arrow_checkbox()
		_update_path_arrow_head_length_spinbox()
		_update_path_arrow_head_angle_spinbox()

# Save current type settings before switching
func _save_current_type_settings():
	if not tool.type_settings.has(tool.active_marker_type):
		tool.type_settings[tool.active_marker_type] = {}

	if tool.active_marker_type == tool.MARKER_TYPE_LINE:
		tool.type_settings[tool.MARKER_TYPE_LINE]["angle"] = tool.active_angle
		tool.type_settings[tool.MARKER_TYPE_LINE]["mirror"] = tool.active_mirror

	elif tool.active_marker_type == tool.MARKER_TYPE_SHAPE:
		tool.type_settings[tool.MARKER_TYPE_SHAPE]["radius"] = tool.active_shape_radius
		tool.type_settings[tool.MARKER_TYPE_SHAPE]["angle"] = tool.active_shape_angle
		tool.type_settings[tool.MARKER_TYPE_SHAPE]["sides"] = tool.active_shape_sides
		tool.type_settings[tool.MARKER_TYPE_SHAPE]["size_mode"] = tool.active_shape_size_mode
		tool.type_settings[tool.MARKER_TYPE_SHAPE]["side"] = tool.active_shape_side

	elif tool.active_marker_type == tool.MARKER_TYPE_PATH:
		tool.type_settings[tool.MARKER_TYPE_PATH]["end_arrow"] = tool.active_path_end_arrow
		tool.type_settings[tool.MARKER_TYPE_PATH]["head_length"] = tool.active_arrow_head_length
		tool.type_settings[tool.MARKER_TYPE_PATH]["head_angle"] = tool.active_arrow_head_angle

# ============================================================================
# MOUSE WHEEL PARAMETER ADJUSTMENT
# ============================================================================

# Adjust angle using mouse wheel (only for Line type)
# direction: 1 for wheel up (increase), -1 for wheel down (decrease)
func adjust_angle_with_wheel(direction):
	if tool.active_marker_type != tool.MARKER_TYPE_LINE:
		return

	var angle_step = 1.0
	var new_angle = tool.active_angle + (direction * angle_step)

	if new_angle < 0:
		new_angle += 360
	elif new_angle >= 360:
		new_angle -= 360

	tool.active_angle = new_angle
	tool.type_settings[tool.MARKER_TYPE_LINE]["angle"] = tool.active_angle
	_update_angle_spinbox()

	if tool.overlay:
		tool.overlay.update()

	if tool.LOGGER:
		tool.LOGGER.debug("Angle adjusted via mouse wheel: %.1f°" % [tool.active_angle])

# Adjust shape radius using mouse wheel (only for Shape type)
# direction: 1 for wheel up (increase), -1 for wheel down (decrease)
func adjust_shape_radius_with_wheel(direction):
	if tool.active_marker_type != tool.MARKER_TYPE_SHAPE:
		return

	if tool.active_shape_size_mode == "side":
		var side_step = 0.1
		var new_side = tool.active_shape_side + (direction * side_step)
		if new_side < 0.1:
			new_side = 0.1
		tool.active_shape_side = new_side
		tool.type_settings[tool.MARKER_TYPE_SHAPE]["side"] = new_side
		_update_shape_side_spinbox()
		var new_radius = tool.recompute_radius_from_side()
		_update_shape_radius_spinbox()
		if tool.overlay:
			tool.overlay.update()
		if tool.LOGGER:
			tool.LOGGER.debug("Shape side adjusted via mouse wheel: %.2f cells (radius=%.3f)" % [new_side, new_radius])
	else:
		var radius_step = 0.1
		var new_radius = tool.active_shape_radius + (direction * radius_step)
		if new_radius < 0.1:
			new_radius = 0.1
		tool.active_shape_radius = new_radius
		tool.type_settings[tool.MARKER_TYPE_SHAPE]["radius"] = tool.active_shape_radius
		_update_shape_radius_spinbox()
		if tool.overlay:
			tool.overlay.update()
		if tool.LOGGER:
			tool.LOGGER.debug("Shape radius adjusted via mouse wheel: %.1f cells" % [tool.active_shape_radius])

# Adjust shape angle using mouse wheel (only for Shape type)
# direction: 1 for wheel up (increase), -1 for wheel down (decrease)
func adjust_shape_angle_with_wheel(direction):
	if tool.active_marker_type != tool.MARKER_TYPE_SHAPE:
		return

	var angle_step = 5.0
	var new_angle = fmod(tool.active_shape_angle + (direction * angle_step), 360.0)
	if new_angle < 0:
		new_angle += 360.0

	tool.active_shape_angle = new_angle
	tool.type_settings[tool.MARKER_TYPE_SHAPE]["angle"] = tool.active_shape_angle
	_update_shape_angle_spinbox()

	if tool.overlay:
		tool.overlay.update()

	if tool.LOGGER:
		tool.LOGGER.debug("Shape angle adjusted via mouse wheel: %.1f°" % [tool.active_shape_angle])

# Rotate shape by 45 degrees via RMB shortcut
func rotate_shape_45():
	if tool.active_marker_type != tool.MARKER_TYPE_SHAPE:
		return

	var new_angle = fmod(tool.active_shape_angle + 45.0, 360.0)

	tool.active_shape_angle = new_angle
	tool.type_settings[tool.MARKER_TYPE_SHAPE]["angle"] = tool.active_shape_angle
	_update_shape_angle_spinbox()

	if tool.overlay:
		tool.overlay.update()

	if tool.LOGGER:
		tool.LOGGER.debug("Shape rotated 45° via RMB: %.1f°" % [tool.active_shape_angle])

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
		btn.connect("pressed", self, "_on_shape_mode_button_pressed", [mode_keys[i]])
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

# GuidesLines - Dungeondraft Mod
# Advanced guide lines system with placeable markers with multi-type support
#
# File Structure:
#   - GuidesLines.gd: Main mod file (this file)
#   - scripts/guides/GuideMarker.gd: Placeable marker data class (Line/Shape/Path)
#   - scripts/tool/GuidesLinesTool.gd: Tool for placing and managing markers
#   - scripts/tool/GuidesLinesToolUI.gd: UI panel and controls for the tool
#   - scripts/tool/GuidesLinesHistory.gd: Undo/redo history record classes
#   - scripts/tool/GuidesLinesPlacement.gd: Multi-point placement state machine
#   - scripts/overlays/MarkerOverlay.gd: Drawing and input overlay node
#   - scripts/overlays/CrossOverlay.gd: Proximity-based guide overlay
#   - scripts/overlays/PermanentOverlay.gd: Permanent guide overlay
#   - scripts/api/guides_lines_api.gd: External API for intermod communication
#   - scripts/utils/GeometryUtils.gd: Geometry helper functions
#   - scripts/render/GuidesLinesRender.gd: Rendering helper functions

var script_class = "tool"

const CLASS_NAME = "GuidesLines"

# ============================================================================
# _LIB API
# ============================================================================

var LOGGER = null  # Logger API instance

# ============================================================================
# ICON PATHS
# ============================================================================

const TOOL_ICON_PATH = "icons/guides_lines_icon.png"

# ============================================================================
# EXTERNAL CLASSES
# ============================================================================

var GuideMarkerClass = null
var FillMarkerClass = null
var GuidesLinesToolClass = null
var GuidesLinesApiClass = null
var MarkerOverlayClass = null
var CrossOverlay = null
var PermanentOverlay = null

# ============================================================================
# CONFIGURATION
# ============================================================================

# Cross guides (proximity-based) - from v1
const DETECTION_DISTANCE = 70.0
const HYSTERESIS = 30.0
const CROSS_LINE_COLOR = Color(1, 0, 0, 0.8)  # Red
const CROSS_LINE_WIDTH = 5.0

# Permanent guides - from v1
const PERM_LINE_COLOR = Color(0, 0.7, 1, 0.6)  # Blue
const PERM_LINE_WIDTH = 5.0

# ============================================================================
# STATE
# ============================================================================

# ModConfig agent (handles settings persistence via _Lib)
var mod_config = null

# Tool and UI
var guides_tool = null
var tool_panel = null
var tool_created = false  # Flag to prevent multiple creation attempts

# Proximity and permanent guide overlays (optional features)
var cross_overlay = null
var perm_overlay = null

# External API (for intermod communication)
var guides_lines_api = null

# Cached custom_snap mod reference (checked once after map load)
var cached_snappy_mod = null
var snappy_mod_checked = false

# Proximity and permanent guide settings
var cross_guides_enabled = true  # Enabled by default
var perm_vertical_enabled = false
var perm_horizontal_enabled = false
var show_coordinates_enabled = false  # Show grid coordinates

# Marker display settings (controlled via tool UI, not Preferences)
var markers_visible = true   # Show/hide all placed markers
var markers_opacity = 1.0    # Global opacity for all markers (0.0–1.0)

# Cross guides state
var cross_show_v = false
var cross_show_h = false

# ============================================================================
# LIFECYCLE
# ============================================================================

# Initialize the mod and register with systems
# Called when Dungeondraft loads the mod
func start():
	# Register with _Lib to get API access
	if Engine.has_signal("_lib_register_mod"):
		Engine.emit_signal("_lib_register_mod", self)
		
		# Initialize Logger after registration (use self.Global.API)
		if self.Global.API and self.Global.API.has("Logger"):
			LOGGER = self.Global.API.Logger.for_class(CLASS_NAME)
			
			LOGGER.info("Mod starting - version 2.4.0")
			LOGGER.debug("Registered with _Lib successfully")
			
			# Register UpdateChecker for automatic update notifications
			if self.Global.API.has("UpdateChecker"):
				LOGGER.debug("UpdateChecker available, registering...")
				var update_checker = self.Global.API.UpdateChecker
				var agent = update_checker.builder()\
					.fetcher(update_checker.github_fetcher("ChosonDev", "GuidesLines"))\
					.downloader(update_checker.github_downloader("ChosonDev", "GuidesLines"))\
					.build()
				update_checker.register(agent)
				LOGGER.debug("UpdateChecker registered for automatic updates")
			else:
				LOGGER.info("UpdateChecker not available")
			
			# Initialize mod config (settings + shortcuts persistence)
			_init_mod_config()
		else:
			print("GuidesLines: _Lib registered but Logger not available")
	else:
		print("GuidesLines: _Lib not found (API features will be unavailable)")
	
	if LOGGER:
		LOGGER.debug("Starting to load classes...")
	
	# Verify self.Global.Root exists
	if not self.Global or not self.Global.has("Root"):
		if LOGGER: LOGGER.error("self.Global.Root not available!")
		else: print("GuidesLines: ERROR - self.Global.Root not available!")
		return
	
	# Load classes (without cache flag to avoid potential issues)
	GuideMarkerClass = ResourceLoader.load(self.Global.Root + "scripts/guides/GuideMarker.gd", "GDScript", false)
	if not GuideMarkerClass:
		if LOGGER: LOGGER.error("Failed to load GuideMarker.gd")
		else: print("GuidesLines: ERROR - Failed to load GuideMarker.gd")
		return
	
	FillMarkerClass = ResourceLoader.load(self.Global.Root + "scripts/guides/FillMarker.gd", "GDScript", false)
	if not FillMarkerClass:
		if LOGGER: LOGGER.error("Failed to load FillMarker.gd")
		else: print("GuidesLines: ERROR - Failed to load FillMarker.gd")
		return
	
	GuidesLinesToolClass = ResourceLoader.load(self.Global.Root + "scripts/tool/GuidesLinesTool.gd", "GDScript", false)
	if not GuidesLinesToolClass:
		if LOGGER: LOGGER.error("Failed to load GuidesLinesTool.gd")
		else: print("GuidesLines: ERROR - Failed to load GuidesLinesTool.gd")
		return
	
	MarkerOverlayClass = ResourceLoader.load(self.Global.Root + "scripts/overlays/MarkerOverlay.gd", "GDScript", false)
	if not MarkerOverlayClass:
		if LOGGER: LOGGER.error("Failed to load MarkerOverlay.gd")
		else: print("GuidesLines: ERROR - Failed to load MarkerOverlay.gd")
		return
	
	CrossOverlay = ResourceLoader.load(self.Global.Root + "scripts/overlays/CrossOverlay.gd", "GDScript", false)
	if not CrossOverlay:
		if LOGGER: LOGGER.error("Failed to load CrossOverlay.gd")
		else: print("GuidesLines: ERROR - Failed to load CrossOverlay.gd")
		return
	
	PermanentOverlay = ResourceLoader.load(self.Global.Root + "scripts/overlays/PermanentOverlay.gd", "GDScript", false)
	if not PermanentOverlay:
		if LOGGER: LOGGER.error("Failed to load PermanentOverlay.gd")
		else: print("GuidesLines: ERROR - Failed to load PermanentOverlay.gd")
		return
	
	GuidesLinesApiClass = ResourceLoader.load(self.Global.Root + "scripts/api/guides_lines_api.gd", "GDScript", false)
	if not GuidesLinesApiClass:
		if LOGGER: LOGGER.warn("Failed to load guides_lines_api.gd — external API unavailable")
		else: print("GuidesLines: WARNING - Failed to load guides_lines_api.gd")
		# Non-fatal: continue without external API
	
	if LOGGER:
		LOGGER.debug("Classes loaded successfully")
	
	# Register external API after all classes are loaded
	_register_external_api()

# Initialize ModConfig: registers hotkeys and settings through _Lib
func _init_mod_config():
	if not (self.Global.API.has("ModConfigApi") and self.Global.API.has("InputMapApi")):
		if LOGGER:
			LOGGER.warn("ModConfigApi or InputMapApi not available — settings will not be saved")
		return
	
	var input_definitions = {
		"Activate Guide Markers Tool": ["guideslines_activate_tool", "Ctrl+G"],
		"Toggle Delete Mode":          ["guideslines_toggle_delete_mode", "Ctrl+D"],
		"Toggle Move Mode":            ["guideslines_toggle_move_mode",   "Ctrl+M"],
	}
	self.Global.API.InputMapApi.add_actions(input_definitions)
	
	var builder = self.Global.API.ModConfigApi.create_config()
	mod_config = builder\
		.shortcuts("shortcuts", input_definitions).rect_min_y(80)\
		.h_separator()\
		.v_box_container().enter()\
			.label("Guide Overlays")\
			.check_button("cross_guides_enabled", cross_guides_enabled, "Proximity Cross Guides")\
				.connect_current("loaded", self, "_on_cross_guides_toggled")\
				.connect_current("updated", self, "_on_cross_guides_toggled")\
			.check_button("perm_vertical_enabled", perm_vertical_enabled, "Permanent Vertical Center Line")\
				.connect_current("loaded", self, "_on_perm_vertical_toggled")\
				.connect_current("updated", self, "_on_perm_vertical_toggled")\
			.check_button("perm_horizontal_enabled", perm_horizontal_enabled, "Permanent Horizontal Center Line")\
				.connect_current("loaded", self, "_on_perm_horizontal_toggled")\
				.connect_current("updated", self, "_on_perm_horizontal_toggled")\
			.check_button("show_coordinates_enabled", show_coordinates_enabled, "Show Grid Coordinates")\
				.connect_current("loaded", self, "_on_perm_coordinates_toggled")\
				.connect_current("updated", self, "_on_perm_coordinates_toggled")\
		.exit()\
		.build()
	builder = null
	
	if LOGGER:
		LOGGER.info("ModConfig initialized — settings saved to user://mod_config/choson_guideslines.json")

# Register our external API so other mods can call our functions
# Called from start() after Logger and mod_config are initialized
func _register_external_api():
	if not (self.Global.API and self.Global.API.has("Logger")):
		if LOGGER:
			LOGGER.warn("Cannot register GuidesLinesApi — ApiApi not ready")
		return
	
	if not GuidesLinesApiClass:
		# Class not loaded yet — will be loaded in start() after class loading
		# This function is called twice: first from start() (early), second after
		# class loading. The second call actually creates the instance.
		return
	
	var api_logger = self.Global.API.Logger.for_class("GuidesLinesApi")
	guides_lines_api = GuidesLinesApiClass.new(self, api_logger)
	self.Global.API.register("GuidesLinesApi", guides_lines_api)
	
	if LOGGER:
		LOGGER.info("GuidesLinesApi registered and available to other mods")

# Main update loop - called every frame
# Manages tool lifecycle and updates overlays
func update(_delta):
	# Create tool when Editor is ready (only once)
	if not tool_created and Global.Editor != null and Global.Editor.Toolset != null:
		create_tool()
		tool_created = true
	
	# Hotkey to activate the Guide Markers tool
	if tool_created and Input.is_action_just_released("guideslines_activate_tool", true):
		Global.Editor.Toolset.Quickswitch("GuidesLinesTool")

	# Hotkey to toggle Delete Mode
	if tool_created and guides_tool and Input.is_action_just_released("guideslines_toggle_delete_mode", true):
		var new_state = not guides_tool.delete_mode
		guides_tool.set_delete_mode(new_state)


	# Hotkey to toggle Move Mode
	if tool_created and guides_tool and Input.is_action_just_released("guideslines_toggle_move_mode", true):
		var new_state = not guides_tool.move_mode
		guides_tool.set_move_mode(new_state)


	# Only work when map is loaded
	if Global.World == null or Global.WorldUI == null:
		return
	
	# Check for snappy_mod once after map is loaded (mods don't change after map creation)
	if not snappy_mod_checked:
		if self.Global.API and self.Global.API.has("ModRegistry"):
			var registered = self.Global.API.ModRegistry.get_registered_mods()
			# Search for custom_snap mod by unique_id
			if registered.has("Lievven.Snappy_Mod"):
				var mod_info = registered["Lievven.Snappy_Mod"]
				if mod_info.mod:
					cached_snappy_mod = mod_info.mod
					if LOGGER:
						var mod_name = mod_info.mod_meta.get("name", "Custom Snap Mod")
						var mod_version = mod_info.mod_meta.get("version", "unknown")
						LOGGER.info("Found custom_snap mod: %s v%s" % [mod_name, mod_version])
			
			if not cached_snappy_mod and LOGGER:
				LOGGER.debug("custom_snap mod not found, using vanilla grid snapping")
		
		snappy_mod_checked = true
	
	# Check if our tool is active and enable/disable accordingly
	if guides_tool:
		# Refresh cached references before checking tool state
		guides_tool.cached_world = Global.World
		guides_tool.cached_worldui = Global.WorldUI
		guides_tool.cached_camera = Global.Camera
		guides_tool.cached_snappy_mod = cached_snappy_mod
		
		# Check if tool is active by tool name
		var is_active = Global.Editor.ActiveToolName == "GuidesLinesTool"
		
		# Enable/disable based on active state
		if is_active and not guides_tool.is_enabled:
			guides_tool.Enable()
		elif not is_active and guides_tool.is_enabled:
			guides_tool.Disable()
		
		# Always call Update — overlay creation and marker drawing
		# must work even when the tool is not the active tool (e.g. API usage)
		guides_tool.Update(_delta)
	
	# Update proximity and permanent guides if enabled
	if cross_guides_enabled or perm_vertical_enabled or perm_horizontal_enabled:
		_update_proximity_and_permanent_guides(_delta)

# Update proximity and permanent guide features
# Only runs if these features are enabled in settings
func _update_proximity_and_permanent_guides(_delta):
	# Create overlays if needed
	if cross_overlay == null and cross_guides_enabled:
		create_cross_overlay()
	if perm_overlay == null and (perm_vertical_enabled or perm_horizontal_enabled):
		create_perm_overlay()
	
	# Get camera
	var camera = null
	if Global.Camera != null:
		camera = Global.Camera
	else:
		camera = find_camera(Global.World.get_parent())
	
	if camera == null:
		return
	
	# Cache world and camera in overlays
	if cross_overlay != null:
		cross_overlay.cached_world = Global.World
		cross_overlay.cached_camera = camera
	if perm_overlay != null:
		perm_overlay.cached_world = Global.World
		perm_overlay.cached_camera = camera
		perm_overlay.cached_snappy_mod = cached_snappy_mod
	
	# Update cross guides (proximity-based)
	if cross_guides_enabled and cross_overlay != null:
		update_cross_guides()
	elif cross_overlay != null:
		if cross_show_v or cross_show_h:
			cross_show_v = false
			cross_show_h = false
			cross_overlay.update()
	

# ============================================================================
# TOOL UI CALLBACKS
# ============================================================================


func _on_cross_guides_toggled(enabled):
	if cross_guides_enabled == enabled:
		return
	cross_guides_enabled = enabled
	if not enabled:
		cross_show_v = false
		cross_show_h = false
	if guides_lines_api:
		guides_lines_api.emit_signal("settings_changed", "cross_guides", enabled)

func _on_perm_vertical_toggled(enabled):
	if perm_vertical_enabled == enabled:
		return
	perm_vertical_enabled = enabled
	_on_perm_guide_changed(enabled)
	if guides_lines_api:
		guides_lines_api.emit_signal("settings_changed", "perm_vertical", enabled)

func _on_perm_horizontal_toggled(enabled):
	if perm_horizontal_enabled == enabled:
		return
	perm_horizontal_enabled = enabled
	_on_perm_guide_changed(enabled)
	if guides_lines_api:
		guides_lines_api.emit_signal("settings_changed", "perm_horizontal", enabled)

func _on_perm_coordinates_toggled(enabled):
	if show_coordinates_enabled == enabled:
		return
	show_coordinates_enabled = enabled
	_on_perm_guide_changed(enabled)
	if guides_lines_api:
		guides_lines_api.emit_signal("settings_changed", "show_coordinates", enabled)

# Create and register the guide marker tool with the host.
func create_tool():
	if LOGGER:
		LOGGER.debug("Creating Guide Markers tool")
	
	# Create tool instance
	guides_tool = GuidesLinesToolClass.new(self)
	guides_tool.GuideMarkerClass = GuideMarkerClass
	guides_tool.FillMarkerClass = FillMarkerClass
	guides_tool.MarkerOverlayClass = MarkerOverlayClass
	
	# Create ClassInstancedLogger for GuidesLinesTool
	if LOGGER:
		guides_tool.LOGGER = LOGGER.for_class("GuidesLinesTool")
	else:
		guides_tool.LOGGER = null
	
	# Cache global references
	guides_tool.cached_world = Global.World
	guides_tool.cached_worldui = Global.WorldUI
	guides_tool.cached_camera = Global.Camera
	
	# Register tool with Dungeondraft
	var icon_path = self.Global.Root + TOOL_ICON_PATH
	
	tool_panel = Global.Editor.Toolset.CreateModTool(
		self,
		"Design",  # Category
		"GuidesLinesTool",  # Unique ID
		"Guide Markers",  # Display name
		icon_path
	)
	
	if tool_panel == null:
		if LOGGER:
			LOGGER.error("Failed to create tool panel!")
		else:
			print("GuidesLines: ERROR - Failed to create tool panel!")
		return
	
	# Set tool reference
	guides_tool.tool_panel = tool_panel
	
	# Create UI for the tool
	guides_tool.create_ui_panel()
	
	if LOGGER:
		LOGGER.debug("Guide Markers tool created successfully")

# Settings changed handlers
func _on_perm_guide_changed(_enabled):
	# Update overlay when any permanent guide setting changes
	if perm_overlay:
		perm_overlay.update()

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

func find_camera(node):
	if node == null:
		return null
	if node.get_class() == "Camera2D":
		return node
	for child in node.get_children():
		var result = find_camera(child)
		if result != null:
			return result
	return null

# ============================================================================
# PROXIMITY AND PERMANENT GUIDE OVERLAYS
# ============================================================================

func create_cross_overlay():
	cross_overlay = CrossOverlay.new()
	cross_overlay.parent_mod = self
	Global.WorldUI.add_child(cross_overlay)
	cross_overlay.update()

func create_perm_overlay():

	perm_overlay = PermanentOverlay.new()
	perm_overlay.parent_mod = self
	Global.WorldUI.add_child(perm_overlay)
	perm_overlay.update()

# Update proximity-based cross guides
# Shows red lines when cursor approaches map center
func update_cross_guides():
	if not Global.WorldUI.IsInsideBounds:
		if cross_show_v or cross_show_h:
			cross_show_v = false
			cross_show_h = false
			cross_overlay.update()
		return
	
	var mp = Global.WorldUI.MousePosition
	var rect = Global.World.WorldRect
	var cx = rect.position.x + rect.size.x * 0.5
	var cy = rect.position.y + rect.size.y * 0.5
	
	var dx = abs(mp.x - cx)
	var dy = abs(mp.y - cy)
	
	var nv = false
	var nh = false
	
	if cross_show_v:
		nv = dx < (DETECTION_DISTANCE + HYSTERESIS)
	else:
		nv = dx < DETECTION_DISTANCE
	
	if cross_show_h:
		nh = dy < (DETECTION_DISTANCE + HYSTERESIS)
	else:
		nh = dy < DETECTION_DISTANCE
	
	if nv != cross_show_v or nh != cross_show_h:
		cross_show_v = nv
		cross_show_h = nh
		cross_overlay.update()


func _on_markers_visible_toggled(enabled):
	var changed = markers_visible != enabled
	markers_visible = enabled
	if guides_tool:
		guides_tool.ui._update_markers_visible_checkbox()
		if changed and guides_tool.overlay:
			guides_tool.overlay.update()
	if changed and guides_lines_api:
		guides_lines_api.emit_signal("settings_changed", "markers_visible", enabled)

func _on_markers_opacity_changed(value):
	if is_nan(value) or is_inf(value):
		return
	value = clamp(value, 0.0, 1.0)
	var changed = markers_opacity != value
	markers_opacity = value
	if guides_tool:
		guides_tool.ui._update_markers_opacity_spinbox()
		if changed:
			guides_tool._apply_opacity_to_all(value)
			if guides_tool.overlay:
				guides_tool.overlay.update()
	if changed and guides_lines_api:
		guides_lines_api.emit_signal("settings_changed", "markers_opacity", value)

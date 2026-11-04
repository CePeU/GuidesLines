extends Reference

# GuidesLinesPlacement - Multi-point placement state machine for GuidesLinesTool.
# Manages the interactive placement session for Path (N-points) type.
#
# Placement state variables remain on the tool itself so that the overlay can read
# tool.path_placement_active, tool.path_temp_points, etc. without changes.

const CLASS_NAME = "GuidesLinesPlacement"
const GuidesLinesHistory = preload("GuidesLinesHistory.gd")


var tool = null  # Reference to GuidesLinesTool

func _init(tool_ref):
	tool = tool_ref

# ============================================================================
# PATH PLACEMENT
# ============================================================================

# Handle one click during path placement (multi-point interactive session).
func handle_path_placement(pos):
	var final_pos = pos
	if tool.parent_mod.Global.Editor.IsSnapping:
		final_pos = tool.snap_position_to_grid(pos)

	# First click — start the session
	if not tool.path_placement_active:
		tool.path_placement_active = true
		tool.path_temp_points = [final_pos]
		if tool.LOGGER:
			tool.LOGGER.info("Path placement started at %s" % [str(final_pos)])
		tool.update_ui()
		return

	# Click near first point (minimum 3 points) — close the path
	var first_point = tool.path_temp_points[0]
	if final_pos.distance_to(first_point) < 30.0 and tool.path_temp_points.size() >= 3:
		var point_count = tool.path_temp_points.size()
		finalize_path_marker(true)
		if tool.LOGGER:
			tool.LOGGER.info("Path closed with %d points" % [point_count])
		return

	# Subsequent click — add point
	tool.path_temp_points.append(final_pos)
	if tool.LOGGER:
		tool.LOGGER.debug("Path point added: %s (total: %d)" % [str(final_pos), tool.path_temp_points.size()])
	tool.update_ui()

# Finalize path marker — called on RMB (open) or when path is closed.
func finalize_path_marker(closed):
	if not tool.path_placement_active or tool.path_temp_points.size() < 2:
		cancel_path_placement()
		return

	var marker_data = {
		"position": tool.path_temp_points[0],  # First point is marker position
		"marker_type": tool.MARKER_TYPE_PATH,
		"color": tool.active_color,
		"id": tool.next_id,
		"marker_points": tool.path_temp_points.duplicate(),
		"path_closed": closed,
		"path_end_arrow": tool.active_path_end_arrow,
		"arrow_head_length": tool.active_arrow_head_length,
		"arrow_head_angle": tool.active_arrow_head_angle
	}

	tool._do_place_marker(marker_data)
	tool.next_id += 1

	if tool.LOGGER:
		tool.LOGGER.debug("Adding path marker to history (id: %d)" % [marker_data["id"]])
	tool._record_history(GuidesLinesHistory.PlaceMarkerRecord.new(tool, marker_data))

	cancel_path_placement()

# Cancel path placement — ESC or marker type switched away from Path.
func cancel_path_placement():
	tool.path_placement_active = false
	tool.path_temp_points = []
	tool.path_preview_point = null
	tool.update_ui()
	if tool.overlay:
		tool.overlay.update()

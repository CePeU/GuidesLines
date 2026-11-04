extends Reference

# GuidesLinesHistory - Undo/Redo history record classes for GuidesLinesTool
#
# Usage in GuidesLinesTool:
#   const GuidesLinesHistory = preload("GuidesLinesHistory.gd")
#   _record_history(GuidesLinesHistory.PlaceMarkerRecord.new(self, marker_data, clip_snaps))

# ============================================================================
# HISTORY RECORDS FOR UNDO/REDO SUPPORT
# ============================================================================

# History record for placing a marker.
# clip_snapshots stores the primitives of every marker that was modified as a
# side-effect of this placement (conforming mode).
# undo() removes the placed marker AND restores those modified markers.
class PlaceMarkerRecord:
	var tool
	var marker_data
	# { marker_id: {"primitives": [...]} }
	var clip_snapshots = {}
	var conforming = false
	var wrapping = false

	func _init(tool_ref, data, p_clip_snapshots = {}):
		tool = tool_ref
		marker_data = data
		clip_snapshots = p_clip_snapshots
		conforming = tool.conforming_mode
		wrapping = tool.wrapping_mode
		if tool.LOGGER:
			tool.LOGGER.debug("PlaceMarkerRecord created for id: %d" % [data["id"]])

	func redo():
		if tool.LOGGER:
			tool.LOGGER.debug("PlaceMarkerRecord.redo() called for id: %d" % [marker_data["id"]])
		# Re-snapshot before redo so that the NEXT undo can restore correctly.
		if conforming and marker_data["marker_type"] == tool.MARKER_TYPE_SHAPE:
			clip_snapshots = tool._snapshot_potential_clip_targets_by_desc(
				tool._get_shape_descriptor_from_marker_data(marker_data))
		var prev_conforming = tool.conforming_mode
		var prev_wrapping = tool.wrapping_mode
		tool.conforming_mode = conforming
		tool.wrapping_mode = wrapping
		tool._do_place_marker(marker_data)
		tool.conforming_mode = prev_conforming
		tool.wrapping_mode = prev_wrapping

	func undo():
		if tool.LOGGER:
			tool.LOGGER.debug("PlaceMarkerRecord.undo() called for id: %d" % [marker_data["id"]])
		tool._undo_place_marker(marker_data["id"])
		# Restore the primitives of every marker that was clipped by this placement.
		for cid in clip_snapshots:
			if tool.markers_lookup.has(cid):
				tool.markers_lookup[cid].set_primitives(
					clip_snapshots[cid]["primitives"].duplicate(true))
		if tool.overlay:
			tool.overlay.update()

	func record_type():
		return "GuidesLines.PlaceMarker"


# History record for placing a Shape marker via the API with Conforming mode.
# Differs from PlaceMarkerRecord in that redo() re-snapshots using a stored
# shape descriptor instead of the tool's active shape parameters, and
# re-enables conforming_mode only for the duration of _do_place_marker.
class PlaceMarkerConformingRecord:
	var tool
	var marker_data
	var stored_desc      # shape descriptor of the placed shape (for redo snapshot)
	var clip_snapshots = {}

	func _init(tool_ref, data, p_desc, p_clip_snapshots = {}):
		tool = tool_ref
		marker_data = data
		stored_desc = p_desc
		clip_snapshots = p_clip_snapshots
		if tool.LOGGER:
			tool.LOGGER.debug("PlaceMarkerConformingRecord created for id: %d" % [data["id"]])

	func redo():
		if tool.LOGGER:
			tool.LOGGER.debug("PlaceMarkerConformingRecord.redo() for id: %d" % [marker_data["id"]])
		clip_snapshots = tool._snapshot_potential_clip_targets_by_desc(stored_desc)
		var prev = tool.conforming_mode
		tool.conforming_mode = true
		tool._do_place_marker(marker_data)
		tool.conforming_mode = prev

	func undo():
		if tool.LOGGER:
			tool.LOGGER.debug("PlaceMarkerConformingRecord.undo() for id: %d" % [marker_data["id"]])
		tool._undo_place_marker(marker_data["id"])
		for cid in clip_snapshots:
			if tool.markers_lookup.has(cid):
				tool.markers_lookup[cid].set_primitives(
					clip_snapshots[cid]["primitives"].duplicate(true))
		if tool.overlay:
			tool.overlay.update()

	func record_type():
		return "GuidesLines.PlaceMarkerConforming"


# History record for placing a Shape marker via the API with Wrapping mode.
# Differs from PlaceMarkerRecord in that redo() re-enables wrapping_mode only
# for the duration of _do_place_marker, regardless of the tool's current flag.
class PlaceMarkerWrappingRecord:
	var tool
	var marker_data

	func _init(tool_ref, data):
		tool = tool_ref
		marker_data = data
		if tool.LOGGER:
			tool.LOGGER.debug("PlaceMarkerWrappingRecord created for id: %d" % [data["id"]])

	func redo():
		if tool.LOGGER:
			tool.LOGGER.debug("PlaceMarkerWrappingRecord.redo() for id: %d" % [marker_data["id"]])
		var prev = tool.wrapping_mode
		tool.wrapping_mode = true
		tool._do_place_marker(marker_data)
		tool.wrapping_mode = prev

	func undo():
		if tool.LOGGER:
			tool.LOGGER.debug("PlaceMarkerWrappingRecord.undo() for id: %d" % [marker_data["id"]])
		tool._undo_place_marker(marker_data["id"])

	func record_type():
		return "GuidesLines.PlaceMarkerWrapping"


# History record for deleting a single marker.
class DeleteMarkerRecord:
	var tool
	var marker_data
	var marker_index

	func _init(tool_ref, data, index):
		tool = tool_ref
		marker_data = data
		marker_index = index
		if tool.LOGGER:
			tool.LOGGER.debug("DeleteMarkerRecord created for id: %d at index: %d" % [data["id"], index])

	func redo():
		if tool.LOGGER:
			tool.LOGGER.debug("DeleteMarkerRecord.redo() called for id: %d" % [marker_data["id"]])
		tool._do_delete_marker(marker_index)

	func undo():
		if tool.LOGGER:
			tool.LOGGER.debug("DeleteMarkerRecord.undo() called for id: %d" % [marker_data["id"]])
		tool._undo_delete_marker(marker_data, marker_index)

	func record_type():
		return "GuidesLines.DeleteMarker"


# History record for deleting all markers.
class DeleteAllMarkersRecord:
	var tool
	var saved_markers

	func _init(tool_ref, markers_data):
		tool = tool_ref
		saved_markers = markers_data

	func redo():
		tool._do_delete_all()

	func undo():
		tool._undo_delete_all(saved_markers)

	func record_type():
		return "GuidesLines.DeleteAll"


# History record for applying a Difference operation.
# Uses snapshots to undo, because there is no "diff marker" that could be removed.
class DifferenceRecord:
	var tool
	var diff_desc   # in-memory Dictionary (has Vector2 values)
	# { marker_id: {"primitives":[...]} }
	var snapshots

	func _init(tool_ref, p_desc, p_snapshots):
		tool = tool_ref
		diff_desc = p_desc
		snapshots = p_snapshots

	func redo():
		tool._do_apply_difference(diff_desc)

	func undo():
		for id in snapshots:
			if tool.markers_lookup.has(id):
				tool.markers_lookup[id].set_primitives(
					snapshots[id]["primitives"].duplicate(true))
		if tool.overlay:
			tool.overlay.update()

	func record_type():
		return "GuidesLines.Difference"


# History record for a Merge operation.
# Merge does NOT create a new marker — instead existing Shape markers that overlap
# the placed shape have their primitives and position updated.
# When multiple markers overlap, all are folded into a single primary marker and
# the rest are deleted.  absorbed_ids holds the IDs of those deleted markers.
# undo() restores the primary marker AND re-creates every absorbed marker.
# redo() re-applies _do_apply_merge() with the stored descriptor + center.
class MergeShapeRecord:
	var tool
	var merge_desc   # { shape_type, points } descriptor of the virtual new shape
	var new_pos      # Vector2 — center of the placed (virtual) shape
	# { marker_id: { "primitives": [...], "position": Vector2, "color": Color } }
	var snapshots
	# IDs of markers absorbed (deleted) during the merge — all except the primary.
	var absorbed_ids: Array

	func _init(tool_ref, p_desc, p_pos, p_snapshots, p_absorbed_ids = []):
		tool = tool_ref
		merge_desc = p_desc
		new_pos = p_pos
		snapshots = p_snapshots
		absorbed_ids = p_absorbed_ids
		if tool.LOGGER:
			tool.LOGGER.debug("MergeShapeRecord created at %s, absorbed: %s" % [
					str(p_pos), str(absorbed_ids)])

	func redo():
		if tool.LOGGER:
			tool.LOGGER.debug("MergeShapeRecord.redo() called")
		tool._do_apply_merge(merge_desc, new_pos)

	func undo():
		if tool.LOGGER:
			tool.LOGGER.debug("MergeShapeRecord.undo() — restoring %d markers, re-creating %d absorbed" % [
					snapshots.size(), absorbed_ids.size()])

		# Restore every marker that still exists (the primary survivor).
		for id in snapshots:
			if absorbed_ids.has(id):
				continue  # handled below via re-creation
			if tool.markers_lookup.has(id):
				var m = tool.markers_lookup[id]
				m.set_primitives(snapshots[id]["primitives"].duplicate(true))
				m.position = snapshots[id]["position"]

		# Re-create every marker that was absorbed (deleted) during the merge.
		for id in absorbed_ids:
			if tool.markers_lookup.has(id):
				continue  # already present (shouldn't happen)
			var snap = snapshots.get(id)
			if snap == null:
				continue
			var marker = tool.GuideMarkerClass.new()
			marker.Load(snap["saved_marker"])
			marker.color = snap["color"]
			marker.update_opacity(tool._current_opacity())
			marker.set_primitives(snap["primitives"].duplicate(true))
			tool.markers.append(marker)
			tool.markers_lookup[id] = marker
			if tool.LOGGER:
				tool.LOGGER.debug("MergeShapeRecord.undo() — restored absorbed marker id=%d" % id)

		if tool.overlay:
			tool.overlay.update()

	func record_type():
		return "GuidesLines.MergeShape"


# ============================================================================
# HISTORY RECORDS FOR FILL MODE
# ============================================================================

# History record for placing a single fill region.
# undo() removes the fill; redo() re-adds it.
class PlaceFillRecord:
	var tool
	var fill_data: Dictionary  # Serialised FillMarker (from FillMarker.Save())

	func _init(tool_ref, data: Dictionary):
		tool = tool_ref
		fill_data = data
		if tool.LOGGER:
			tool.LOGGER.debug("PlaceFillRecord created for fill id: %d" % [data["id"]])

	func redo():
		if tool.LOGGER:
			tool.LOGGER.debug("PlaceFillRecord.redo() for fill id: %d" % [fill_data["id"]])
		tool._do_place_fill(fill_data)

	func undo():
		if tool.LOGGER:
			tool.LOGGER.debug("PlaceFillRecord.undo() for fill id: %d" % [fill_data["id"]])
		tool._undo_place_fill(fill_data["id"])

	func record_type():
		return "GuidesLines.PlaceFill"


# History record for deleting all fill regions at once.
# undo() restores every previously deleted fill; redo() deletes them all again.
class DeleteAllFillsRecord:
	var tool
	var saved_fills: Array  # Array of serialised FillMarker dicts

	func _init(tool_ref, fills_data: Array):
		tool = tool_ref
		saved_fills = fills_data
		if tool.LOGGER:
			tool.LOGGER.debug("DeleteAllFillsRecord created (%d fills saved)" % [fills_data.size()])

	func redo():
		if tool.LOGGER:
			tool.LOGGER.debug("DeleteAllFillsRecord.redo() — deleting all fills")
		tool._do_delete_all_fills()

	func undo():
		if tool.LOGGER:
			tool.LOGGER.debug("DeleteAllFillsRecord.undo() — restoring %d fills" % [saved_fills.size()])
		tool._undo_delete_all_fills(saved_fills)

	func record_type():
		return "GuidesLines.DeleteAllFills"


# ============================================================================
# HISTORY RECORD FOR CUT MODE
# ============================================================================

# History record for a Cut operation.
#
# Cut clips the outline of each intersecting Shape marker against the cut shape,
# splits the remaining segments into disconnected chains, and:
#   • Converts the existing marker to a Path (first chain).
#   • Creates new Path markers for each additional chain.
#   • Deletes markers that were fully inside the cut shape.
#
# Snapshot format:
#   snapshots = { marker_id: { "primitives": Array, "color": Color, "position": Vector2 } }
# deleted_ids   — subset of snapshots.keys() that were fully deleted (not just modified).
# created_markers_data — Array of marker_data dicts for the extra Path markers created.
class CutRecord:
	var tool
	var cut_desc            # { shape_type, points } — descriptor of the virtual cut shape
	var snapshots           # { marker_id: { primitives, color, position } }
	var deleted_ids: Array  # IDs of markers deleted (fully inside cut)
	var created_markers_data: Array  # marker_data dicts for newly created Path markers

	func _init(tool_ref, p_cut_desc, p_snapshots, p_deleted_ids, p_created_data):
		tool = tool_ref
		cut_desc             = p_cut_desc
		snapshots            = p_snapshots
		deleted_ids          = p_deleted_ids
		created_markers_data = p_created_data
		if tool.LOGGER:
			tool.LOGGER.debug("CutRecord created: %d affected, %d deleted, %d extra paths" % [
					p_snapshots.size(), p_deleted_ids.size(), p_created_data.size()])

	func redo():
		if tool.LOGGER:
			tool.LOGGER.debug("CutRecord.redo() called")
		# Re-snapshot before redo so undo after redo uses fresh pre-redo state.
		snapshots = tool._take_cut_snapshot(cut_desc)
		var result = tool._do_apply_cut(cut_desc)
		deleted_ids          = result.deleted_ids
		created_markers_data = result.created_markers_data

	func undo():
		if tool.LOGGER:
			tool.LOGGER.debug("CutRecord.undo() called")
		tool._undo_cut(snapshots, deleted_ids, created_markers_data)

	func record_type():
		return "GuidesLines.Cut"


# History record for moving a marker to a new position.
class MoveMarkerRecord:
	var tool
	var marker_id: int
	var old_pos: Vector2
	var new_pos: Vector2

	func _init(tool_ref, id, from: Vector2, to: Vector2):
		tool = tool_ref
		marker_id = id
		old_pos = from
		new_pos = to
		if tool.LOGGER:
			tool.LOGGER.debug("MoveMarkerRecord created for id: %d" % [id])

	func redo():
		if tool.LOGGER:
			tool.LOGGER.debug("MoveMarkerRecord.redo() called for id: %d" % [marker_id])
		if tool.markers_lookup.has(marker_id):
			tool._do_move_marker(tool.markers_lookup[marker_id], new_pos)

	func undo():
		if tool.LOGGER:
			tool.LOGGER.debug("MoveMarkerRecord.undo() called for id: %d" % [marker_id])
		if tool.markers_lookup.has(marker_id):
			tool._do_move_marker(tool.markers_lookup[marker_id], old_pos)

	func record_type():
		return "GuidesLines.MoveMarker"

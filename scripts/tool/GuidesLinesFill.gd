extends Reference

# GuidesLinesFill - Fill mode logic for GuidesLinesTool.
#
# Click behaviour depends on how many Shape markers contain the click point:
#
#   ONE shape contains pos  →  EXCLUSIVE fill:
#     Fill = primary shape MINUS every overlapping shape that is not an outer
#     container of the primary.
#     Examples:
#       B partially overlaps A, pos in A only  →  fill A − B
#       B fully inside A,       pos in A only  →  fill A − B  (hole where B is)
#       A fully inside B,       pos in A       →  fill A as-is (B is outer container)
#
#   MULTIPLE shapes contain pos  →  INTERSECTION fill:
#     pos sits in the zone where all hit shapes overlap each other.
#     Fill = A ∩ B ∩ C … (precisely that shared region).
#     Example:
#       A, B, C partially overlap, pos in the common zone  →  fill A ∩ B ∩ C
#
# Usage:
#   const GuidesLinesFill = preload("GuidesLinesFill.gd")
#   var _fill_handler = GuidesLinesFill.new(self)
#   var fill_data = _fill_handler.handle_fill_click(world_pos)

var tool = null

func _init(tool_ref):
	tool = tool_ref

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

## Given a click at [pos] in world space, compute the FillMarker data dict.
## Returns a populated Dictionary (FillMarker.Save() format) or {} on failure.
func handle_fill_click(pos: Vector2) -> Dictionary:
	var cell_size = tool._get_grid_cell_size()
	if cell_size == null:
		if tool.LOGGER:
			tool.LOGGER.warn("GuidesLinesFill: cell_size unavailable, cannot compute fill")
		return {}

	var hit_entries = _collect_hit_markers(pos, cell_size)
	if hit_entries.empty():
		if tool.LOGGER:
			tool.LOGGER.debug("GuidesLinesFill: no Shape marker hit at %s" % str(pos))
		return {}

	var fill_poly = _compute_fill_polygon(pos, hit_entries)
	if fill_poly.empty():
		if tool.LOGGER:
			tool.LOGGER.warn("GuidesLinesFill: computed polygon is empty at %s" % str(pos))
		return {}

	var c = tool.active_color
	var fill = tool.FillMarkerClass.new()
	fill.id      = tool.next_fill_id
	fill.polygon = fill_poly
	fill.color   = Color(c.r, c.g, c.b, 0.25)
	return fill.Save()

# ============================================================================
# HIT DETECTION
# ============================================================================

## Collects all Shape markers whose current polygon contains [pos].
## Returns Array of { "marker": GuideMarker, "desc": { shape_type, points } }.
func _collect_hit_markers(pos: Vector2, cell_size) -> Array:
	var result = []
	for marker in tool.markers:
		if marker.marker_type != tool.MARKER_TYPE_SHAPE:
			continue
		var desc = tool._get_shape_descriptor(marker, cell_size)
		if desc.empty():
			continue
		var pts = desc.points
		if pts.empty():
			continue
		if Geometry.is_point_in_polygon(pos, pts):
			result.append({"marker": marker, "desc": desc})
	return result

# ============================================================================
# FILL POLYGON COMPUTATION
# ============================================================================

## Top-level dispatcher: choose fill strategy based on how many shapes contain pos.
func _compute_fill_polygon(pos: Vector2, hit_entries: Array) -> Array:
	if hit_entries.size() == 1:
		# pos is inside exactly one shape → exclusive fill (subtract overlaps)
		if tool.LOGGER:
			tool.LOGGER.debug("GuidesLinesFill: 1 hit — exclusive fill")
		return _compute_exclusive_fill(pos, hit_entries[0])
	else:
		# pos is inside the intersection zone of multiple shapes → intersection fill
		if tool.LOGGER:
			tool.LOGGER.debug("GuidesLinesFill: %d hits — intersection fill" % hit_entries.size())
		return _compute_intersection_fill(pos, hit_entries)

# ─── Branch A: EXCLUSIVE FILL ─────────────────────────────────────────────────
# pos is inside only one shape (primary). Fill = primary minus every shape that
# overlaps primary but does NOT fully contain primary.

func _compute_exclusive_fill(pos: Vector2, primary_entry: Dictionary) -> Array:
	var primary_pts = primary_entry.desc.points
	var primary_id  = primary_entry.marker.id
	var cell_size   = tool._get_grid_cell_size()

	var shapes_to_subtract = []
	for marker in tool.markers:
		if marker.marker_type != tool.MARKER_TYPE_SHAPE:
			continue
		if marker.id == primary_id:
			continue
		var desc = tool._get_shape_descriptor(marker, cell_size)
		if desc.empty():
			continue
		if not tool._shapes_overlap(primary_entry.desc, desc):
			continue
		# Outer container (primary is inside this marker) → skip, don't subtract.
		if _polygon_fully_inside(primary_pts, desc.points):
			if tool.LOGGER:
				tool.LOGGER.debug(
					"GuidesLinesFill: marker %d fully contains primary — skipping" % marker.id)
			continue
		shapes_to_subtract.append(desc.points)

	if shapes_to_subtract.empty():
		if tool.LOGGER:
			tool.LOGGER.debug("GuidesLinesFill: nothing to subtract — filling primary as-is")
		return primary_pts

	if tool.LOGGER:
		tool.LOGGER.debug(
			"GuidesLinesFill: subtracting %d shape(s) from primary" % shapes_to_subtract.size())
	return _subtract_shapes(pos, primary_pts, shapes_to_subtract)

# ─── Branch B: INTERSECTION FILL ──────────────────────────────────────────────
# pos is inside the overlap zone of all hit shapes. Fill = A ∩ B ∩ C …

func _compute_intersection_fill(pos: Vector2, hit_entries: Array) -> Array:
	var result: PoolVector2Array = PoolVector2Array(hit_entries[0].desc.points)

	for i in range(1, hit_entries.size()):
		var next_poly: PoolVector2Array = PoolVector2Array(hit_entries[i].desc.points)
		# intersect_polygons_2d returns the region common to both polygons.
		var clips = Geometry.intersect_polygons_2d(result, next_poly)
		if clips.empty():
			if tool.LOGGER:
				tool.LOGGER.debug("GuidesLinesFill: intersection empty at step %d" % i)
			return []
		# Merge results (handles any outer+hole pairs) into one polygon.
		result = _merge_clips_to_polygon(clips, pos)
		if result.empty():
			return []

	return Array(result)

## Iteratively subtract each polygon in [subtract_list] from [base_pts] using
## Geometry.clip_polygons_2d (returns the parts of base outside the subtracted shape).
## After each step the resulting polygon set (possibly outer + holes) is merged
## into a single drawable polygon via the bridge technique.
func _subtract_shapes(pos: Vector2, base_pts: Array, subtract_list: Array) -> Array:
	var result: PoolVector2Array = PoolVector2Array(base_pts)

	for sub_pts in subtract_list:
		var sub: PoolVector2Array = PoolVector2Array(sub_pts)
		# clip_polygons_2d returns the parts of `result` that lie OUTSIDE `sub`.
		# When sub is fully inside result, this returns [outer, hole_reversed].
		var clips = Geometry.clip_polygons_2d(result, sub)
		if clips.empty():
			# The entire remaining area was subtracted — nothing left to fill.
			return []
		# Merge outer polygon + any hole polygons into one drawable polygon.
		result = _merge_clips_to_polygon(clips, pos)
		if result.empty():
			return []

	return Array(result)

## Combine the array of polygons returned by clip_polygons_2d/intersect_polygons_2d
## (outer boundary + optional hole polygons) into a single polygon suitable for
## draw_colored_polygon.
##
## Strategy:
##   1. Pick the outer polygon — the one that contains [pos], or the largest.
##   2. Every other polygon whose centroid is inside the outer polygon is a hole.
##   3. Each hole is stitched into the outer polygon via a minimum-distance bridge.
##
## The resulting polygon, when filled with the even-odd rule (used by Godot 3's
## tessellator), correctly leaves the hole regions empty.
func _merge_clips_to_polygon(clips: Array, pos: Vector2) -> PoolVector2Array:
	if clips.size() == 1:
		return clips[0]

	# Identify the outer polygon (contains pos, or largest).
	var outer_idx = -1
	for i in range(clips.size()):
		if Geometry.is_point_in_polygon(pos, clips[i]):
			outer_idx = i
			break
	if outer_idx == -1:
		var max_area = -1.0
		for i in range(clips.size()):
			var a = _polygon_area(Array(clips[i]))
			if a > max_area:
				max_area = a
				outer_idx = i
	if outer_idx == -1:
		return PoolVector2Array()

	# Collect holes: polygons whose centroid lies inside the outer polygon.
	var outer_poly = Array(clips[outer_idx])
	var holes = []
	for i in range(clips.size()):
		if i == outer_idx:
			continue
		var hole = Array(clips[i])
		if hole.empty():
			continue
		var centroid = Vector2.ZERO
		for p in hole:
			centroid += p
		centroid /= hole.size()
		if Geometry.is_point_in_polygon(centroid, clips[outer_idx]):
			holes.append(hole)

	if holes.empty():
		return PoolVector2Array(outer_poly)

	# Stitch each hole into the outer polygon using the bridge technique.
	var combined = outer_poly
	for hole in holes:
		combined = _bridge_hole_into_polygon(combined, hole)

	return PoolVector2Array(combined)

## Stitch [hole_pts] into [outer_pts] via a zero-width bridge at the nearest
## vertex pair.  The resulting single polygon, when rendered with the even-odd
## fill rule, visually excludes the hole region.
##
## Clipper returns hole polygons in the opposite winding order to outer polygons,
## which is exactly what the even-odd bridge technique requires — keep as-is.
func _bridge_hole_into_polygon(outer_pts: Array, hole_pts: Array) -> Array:
	if outer_pts.empty() or hole_pts.empty():
		return outer_pts

	# Find the closest vertex pair (outer[bi] ↔ hole[bj]).
	var min_dist_sq = INF
	var bi = 0
	var bj = 0
	for i in range(outer_pts.size()):
		for j in range(hole_pts.size()):
			var d = outer_pts[i].distance_squared_to(hole_pts[j])
			if d < min_dist_sq:
				min_dist_sq = d
				bi = i
				bj = j

	# Build the bridged polygon:
	#   outer[0..bi]  →  bridge  →  hole[bj .. bj (full loop)]  →  hole[bj] (close)
	#   →  bridge back outer[bi]  →  outer[bi+1 .. end]
	# outer[bi] appears twice (departure and return), creating an invisible zero-
	# width bridge edge; the even-odd fill rule then leaves the hole region unfilled.
	var result = []
	for i in range(bi + 1):                       # outer[0 .. bi]
		result.append(outer_pts[i])
	for k in range(hole_pts.size()):              # hole[bj .. bj-1]
		result.append(hole_pts[(bj + k) % hole_pts.size()])
	result.append(hole_pts[bj])                   # close hole: return to bj
	result.append(outer_pts[bi])                  # bridge back: return to outer[bi]
	for i in range(bi + 1, outer_pts.size()):     # outer[bi+1 .. end]
		result.append(outer_pts[i])

	return result

func _polygon_fully_inside(inner: Array, outer: Array) -> bool:
	if inner.empty():
		return false
	for pt in inner:
		if not Geometry.is_point_in_polygon(pt, outer):
			return false
	return true


func _polygon_area(pts: Array) -> float:
	var n = pts.size()
	if n < 3:
		return 0.0
	var area = 0.0
	for i in range(n):
		var j = (i + 1) % n
		area += pts[i].x * pts[j].y
		area -= pts[j].x * pts[i].y
	return abs(area) * 0.5

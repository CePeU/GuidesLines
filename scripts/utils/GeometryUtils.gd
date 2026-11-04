extends Reference

class_name GeometryUtils

const TWO_PI = 6.28318530718

# Calculate vertices for a regular polygon
# center: Vector2 - Center point
# radius: float - Radius (circumradius)
# sides: int - Number of sides
# rotation_offset: float - Rotation in radians
static func calculate_polygon_vertices(center, radius, sides, rotation_offset = 0.0):
	var vertices = []
	var angle_step = TWO_PI / sides
	
	for i in range(sides):
		var angle = angle_step * i + rotation_offset
		var point = center + Vector2(cos(angle), sin(angle)) * radius
		vertices.append(point)
	
	return vertices

# Convert side length to circumradius for a regular n-gon (n >= 3).
static func side_to_circumradius(side: float, n: int) -> float:
	return side / (2.0 * sin(PI / float(n)))

# Convert circumradius to side length for a regular n-gon.
# radius: circumradius (in grid cells or any consistent unit)
# n:      number of sides (must be >= 3)
static func circumradius_to_side(radius: float, n: int) -> float:
	return radius * 2.0 * sin(PI / float(n))

## Returns the closest point on segment [a]→[b] to point [p].
static func closest_point_on_segment(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab = b - a
	var len_sq = ab.length_squared()
	if len_sq == 0.0:
		return a
	return a + ab * clamp((p - a).dot(ab) / len_sq, 0.0, 1.0)

## Returns the nearest point on an open or closed polygon outline.
static func closest_point_on_polygon_edges(p: Vector2, pts: Array, closed: bool = true) -> Vector2:
	var best_pt = pts[0]
	var best_dist_sq = INF
	var edge_count = pts.size() if closed else pts.size() - 1
	for i in range(edge_count):
		var pt = closest_point_on_segment(p, pts[i], pts[(i + 1) % pts.size()])
		var d_sq = p.distance_squared_to(pt)
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best_pt = pt
	return best_pt

## Returns the vertex in [pts] nearest to [p], or null if [pts] is empty.
static func nearest_polygon_vertex(p: Vector2, pts: Array):
	if pts.empty():
		return null
	var best_v    = pts[0]
	var best_d_sq = p.distance_squared_to(pts[0])
	for i in range(1, pts.size()):
		var d_sq = p.distance_squared_to(pts[i])
		if d_sq < best_d_sq:
			best_d_sq = d_sq
			best_v    = pts[i]
	return best_v

## Intersects an infinite line with a segment; null means parallel or a miss.
static func line_intersect_segment(lp: Vector2, ld: Vector2, a: Vector2, b: Vector2):
	var ab = b - a
	var denom = ab.x * ld.y - ab.y * ld.x
	if abs(denom) < 1e-10:
		return null
	var diff = lp - a
	var s = (diff.x * ld.y - diff.y * ld.x) / denom
	if s < -1e-6 or s > 1.0 + 1e-6:
		return null
	return a + ab * clamp(s, 0.0, 1.0)

## Clips a segment to a rectangle; returns [] on a miss.
static func clip_line_segment_to_rect(p1, p2, rect):
	var x1 = p1.x
	var y1 = p1.y
	var x2 = p2.x
	var y2 = p2.y
	
	var dx = x2 - x1
	var dy = y2 - y1
	
	var t_min = 0.0
	var t_max = 1.0
	
	# Check all four boundaries
	# p values: -dx, dx, -dy, dy
	# q values: x1 - left, right - x1, y1 - top, bottom - y1
	var p = [-dx, dx, -dy, dy]
	var q = [x1 - rect.position.x, rect.position.x + rect.size.x - x1, 
			 y1 - rect.position.y, rect.position.y + rect.size.y - y1]
	
	for i in range(4):
		if p[i] == 0:
			# Line is parallel to boundary
			if q[i] < 0:
				return [] # Outside
		else:
			var t = q[i] / p[i]
			if p[i] < 0:
				# Entering the boundary
				if t > t_max: return []
				if t > t_min: t_min = t
			else:
				# Leaving the boundary
				if t < t_min: return []
				if t < t_max: t_max = t
	
	if t_min > t_max:
		return [] # Outside
	
	return [
		Vector2(x1 + t_min * dx, y1 + t_min * dy),
		Vector2(x1 + t_max * dx, y1 + t_max * dy)
	]

# Clips a ray to a rectangle; a miss returns [origin, origin].
static func get_ray_to_rect_edge(origin, direction, rect):
	var t_min = 0.0
	var t_max = INF
	
	# Check X (vertical boundaries)
	if abs(direction.x) < 0.00001:
		if origin.x < rect.position.x or origin.x > rect.end.x:
			return [origin, origin] # Parallel and outside
	else:
		var txt1 = (rect.position.x - origin.x) / direction.x
		var txt2 = (rect.end.x - origin.x) / direction.x
		
		# t_min/max for X interval
		var t_x_min = min(txt1, txt2)
		var t_x_max = max(txt1, txt2)
		
		t_min = max(t_min, t_x_min)
		t_max = min(t_max, t_x_max)

	# Check Y (horizontal boundaries)
	if abs(direction.y) < 0.00001:
		if origin.y < rect.position.y or origin.y > rect.end.y:
			return [origin, origin] # Parallel and outside
	else:
		var tyt1 = (rect.position.y - origin.y) / direction.y
		var tyt2 = (rect.end.y - origin.y) / direction.y
		
		# t_min/max for Y interval
		var t_y_min = min(tyt1, tyt2)
		var t_y_max = max(tyt1, tyt2)
		
		t_min = max(t_min, t_y_min)
		t_max = min(t_max, t_y_max)
	
	# If t_min > t_max, the ray misses the rect completely
	if t_min > t_max:
		return [origin, origin]
	
	# Construct the segment
	# If origin is inside, we want from origin (t=0) to exit point (t_max)
	if rect.has_point(origin):
		return [origin, origin + direction * t_max]
	
	# If origin is outside and ray hits rect, theoretically we want [entry, exit]
	# But for "infinite line from origin", we might want from origin to exit?
	# The original code logic implies drawing from origin to the edge of viewport.
	# If origin is outside viewport, we usually draw from entry to exit.
	return [origin + direction * t_min, origin + direction * t_max]

# Calculate points for an arrowhead
# tip_pos: Position of the arrow tip
# direction_from: Point to determine direction from (start of arrow line)
# length: Length of the arrowhead lines
# angle_deg: Angle of the arrowhead lines relative to the shaft
static func calculate_arrowhead_points(tip_pos, direction_from, length, angle_deg):
	var direction = (tip_pos - direction_from).normalized()
	var angle_rad = deg2rad(angle_deg)
	
	var left_angle = direction.angle() + PI - angle_rad
	var right_angle = direction.angle() + PI + angle_rad
	
	var left_point = tip_pos + Vector2(cos(left_angle), sin(left_angle)) * length
	var right_point = tip_pos + Vector2(cos(right_angle), sin(right_angle)) * length
	
	return [left_point, right_point]

# Normalize angle to range [-PI, PI]
# Returns the shortest difference between two angles in radians
static func get_angle_difference(angle1, angle2):
	var diff = angle1 - angle2
	return fposmod(diff + PI, TWO_PI) - PI

# Check if a point lies on a ray (within angular threshold)
# origin: Start of the ray
# direction: Direction vector (normalized)
# point: Point to check
# threshold_rad: Maximum angular deviation in radians
static func is_point_on_ray(origin, direction, point, threshold_rad = 0.1):
	var to_point = point - origin
	if to_point.length_squared() < 0.1: return true # Point coincides with origin
	
	var angle_to_point = to_point.angle()
	var line_angle = direction.angle()
	
	var diff = abs(get_angle_difference(angle_to_point, line_angle))
	
	return diff < threshold_rad

# Convert polygon vertices into closed outline segments.
static func points_to_segs(pts: Array) -> Array:
	var segs = []
	var n = pts.size()
	for i in range(n):
		segs.append({"type": "seg", "a": pts[i], "b": pts[(i + 1) % n]})
	return segs

## Returns the intersection point of segment [a1]→[a2] with segment [b1]→[b2],
## or null if they don't intersect (includes parallel case).
static func segment_segment_intersect(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2):
	var da = a2 - a1
	var db = b2 - b1
	var denom = da.x * db.y - da.y * db.x
	if abs(denom) < 1e-10:
		return null  # Parallel
	var d = b1 - a1
	var t = (d.x * db.y - d.y * db.x) / denom
	var u = (d.x * da.y - d.y * da.x) / denom
	if t < -1e-6 or t > 1.0 + 1e-6 or u < -1e-6 or u > 1.0 + 1e-6:
		return null
	return a1 + da * clamp(t, 0.0, 1.0)

## Clip polygon edges against multiple shapes, keeping only sub-segments whose
## midpoint lies OUTSIDE ALL shapes in [b_shapes].
## Returns Array of { "type": "seg", "a": Vector2, "b": Vector2 }.
## Each b_shape must be: { "shape_type": "poly", "points": Array<Vector2> }
static func clip_polygon_against_shapes(poly_pts: Array, b_shapes: Array) -> Array:
	return _clip_segments(points_to_segs(poly_pts), b_shapes, false)

static func clip_polygon_inside_shape(poly_pts: Array, container: Dictionary) -> Array:
	return _clip_segments(points_to_segs(poly_pts), [container], true)

static func clip_primitives_against_shapes(primitives: Array, shapes: Array) -> Array:
	if shapes.empty():
		return primitives
	return _clip_segments(primitives, shapes, false)

static func _clip_segments(primitives: Array, shapes: Array, keep_inside: bool) -> Array:
	var result = []
	for prim in primitives:
		if prim.type == "seg":
			var a = prim.a
			var b = prim.b
			var edge = b - a
			var edge_len_sq = edge.length_squared()
			if edge_len_sq < 1e-10:
				continue
			var ts = [0.0, 1.0]
			for shape in shapes:
				if shape.shape_type == "poly":
					var pts = shape.points
					var m = pts.size()
					for j in range(m):
						var pt = segment_segment_intersect(a, b, pts[j], pts[(j + 1) % m])
						if pt != null:
							ts.append(clamp((pt - a).dot(edge) / edge_len_sq, 0.0, 1.0))
			ts.sort()
			for k in range(ts.size() - 1):
				if ts[k + 1] - ts[k] < 1e-6:
					continue
				var mid = a + edge * ((ts[k] + ts[k + 1]) * 0.5)
				var outside = true
				for shape in shapes:
					if shape.shape_type == "poly" and Geometry.is_point_in_polygon(mid, shape.points):
						outside = false
						break
				if outside != keep_inside:
					result.append({"type": "seg", "a": a + edge * ts[k], "b": a + edge * ts[k + 1]})
	return result

static func merge_polygons_outline(pts_a: Array, pts_b: Array) -> Array:
	if pts_a.empty() or pts_b.empty():
		return []

	var shape_a = {"shape_type": "poly", "points": pts_a}
	var shape_b = {"shape_type": "poly", "points": pts_b}

	# Check whether the outlines actually cross each other.
	var edges_intersect = false
	var na = pts_a.size()
	var nb = pts_b.size()
	for i in range(na):
		for j in range(nb):
			if segment_segment_intersect(pts_a[i], pts_a[(i + 1) % na],
										 pts_b[j], pts_b[(j + 1) % nb]) != null:
				edges_intersect = true
				break
		if edges_intersect:
			break

	if not edges_intersect:
		# Check containment using a single representative vertex from each polygon.
		var a_in_b = Geometry.is_point_in_polygon(pts_a[0], pts_b)
		var b_in_a = Geometry.is_point_in_polygon(pts_b[0], pts_a)
		if a_in_b:
			return points_to_segs(pts_b)  # A absorbed by B → keep B outline
		if b_in_a:
			return points_to_segs(pts_a)  # B absorbed by A → keep A outline
		# Completely separate shapes — no merge.
		return []

	# Normal intersection: keep the outer ring of each polygon.
	var segs_a = clip_polygon_against_shapes(pts_a, [shape_b])
	var segs_b = clip_polygon_against_shapes(pts_b, [shape_a])

	# ── Pass 1: de-duplicate reverse-direction boundary segments ─────────────
	# When two polygon edges are collinear and Godot 3's is_point_in_polygon()
	# returns FALSE for boundary-midpoints, both copies of the shared-boundary
	# segment survive clip — but in opposite directions — causing chain_segments
	# to dead-end.  Remove from segs_b every segment whose reverse is in segs_a.
	var eps_sq = 0.25  # (0.5 px)²
	var deduped_b = []
	for sb in segs_b:
		var dup = false
		for sa in segs_a:
			if sa.a.distance_squared_to(sb.b) < eps_sq and \
					sa.b.distance_squared_to(sb.a) < eps_sq:
				dup = true
				break
		if not dup:
			deduped_b.append(sb)

	var all_segs = segs_a + deduped_b

	# ── Pass 2: bridge gaps caused by collinear shared boundaries ────────────
	# When two polygon edges are collinear and is_point_in_polygon() returns
	# TRUE for boundary-midpoints (the usual Godot 3 behaviour), BOTH copies of
	# the connector segment along the shared boundary are dropped.  The result
	# is an open-ended segment set that chain_segments_to_polygon cannot close.
	#
	# Detection: in a valid closed-polygon edge-set each vertex appears as a
	# segment-endpoint an even number of times.  Vertices with an odd count are
	# "open ends" that lost their partner connector.  We greedily pair them by
	# nearest distance and add a synthetic bridge segment for each pair.
	#
	# Example: two axis-aligned squares whose top boundaries share the same Y.
	#   seg[0]  (10365, 4093) → (9981, 4093)   ← B-top right portion
	#   seg[3]  (9858, 4093)  → (9474, 4093)   ← A-top left portion
	# Open ends: (9981, 4093) and (9858, 4093) — bridged to close the top.
	var EPS_VERTEX = 0.5  # matches chain_segments_to_polygon tolerance
	var pts_list  = []      # unique endpoint positions
	var valence   = []      # how many seg-ends touch each unique point
	for seg in all_segs:
		for pt in [seg.a, seg.b]:
			var found = -1
			for idx in range(pts_list.size()):
				if pts_list[idx].distance_squared_to(pt) < EPS_VERTEX * EPS_VERTEX:
					found = idx
					break
			if found == -1:
				pts_list.append(pt)
				valence.append(1)
			else:
				valence[found] += 1

	var open_ends = []
	for idx in range(pts_list.size()):
		if valence[idx] % 2 == 1:
			open_ends.append(pts_list[idx])

	if not open_ends.empty():
		var remaining = open_ends.duplicate()
		while remaining.size() >= 2:
			# Find the closest pair.
			var best_i = 0
			var best_j = 1
			var best_d = remaining[0].distance_squared_to(remaining[1])
			for ii in range(remaining.size()):
				for jj in range(ii + 1, remaining.size()):
					var d = remaining[ii].distance_squared_to(remaining[jj])
					if d < best_d:
						best_d = d
						best_i = ii
						best_j = jj
			all_segs.append({"type": "seg", "a": remaining[best_i], "b": remaining[best_j]})
			var hi = max(best_i, best_j)
			var lo = min(best_i, best_j)
			remaining.remove(hi)
			remaining.remove(lo)

	return all_segs

## Chain a flat list of {type:"seg", a:V2, b:V2} segments into a single ordered
## polygon vertex array.  Endpoints are matched within [eps] tolerance.
## Handles figure-8 / tangent unions where two closed loops share exactly one
## vertex: after the primary loop is closed, any unused edges that reconnect to
## a vertex already in [poly] are inserted as an in-and-out detour at that
## junction, producing a self-touching outline that draws both shapes.
## Returns Array[Vector2] suitable for draw_polyline() / points_to_segs(),
## or an empty array if the input is empty.
static func chain_segments_to_polygon(segs: Array, eps: float = 0.5) -> Array:
	var eps_sq = max(eps, 0.0) * max(eps, 0.0)
	# ponytail: greedy chaining remains O(E²); use endpoint buckets if profiling warrants it.
	if segs.empty():
		return []

	# Copy segment endpoints into a mutable list of [a, b, used] triplets.
	var edges = []
	for s in segs:
		if s.get("type", "") == "seg":
			edges.append({"a": s.a, "b": s.b, "used": false})
	if edges.empty():
		return []

	# Start the chain from the first edge.
	var poly = [edges[0].a, edges[0].b]
	edges[0].used = true

	var max_iter = edges.size() + 2
	for _i in range(max_iter):
		var tail = poly[poly.size() - 1]
		var found = -1
		var rev = false
		for i in range(edges.size()):
			if edges[i].used:
				continue
			if tail.distance_squared_to(edges[i].a) < eps_sq:
				found = i; rev = false; break
			if tail.distance_squared_to(edges[i].b) < eps_sq:
				found = i; rev = true; break
		if found == -1:
			break
		edges[found].used = true
		poly.append(edges[found].b if not rev else edges[found].a)

	# Drop the closing duplicate if the last point coincides with the first.
	if poly.size() > 1 and poly[0].distance_squared_to(poly[poly.size() - 1]) < eps_sq:
		poly.pop_back()

	# ── Figure-8 / tangent-touch continuation ───────────────────────────────
	# If unused edges remain (e.g. the second circle of a tangent pair), find
	# any vertex in poly that serves as a bridge to those edges and insert the
	# sub-chain as a detour: [..., T, <sub-loop>, T, ...].
	# This preserves the outline of both shapes in one continuous path.
	var any_unused = false
	for e in edges:
		if not e.used:
			any_unused = true
			break

	if any_unused:
		# Find poly vertex that connects to an unused edge (the tangent point).
		var bridge_poly_idx = -1
		var bridge_edge_idx = -1
		var bridge_rev      = false
		for pi in range(poly.size()):
			var pv = poly[pi]
			for ei in range(edges.size()):
				if edges[ei].used:
					continue
				if pv.distance_squared_to(edges[ei].a) < eps_sq:
					bridge_poly_idx = pi; bridge_edge_idx = ei; bridge_rev = false
					break
				if pv.distance_squared_to(edges[ei].b) < eps_sq:
					bridge_poly_idx = pi; bridge_edge_idx = ei; bridge_rev = true
					break
			if bridge_poly_idx != -1:
				break

		if bridge_poly_idx != -1:
			var bridge_pt = poly[bridge_poly_idx]
			# Trace the sub-loop back to bridge_pt.
			var sub = []
			edges[bridge_edge_idx].used = true
			sub.append(edges[bridge_edge_idx].b if not bridge_rev else edges[bridge_edge_idx].a)
			for _j in range(edges.size()):
				var stail = sub[sub.size() - 1]
				if stail.distance_squared_to(bridge_pt) < eps_sq:
					break  # sub-loop closed
				var sf = -1
				var sr = false
				for ei in range(edges.size()):
					if edges[ei].used:
						continue
					if stail.distance_squared_to(edges[ei].a) < eps_sq:
						sf = ei; sr = false; break
					if stail.distance_squared_to(edges[ei].b) < eps_sq:
						sf = ei; sr = true; break
				if sf == -1:
					break
				edges[sf].used = true
				sub.append(edges[sf].b if not sr else edges[sf].a)
			# Remove closing duplicate of bridge_pt at the end of sub.
			if sub.size() > 0 and sub[sub.size() - 1].distance_squared_to(bridge_pt) < eps_sq:
				sub.pop_back()
			# Insert: bridge_pt is already at bridge_poly_idx;
			# splice in [sub..., bridge_pt] right after it.
			sub.append(bridge_pt)
			var insert_idx = bridge_poly_idx + 1
			for k in range(sub.size()):
				poly.insert(insert_idx + k, sub[k])

	return poly

## Split a flat segment list into one or more disconnected open chains.
## Unlike chain_segments_to_polygon (which produces a single closed polygon),
## this function extracts every independent connected run of segments and
## returns them as separate Array[Vector2] polylines.
##
## Used by the Cut mode: after clipping a Shape's primitives against the cut
## shape, the remaining segments may form several disconnected runs — each run
## becomes its own Path marker.
##
## Returns Array of Array[Vector2].  Each inner array has >= 2 points.
## Closing duplicates (first == last within eps) are removed from each chain.
static func split_segments_into_chains(segs: Array, eps: float = 0.5) -> Array:
	var eps_sq = max(eps, 0.0) * max(eps, 0.0)
	# ponytail: greedy chaining remains O(E²); use endpoint buckets if profiling warrants it.
	if segs.empty():
		return []

	# Build a mutable list of {a, b, used} from the input segment list.
	var edges = []
	for s in segs:
		if s.get("type", "") == "seg":
			edges.append({"a": s.a, "b": s.b, "used": false})
	if edges.empty():
		return []

	var chains = []

	# Repeat until every edge has been consumed.
	for _outer in range(edges.size()):
		# Find the first unused edge to start a new chain.
		var start_idx = -1
		for i in range(edges.size()):
			if not edges[i].used:
				start_idx = i
				break
		if start_idx == -1:
			break  # All edges consumed.

		edges[start_idx].used = true
		var chain = [edges[start_idx].a, edges[start_idx].b]

		# Greedily extend the chain FORWARD by finding the next connected edge.
		for _inner in range(edges.size()):
			var tail = chain[chain.size() - 1]
			var found = -1
			var rev   = false
			for i in range(edges.size()):
				if edges[i].used:
					continue
				if tail.distance_squared_to(edges[i].a) < eps_sq:
					found = i; rev = false; break
				if tail.distance_squared_to(edges[i].b) < eps_sq:
					found = i; rev = true;  break
			if found == -1:
				break  # No continuation — chain ends here.
			edges[found].used = true
			chain.append(edges[found].b if not rev else edges[found].a)

		# Greedily extend the chain BACKWARD (prepend) to handle arcs that
		# wrap around the segment-array boundary.  Without this step, a single
		# arc stored as [..., V62, V63, V0, V1, ...] would be split in two
		# because greedy-forward starts at V0 and cannot reach back to V63.
		#
		# rev=false: edge.b == head  →  the edge A→B naturally arrives at head;
		#             prepend A (new head).
		# rev=true:  edge.a == head  →  the edge A→B starts at head (reversed
		#             usage); prepend B (new head).
		for _inner in range(edges.size()):
			var head = chain[0]
			var found = -1
			var rev   = false
			for i in range(edges.size()):
				if edges[i].used:
					continue
				if head.distance_squared_to(edges[i].b) < eps_sq:
					found = i; rev = false; break  # edge.b == head → prepend edge.a
				if head.distance_squared_to(edges[i].a) < eps_sq:
					found = i; rev = true;  break  # edge.a == head → prepend edge.b
			if found == -1:
				break  # No extension backward — head is a true open end.
			edges[found].used = true
			chain.insert(0, edges[found].a if not rev else edges[found].b)

		# Remove closing duplicate (chain loops back to its own start).
		if chain.size() > 1 and chain[0].distance_squared_to(chain[chain.size() - 1]) < eps_sq:
			chain.pop_back()

		if chain.size() >= 2:
			chains.append(chain)

	return chains

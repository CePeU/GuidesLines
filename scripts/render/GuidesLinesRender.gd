extends Reference

class_name GuidesLinesRender

# ============================================================================
# CONSTANTS & STYLING
# ============================================================================

const OUTLINE_COLOR = Color(0, 0, 0, 0.8)
const TEXT_SCALE = 4.0 # For high-res text scaling

# ============================================================================
# DRAWING PRIMITIVES
# ============================================================================

# Calculates adaptive line width based on camera zoom
static func get_adaptive_width(base_width: float, time_scale: Vector2) -> float:
	var width = base_width
	var zoom_factor = time_scale.x
	
	# Apply scaling for small zoom levels (zoomed out)
	if zoom_factor > 1.0:
		# Linear scaling: width increases proportionally to zoom
		width = base_width * zoom_factor
	
	if width < 1.0: 
		width = 1.0 # Minimum 1px
		
	return width

# Draws a line with adaptive width
static func draw_adaptive_line(canvas: CanvasItem, start: Vector2, end: Vector2, color: Color, base_width: float, time_scale: Vector2):
	var width = get_adaptive_width(base_width, time_scale)
	canvas.draw_line(start, end, color, width)

# Draws text with a black outline
static func draw_text_with_outline(canvas: CanvasItem, text: String, position: Vector2, color: Color, font: Font = null):
	if font == null:
		return
	canvas.draw_set_transform(position, 0, Vector2(TEXT_SCALE, TEXT_SCALE))
	var offset_step = 2.0 / TEXT_SCALE
	for dx in [-offset_step, 0.0, offset_step]:
		for dy in [-offset_step, 0.0, offset_step]:
			if dx != 0.0 or dy != 0.0:
				canvas.draw_string(font, Vector2(dx, dy), text, OUTLINE_COLOR, -1)
	canvas.draw_string(font, Vector2.ZERO, text, color, -1)
	canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

static func draw_arrow(canvas: CanvasItem, start: Vector2, end: Vector2, head_points: Array, color: Color, width: float):
	canvas.draw_line(start, end, color, width)
	if head_points.size() >= 2:
		canvas.draw_line(end, head_points[0], color, width)
		canvas.draw_line(end, head_points[1], color, width)

# Draws a polygon outline
static func draw_polygon_outline(canvas: CanvasItem, vertices: Array, color: Color, width: float):
	if vertices.size() < 2:
		return
		
	for i in range(vertices.size()):
		var p1 = vertices[i]
		var p2 = vertices[(i + 1) % vertices.size()]
		canvas.draw_line(p1, p2, color, width)

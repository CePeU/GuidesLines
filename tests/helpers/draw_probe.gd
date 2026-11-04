extends Node2D

# Records original render commands without requiring a Dungeondraft viewport.
var lines = []
var circles = []
var arcs = []
var strings = []
var transforms = []
var draw_transform = Transform2D.IDENTITY
var redraws = 0
var viewport_rect = Rect2(0, 0, 800, 600)
var custom_snap_enabled = true
var snap_interval = Vector2(10, 10)
var snap_offset = Vector2.ZERO
var active_geometry = 0
var radial_mode_to_corner = true

func update():
	redraws += 1

func get_viewport_rect():
	return viewport_rect

func get_snapped_position(point):
	return ((point - snap_offset) / snap_interval).snapped(Vector2.ONE) * snap_interval + snap_offset

func draw_set_transform(offset, rotation = 0.0, scale = Vector2.ONE):
	draw_transform = Transform2D(rotation, offset).scaled(scale)
	# CanvasItem scales local coordinates, not the translation itself.
	draw_transform.origin = offset
	transforms.append(draw_transform)

func draw_line(from, to, color, width = 1.0, _antialiased = false):
	lines.append({"a": from, "b": to, "color": color, "width": width})

func draw_circle(pos, radius, color):
	circles.append({"pos": pos, "radius": radius, "color": color})

func draw_arc(pos, radius, _start, _end, _count, color, width = 1.0, _antialiased = false):
	arcs.append({"pos": pos, "radius": radius, "color": color, "width": width})

func draw_string(_font: Font, pos: Vector2, text: String, color: Color = Color(1, 1, 1, 1), _clip: int = -1) -> void:
	strings.append({"pos": draw_transform.xform(pos), "text": text, "color": color})

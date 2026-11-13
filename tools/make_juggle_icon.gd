extends SceneTree
## Draws the Juggling menu icon -- a tennis ball, a bowling pin and a flaming
## sword (one for each act) flying round a dotted juggling arc -- and saves it to
## res://art/juggling/icon.png. A stand-in until there's a drawn icon: replace
## that PNG with your own and the menu uses it.
##
## Run (needs a window, not --headless):
##   ../Godot_v4.6.1-stable_win64_console.exe --path . -s tools/make_juggle_icon.gd

const SIZE := 256
const OUT := "res://art/juggling/icon.png"
const INK := Color(0.2, 0.14, 0.12)
const W := 7.0   ## outline width


class Icon extends Node2D:
	func _draw() -> void:
		var c := Vector2(128, 168)
		# the juggling arc
		for i in 15:
			var a := lerpf(PI * 1.12, PI * 1.88, i / 14.0)
			draw_circle(c + Vector2(cos(a) * 92, sin(a) * 86), 4.5, Color(INK, 0.35))
		_sword(Vector2(70, 150), -0.45)
		_pin(Vector2(128, 92), 0.35)
		_ball(Vector2(196, 154))

	func _ball(p: Vector2) -> void:
		draw_circle(p, 31 + W, INK)
		draw_circle(p, 31, Color(0.82, 0.92, 0.2))
		# the white seam curves
		draw_arc(p + Vector2(-34, 0), 26, -1.0, 1.0, 20, Color(1, 1, 0.92), 5.0, true)
		draw_arc(p + Vector2(34, 0), 26, PI - 1.0, PI + 1.0, 20, Color(1, 1, 0.92), 5.0, true)
		draw_circle(p + Vector2(-11, -12), 6, Color(1, 1, 0.8, 0.6))

	func _pin(p: Vector2, rot: float) -> void:
		draw_set_transform(p, rot)
		# body: a bulb at the bottom, a thin neck, a small head
		var pts := PackedVector2Array()
		var prof := [[-58, 9], [-50, 13], [-38, 9], [-24, 8], [-6, 18], [14, 25], [34, 22], [50, 13], [56, 0]]
		for q in prof:
			pts.append(Vector2(q[1], q[0]))
		for i in range(prof.size() - 1, -1, -1):
			pts.append(Vector2(-prof[i][1], prof[i][0]))
		_outlined(pts, Color(0.97, 0.95, 0.9))
		# red stripes on the neck
		draw_rect(Rect2(-9, -30, 18, 6), Color(0.85, 0.2, 0.15))
		draw_rect(Rect2(-8.5, -20, 17, 5), Color(0.85, 0.2, 0.15))
		draw_set_transform(Vector2.ZERO)

	func _sword(p: Vector2, rot: float) -> void:
		draw_set_transform(p, rot)
		# flames along the blade
		for f in [[Vector2(0, -34), 22.0, Color(0.95, 0.35, 0.1)], [Vector2(0, -30), 15.0, Color(1, 0.7, 0.15)], [Vector2(0, -27), 8.0, Color(1, 0.95, 0.55)]]:
			var flame := PackedVector2Array()
			var base: Vector2 = f[0]
			var r: float = f[1]
			for i in 25:
				var a := TAU * i / 24.0
				var k := 1.0 + 0.9 * maxf(0.0, -sin(a)) + 0.25 * sin(a * 5.0) * maxf(0.0, -sin(a))
				flame.append(base + Vector2(cos(a) * r * 0.75, sin(a) * r * 1.6 * k))
			draw_colored_polygon(flame, f[2])
		# blade
		var blade := PackedVector2Array([Vector2(-7, 18), Vector2(-7, -50), Vector2(0, -64), Vector2(7, -50), Vector2(7, 18)])
		_outlined(blade, Color(0.82, 0.86, 0.9))
		# cross-guard and grip
		_outlined(PackedVector2Array([Vector2(-22, 18), Vector2(22, 18), Vector2(22, 27), Vector2(-22, 27)]), Color(0.75, 0.55, 0.2))
		_outlined(PackedVector2Array([Vector2(-6, 27), Vector2(6, 27), Vector2(6, 50), Vector2(-6, 50)]), Color(0.45, 0.28, 0.18))
		draw_circle(Vector2(0, 54), 8, INK)
		draw_circle(Vector2(0, 54), 5, Color(0.75, 0.55, 0.2))
		draw_set_transform(Vector2.ZERO)

	func _outlined(pts: PackedVector2Array, fill: Color) -> void:
		draw_colored_polygon(pts, fill)
		var loop := pts.duplicate()
		loop.append(pts[0])
		draw_polyline(loop, INK, W, true)
		for q in pts:
			draw_circle(q, W / 2.0, INK)


var _vp: SubViewport
var _frames := 0


func _initialize() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.transparent_bg = true
	_vp.msaa_2d = Viewport.MSAA_8X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.add_child(Icon.new())
	root.add_child(_vp)


func _process(_dt: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false
	var img := _vp.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT))
	print("saved ", OUT)
	return true

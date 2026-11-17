extends Node
var g
var shots := [29.3, 30.0, 31.6, 32.3, 32.8, 33.3]
var started := false
func _ready() -> void:
	g = load("res://Grill.tscn").instantiate()
	add_child(g)
func _input(_e: InputEvent) -> void:
	get_viewport().set_input_as_handled()
func _process(_d: float) -> void:
	if not started:
		started = true
		g._start_song()
		return
	var b: float = Conductor.song_position / Conductor.seconds_per_beat
	if not g._answers.is_empty() and absf(Conductor.timing_error(g._answers[0]["beat"])) < 0.01:
		g._press()
	if not shots.is_empty() and b >= shots[0]:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.get_region(Rect2i(0, 0, 640, 480)).save_png("user://crit_%.2f.png" % shots[0])
		shots.pop_front()
		if shots.is_empty():
			var sheet := Image.create(640 * 3, 480 * 2, false, Image.FORMAT_RGBA8)
			var i := 0
			for n in [29.3, 30.0, 31.6, 32.3, 32.8, 33.3]:
				var im := Image.load_from_file(OS.get_user_data_dir() + "/crit_%.2f.png" % n)
				im.convert(Image.FORMAT_RGBA8)
				sheet.blit_rect(im, Rect2i(0, 0, 640, 480), Vector2i((i % 3) * 640, (i / 3) * 480))
				i += 1
			sheet.save_png("user://sheet.png")
			get_tree().quit()

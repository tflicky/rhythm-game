extends CanvasLayer
## Fade to black, switch scene, fade back in. An autoload ("Transition"), so it
## survives the scene change.
##   Transition.go("res://Grill.tscn")

const OUT_S := 0.3      ## fading to black
const HOLD_S := 0.1     ## black, while the new scene loads
const IN_S := 0.45      ## fading back in

var _black: ColorRect
var _busy := false


func _ready() -> void:
	layer = 100                        # over everything, the pause menu included
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 0)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)


func go(scene: String) -> void:
	if _busy:
		return
	_busy = true
	_black.mouse_filter = Control.MOUSE_FILTER_STOP   # no clicks while fading
	var t := create_tween()
	t.tween_property(_black, "color:a", 1.0, OUT_S)
	await t.finished
	get_tree().change_scene_to_file(scene)
	await get_tree().create_timer(HOLD_S).timeout
	t = create_tween()
	t.tween_property(_black, "color:a", 0.0, IN_S)
	await t.finished
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false

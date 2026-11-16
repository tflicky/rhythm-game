class_name Settings
## Per-computer player settings, saved in user:// (not in the project), so each
## machine keeps its own timing calibration.

const PATH := "user://settings.cfg"

## Set once the first-launch calibration has been offered this session, so
## skipping it (Esc) doesn't bounce the player straight back to it.
static var calibration_offered := false


## Measured input + audio delay for this computer, in seconds; `fallback` if
## the player has never calibrated.
static func input_offset(fallback: float = 0.0) -> float:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return fallback
	return float(cfg.get_value("timing", "input_offset", fallback))


static func has_input_offset() -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(PATH) == OK and cfg.has_section_key("timing", "input_offset")


static func set_input_offset(seconds: float) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)   # keep any other keys; a missing file is fine
	cfg.set_value("timing", "input_offset", seconds)
	cfg.save(PATH)


## Levels you've finished with 100% (every press landed), by scene path --
## the menu gives each one a gold star.
static func is_perfect(scene: String) -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(PATH) == OK and bool(cfg.get_value("perfect", scene, false))


static func set_perfect(scene: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)   # keep any other keys; a missing file is fine
	cfg.set_value("perfect", scene, true)
	cfg.save(PATH)

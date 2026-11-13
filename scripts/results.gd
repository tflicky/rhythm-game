class_name Results
## Shared by every level's results screen: no points, just how many you got out
## of how many there were, and that as a percent in a colour that goes from red
## (0%) through a reddish yellow (50%) to green (100%).

const RED := Color(0.9, 0.15, 0.1)
const MID := Color(0.95, 0.6, 0.1)
const GREEN := Color(0.25, 0.8, 0.3)


## 0..100, rounded. 0 when there was nothing to get.
static func percent(got: int, total: int) -> int:
	return roundi(100.0 * got / total) if total > 0 else 0


## The percent's colour, `k` = 0..1.
static func pct_color(k: float) -> Color:
	k = clampf(k, 0.0, 1.0)
	return RED.lerp(MID, k * 2.0) if k < 0.5 else MID.lerp(GREEN, (k - 0.5) * 2.0)


## "You got X / Y" and the big coloured percent under it. `pos` is the left end
## of the "You got" baseline, or its middle when `centred`. The percent gets a
## dark outline so it reads on light or dark panels.
static func draw(ci: CanvasItem, font: Font, pos: Vector2, got: int, total: int,
		text_col: Color, centred := false) -> void:
	var pct := percent(got, total)
	var line := "You got  %d / %d" % [got, total]
	var big := "%d%%" % pct
	var lx := pos.x - (font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x / 2.0 if centred else 0.0)
	var bx := pos.x - (font.get_string_size(big, HORIZONTAL_ALIGNMENT_LEFT, -1, 60).x / 2.0 if centred else 0.0)
	ci.draw_string(font, Vector2(lx, pos.y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, text_col)
	ci.draw_string_outline(font, Vector2(bx, pos.y + 66), big, HORIZONTAL_ALIGNMENT_LEFT, -1, 60, 6, Color(0.1, 0.06, 0.05))
	ci.draw_string(font, Vector2(bx, pos.y + 66), big, HORIZONTAL_ALIGNMENT_LEFT, -1, 60, pct_color(pct / 100.0))

extends Control
## In-world SubViewport screen. Interacting opens the same live mission channel.
const Portrait = preload("res://scripts/LunaPortrait.gd")
var mission: Node
var mode := 0
var data := {}
var alert := false
var alert_text := ""
var clock := 0.0
var portrait: Control
var font: Font

func _ready() -> void:
	font = ThemeDB.fallback_font
	portrait = Portrait.new()
	portrait.audio = mission.audio
	portrait.position = Vector2(8, 54)
	portrait.size = Vector2(126, 126)
	add_child(portrait)

func cycle_mode() -> void:
	mode = 0

func set_alert(active: bool, text: String = "WARNING") -> void:
	alert = active
	alert_text = text

func _process(delta: float) -> void:
	clock += delta
	queue_redraw()

func text_at(point: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string(font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw() -> void:
	if mission == null or font == null:
		return
	var w := size.x
	var h := size.y
	var cyan := Color("71e9e0")
	draw_rect(Rect2(Vector2.ZERO, size), Color("071822"))
	for i in 8:
		draw_line(Vector2(0, i * h / 8), Vector2(w, i * h / 8), Color(0.2, 0.6, 0.65, 0.09))
	draw_rect(Rect2(0, 0, w, 34), Color("153c49"))
	text_at(Vector2(14, 25), "LUNA / MISSION LINK", 20, cyan)
	text_at(Vector2(18, 194), "GUIDE ONLINE", 12, cyan)
	var lines := font.get_string_size(mission.phase_label(), HORIZONTAL_ALIGNMENT_LEFT, -1, 19)
	text_at(Vector2(146, 67), mission.phase_label(), 19, Color("f5c979"))
	var words := str(mission.screen_summary()).split(" ")
	var line := ""
	var y := 98.0
	for word in words:
		var next := line + (" " if line != "" else "") + word
		if font.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x > w - 160 and line != "":
			text_at(Vector2(146, y), line, 18, Color("d4edf0"))
			y += 25
			line = word
		else:
			line = next
	text_at(Vector2(146, y), line, 18, Color("d4edf0"))
	draw_line(Vector2(14, h - 76), Vector2(w - 14, h - 76), Color(cyan, 0.35), 1.0)
	text_at(Vector2(16, h - 48), "FUEL %d%%   POWER %d%%   TIME %02d:%02d" % [mission.fuel(), mission.power(), int(mission.minutes()), int(fmod(mission.minutes(), 1.0) * 60)], 17, cyan)
	text_at(Vector2(16, h - 16), "E TO OPEN  /  TAB FOR COMMS", 14, Color("f5c979"))
	draw_rect(Rect2(1, 1, w - 2, h - 2), Color(cyan, 0.5), false, 2)

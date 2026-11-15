extends Control
## Vector avatar shared by the physical monitors and the mission comms panel.
var audio: Node
var clock := 0.0
var scale_factor := 1.0

func _process(delta: float) -> void:
	clock += delta
	queue_redraw()

func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var cyan := Color("71e9e0")
	var activity := float(audio.call("speech_activity")) if audio != null else 0.0
	draw_circle(c, s * 0.47, Color(0.08, 0.32, 0.36, 0.3))
	draw_arc(c, s * 0.46, clock * 0.12, clock * 0.12 + TAU * 0.7, 64, Color(cyan, 0.4), 1.5, true)
	draw_arc(c, s * 0.40, -clock * 0.08, -clock * 0.08 + TAU * 0.9, 64, Color(cyan, 0.2), 1.0, true)
	var head := Rect2(c - Vector2(s * 0.28, s * 0.23), Vector2(s * 0.56, s * 0.47))
	var style := StyleBoxFlat.new()
	style.bg_color = Color("12323e")
	style.border_color = cyan
	style.set_border_width_all(2)
	style.set_corner_radius_all(int(s * 0.1))
	draw_style_box(style, head)
	draw_line(c + Vector2(0, -s * 0.23), c + Vector2(0, -s * 0.34), cyan, 2, true)
	draw_circle(c + Vector2(0, -s * 0.36), s * 0.024, Color("f5c979"))
	var blink := fmod(clock, 5.0) > 4.82
	for side in [-1.0, 1.0]:
		var eye := c + Vector2(side * s * 0.12, -s * 0.045)
		if blink:
			draw_line(eye - Vector2(s * 0.04, 0), eye + Vector2(s * 0.04, 0), cyan, 2.5, true)
		else:
			draw_circle(eye, s * 0.036, cyan)
			draw_circle(eye + Vector2(s * 0.008, -s * 0.01), s * 0.01, Color.WHITE)
	for i in 7:
		var x := (i - 3) * s * 0.035
		var h := s * (0.008 + activity * 0.09 * (0.4 + 0.6 * absf(sin(clock * 17 + i * 1.3))))
		draw_line(c + Vector2(x, s * 0.13 - h), c + Vector2(x, s * 0.13 + h), cyan, maxf(1.5, s * 0.014), true)

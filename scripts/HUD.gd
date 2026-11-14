extends CanvasLayer
## On-screen help, hover read-out for controls, event log and crosshair.

const HELP := """TITANS · SPACE BRIDGE
W A S D: walk / strafe     Mouse: look around
Aim at a nearby control, then E or Left click to use it.
Esc: release cursor / pause walking     Click: resume
R: return to entry     H: hide this help
Screens change pages · switches toggle systems · door opens to corridor"""

var _help: Label
var _hover: Label
var _log: Label
var _cross: Label
var _lines: Array[String] = []


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(12, 12)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.06, 0.12, 0.72)
	sb.border_color = Color(0.3, 0.75, 1.0, 0.6)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	_help = Label.new()
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help.text = HELP
	_help.add_theme_color_override("font_color", Color(0.75, 0.92, 1.0))
	_help.add_theme_font_size_override("font_size", 14)
	panel.add_child(_help)
	add_child(panel)

	_hover = Label.new()
	_hover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_hover.add_theme_font_size_override("font_size", 18)
	_hover.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hover.position = Vector2(-300, -90)
	_hover.size = Vector2(600, 30)
	_hover.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hover)

	_log = Label.new()
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_theme_color_override("font_color", Color(0.6, 0.95, 0.75))
	_log.add_theme_font_size_override("font_size", 14)
	_log.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_log.position = Vector2(14, -150)
	_log.size = Vector2(900, 140)
	_log.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_log)

	_cross = Label.new()
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.text = "+"
	_cross.add_theme_font_size_override("font_size", 26)
	_cross.add_theme_color_override("font_color", Color(0.6, 0.95, 1.0, 0.9))
	_cross.set_anchors_preset(Control.PRESET_CENTER)
	_cross.position = Vector2(-8, -18)
	_cross.visible = false
	add_child(_cross)

	var cockpit := get_node_or_null("../Cockpit")
	if cockpit != null:
		cockpit.control_event.connect(_on_control_event)
		cockpit.status_message.connect(push_line)
	var cam := get_node_or_null("../Astronaut")
	if cam != null:
		cam.get_node("Interaction").hover_changed.connect(func(t: String) -> void: _hover.text = t)
		_cross.visible = cam.mouse_look_active
		cam.mouse_look_changed.connect(func(on: bool) -> void: _cross.visible = on)
	push_line("Bridge 6 systems online.")


func push_line(text: String) -> void:
	_lines.append(text)
	while _lines.size() > 6:
		_lines.pop_front()
	_log.text = "\n".join(_lines)


func _on_control_event(id: String, state: Variant) -> void:
	var s := str(state)
	if typeof(state) == TYPE_BOOL:
		s = "ON" if state else "OFF"
	push_line("» %s → %s" % [id, s])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
		_help.get_parent().visible = not _help.get_parent().visible

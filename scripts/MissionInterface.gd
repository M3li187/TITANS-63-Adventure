extends CanvasLayer
## A readable comms overlay; the same LUNA avatar lives on physical monitors.
const Portrait = preload("res://scripts/LunaPortrait.gd")
const BG := Color("091722")
const PANEL := Color("102733")
const CYAN := Color("71e9e0")
const AMBER := Color("f5c979")
const TEXT := Color("e3eef1")
const DIM := Color("92aab4")
var mission: Node
var root: Control
var overlay: Control
var card: PanelContainer
var body: VBoxContainer
var title: Label
var kicker: Label
var _fuel: Label
var _power: Label
var _time: Label
var _altitude: Label
var _subtitle: Label
var _subtitle_panel: PanelContainer
var _hover: Label
var _cross: Label
var _voice_button: Button
var _sound_button: Button
var _music_button: Button
var _mission_alert: PanelContainer
var _mission_alert_text: Label

func style(color: Color, border: Color = Color.TRANSPARENT, radius: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(18)
	return s

func label(text: String, size: int = 18, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func paragraph(text: String, size: int = 20, color: Color = TEXT) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func button(text: String, action: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size.y = 48
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", BG if primary else TEXT)
	b.add_theme_color_override("font_hover_color", BG if primary else Color.WHITE)
	b.add_theme_stylebox_override("normal", style(CYAN if primary else Color("183642"), Color("32535f"), 8))
	b.add_theme_stylebox_override("hover", style(Color("9cf4ec") if primary else Color("254c58"), CYAN, 8))
	b.add_theme_stylebox_override("pressed", style(Color("4eaea9") if primary else Color("0f2933"), CYAN, 8))
	b.add_theme_stylebox_override("focus", style(Color(0.1, 0.4, 0.45, 0.15), CYAN, 8))
	b.pressed.connect(action)
	return b

func _ready() -> void:
	layer = 5
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_header()
	_build_subtitles()
	_build_overlay()
	_build_mission_alert()
	_cross = label("·", 40, CYAN)
	_cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_cross.position = Vector2(-7, -26)
	root.add_child(_cross)
	_hover = paragraph("", 16, AMBER)
	_hover.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hover.anchor_left = 0.5
	_hover.anchor_right = 0.5
	_hover.anchor_top = 1
	_hover.anchor_bottom = 1
	_hover.offset_left = -430
	_hover.offset_right = 430
	_hover.offset_top = -226
	_hover.offset_bottom = -188
	root.add_child(_hover)
	mission.player.get_node("Interaction").hover_changed.connect(func(text: String) -> void: _hover.text = text)

func _build_header() -> void:
	var top := HBoxContainer.new()
	top.anchor_right = 1
	top.offset_left = 28
	top.offset_right = -28
	top.offset_top = 20
	top.add_theme_constant_override("separation", 12)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var brand := VBoxContainer.new()
	brand.add_child(label("TITANS / FRA MAURO", 24, TEXT))
	brand.add_child(label("LUNAR LANDING TRAINER  ·  LUNA ONLINE", 12, CYAN))
	top.add_child(brand)
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(space)
	for name in ["FUEL", "POWER", "TIME BUDGET"]:
		var panel := PanelContainer.new()
		panel.custom_minimum_size.x = 120
		panel.add_theme_stylebox_override("panel", style(Color(0.025, 0.075, 0.10, 0.94), Color("32535f"), 8))
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := VBoxContainer.new()
		box.add_child(label(name, 11, DIM))
		var value := label("100%", 25, CYAN)
		box.add_child(value)
		panel.add_child(box)
		top.add_child(panel)
		match name:
			"FUEL": _fuel = value
			"POWER": _power = value
			_: _time = value
	_altitude = label("", 14, DIM)
	_altitude.anchor_right = 1
	_altitude.anchor_left = 1
	_altitude.offset_left = -550
	_altitude.offset_right = -28
	_altitude.offset_top = 120
	_altitude.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_altitude)
	var footer := label("TAB  LUNA   ·   WASD  WALK   ·   SHIFT  RUN   ·   SPACE  JUMP   ·   E  USE   ·   T  REPLAY   ·   M  AUDIO   ·   V  VOICE   ·   N  MUSIC", 12, DIM)
	footer.anchor_top = 1
	footer.anchor_bottom = 1
	footer.offset_left = 28
	footer.offset_top = -30
	root.add_child(footer)

func _build_subtitles() -> void:
	_subtitle_panel = PanelContainer.new()
	_subtitle_panel.anchor_left = 0.5
	_subtitle_panel.anchor_right = 0.5
	_subtitle_panel.anchor_top = 1
	_subtitle_panel.anchor_bottom = 1
	_subtitle_panel.offset_left = -480
	_subtitle_panel.offset_right = 480
	_subtitle_panel.offset_top = -177
	_subtitle_panel.offset_bottom = -54
	_subtitle_panel.add_theme_stylebox_override("panel", style(Color(0.025, 0.06, 0.09, 0.95), Color("32535f"), 10))
	_subtitle_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_child(label("LUNA  /  SCREEN TRANSMISSION", 11, CYAN))
	_subtitle = paragraph("", 17, TEXT)
	box.add_child(_subtitle)
	_subtitle_panel.add_child(box)
	root.add_child(_subtitle_panel)

func _build_overlay() -> void:
	overlay = Control.new()
	overlay.visible = false
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.035, 0.055, 0.78)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	card = PanelContainer.new()
	card.custom_minimum_size = Vector2(900, 620)
	card.add_theme_stylebox_override("panel", style(BG, Color("32535f"), 16))
	center.add_child(card)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 14)
	card.add_child(main)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	main.add_child(header)
	var avatar := Portrait.new()
	avatar.audio = mission.audio
	avatar.custom_minimum_size = Vector2(112, 112)
	header.add_child(avatar)
	var captions := VBoxContainer.new()
	captions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	captions.add_child(label("LUNA  /  YOUR LANDING GUIDE", 13, CYAN))
	title = label("MISSION BRIEFING", 26, TEXT)
	captions.add_child(title)
	kicker = label("NASA-inspired scenario · simulated resource costs", 13, DIM)
	captions.add_child(kicker)
	header.add_child(captions)
	var close := button("Return to bridge  [Tab]", close_panel)
	close.custom_minimum_size.x = 200
	header.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	main.add_child(controls)
	controls.add_child(button("Replay message", func() -> void: mission.replay_message()))
	_voice_button = button("Voice: on", func() -> void: mission.audio.toggle_voice())
	controls.add_child(_voice_button)
	_sound_button = button("Audio: on", func() -> void: mission.audio.toggle_sound())
	controls.add_child(_sound_button)
	_music_button = button("Music: on", func() -> void: get_node("/root/SpaceMusic").toggle_music())
	controls.add_child(_music_button)

func open_panel() -> void:
	if mission.cinematic != null and mission.cinematic.active: return
	overlay.visible = true
	mission.player.set_mouse_look(false)
	refresh()
	mission.on_comms_opened()

func close_panel() -> void:
	overlay.visible = false
	mission.player.set_mouse_look(true)

func panel_visible() -> bool:
	return overlay != null and overlay.visible

func _clear_body() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()

func refresh() -> void:
	if body == null:
		return
	_clear_body()
	title.text = mission.phase_label()
	kicker.text = "Choose a plan, then follow LUNA to the highlighted control"
	match mission.phase:
		"briefing":
			body.add_child(paragraph("Welcome, Commander.", 27, AMBER))
			body.add_child(paragraph("Approach the Moon, handle three landing challenges, and bring your crew safely to Fra Mauro. I will guide you from the bridge screens."))
			body.add_child(paragraph("Your 20-minute mission clock starts as soon as the game begins. Explore the bridge; LUNA will alert you when a mission needs attention.", 18, DIM))
			body.add_child(paragraph("Use the buttons or 1 / 2 / 3 to choose a plan. Then walk to the highlighted control and press E to carry it out. LUNA will guide you.", 17, DIM))
			body.add_child(button("Return to the bridge", close_panel, true))
		"choice":
			body.add_child(paragraph(str(mission.current_scenario()["prompt"]), 22, TEXT))
			body.add_child(label("WHAT WILL YOU DO?  /  1, 2 OR 3", 12, AMBER))
			for option in mission.current_scenario()["choices"]:
				var id := str(option["id"])
				var choice := button("%s   %s" % [id, option["label"]], func() -> void: mission.choose(id))
				choice.alignment = HORIZONTAL_ALIGNMENT_LEFT
				choice.custom_minimum_size.y = 76
				if mission.stage_index == 2 and id == "A" and mission.lights_used:
					choice.disabled = true
					choice.text = "A   Landing lights are already on\nChoose B or C to select the landing site."
				body.add_child(choice)
		"task":
			body.add_child(paragraph(mission.tasks.instruction, 25, CYAN))
			body.add_child(paragraph(mission.tasks.location_hint, 20, AMBER))
			body.add_child(paragraph("Return to the bridge. Follow the cyan marker, aim at the control, and press E. Your decision is applied only after you carry out the task.", 19, TEXT))
			body.add_child(button("Carry out the task  →", close_panel, true))
		"result":
			body.add_child(label("TASK COMPLETE  /  " + mission.last_choice, 13, CYAN))
			body.add_child(paragraph(mission.last_outcome, 24, TEXT))
			if not mission.last_effects.is_empty():
				var cost: Dictionary = mission.last_effects
				body.add_child(paragraph("RESOURCE EFFECTS\nFuel −%d%%   /   Power −%d%%   /   Time −%d min" % [cost["fuel_percentage_points"], cost["power_percentage_points"], cost["time_minutes"]], 21, AMBER))
			if mission.stage_index == 1 and not mission.reliable_height:
				body.add_child(paragraph("WARNING: visual observation does not provide reliable altitude. A landing attempt without a restored radar or backup sensor will be unsafe.", 18, AMBER))
			if mission.stage_index == 2 and mission.last_choice == "A":
				body.add_child(paragraph("Lights improve visibility. They do not select a landing site. Choose B or C next; their resource costs will also apply.", 18, AMBER))
			body.add_child(paragraph("Remaining: %d%% fuel  /  %d%% power  /  %02d:%02d" % [mission.fuel(), mission.power(), int(mission.minutes()), int(fmod(mission.minutes(), 1.0) * 60)], 18, CYAN))
			var next := "Continue  →"
			if mission.stage_index == 2 and mission.last_choice != "A": next = "Watch the final descent  →"
			if mission.stage_index == 2 and mission.last_choice == "A": next = "Choose a landing site  →"
			if mission._pending_ending == "safe": next = "Return safely to orbit  →"
			body.add_child(button(next, func() -> void: mission.advance(), true))
		"coasting":
			body.add_child(paragraph("Systems stable. Stand by for LUNA.", 24))
			body.add_child(paragraph("Walk around or inspect the bridge. An alert will ask you to press Tab when the next mission is ready.", 19, DIM))
			body.add_child(button("Return to the bridge", close_panel, true))
		"descent":
			body.add_child(paragraph("Ending sequence in progress. Flight controls are locked for the camera sequence.", 24, TEXT))
			body.add_child(button("View the descent  →", close_panel, true))
		"ending":
			body.add_child(paragraph(mission.ending_title(), 29, AMBER if mission.ending == "bad" else CYAN))
			body.add_child(paragraph(mission.ending_description(), 20, TEXT))
			for item in mission.history:
				body.add_child(label("SCENARIO %d  →  %s" % [item["stage"], item["choice"]], 15, DIM))
			body.add_child(paragraph("Secret goal: safe landing + safe decisions + fuel ≥70% + power ≥75% + time ≥7 min.", 16, AMBER))
			body.add_child(button("Restart the training mission  ↻", func() -> void: mission.reset_mission(), true))

func _process(_delta: float) -> void:
	if _fuel == null:
		return
	_mission_alert_text.text = mission.alert_text()
	_mission_alert.visible = not panel_visible() and _mission_alert_text.text != ""
	_fuel.text = "%d%%" % mission.fuel()
	_power.text = "%d%%" % mission.power()
	_time.text = "%02d:%02d" % [int(mission.minutes()), int(fmod(mission.minutes(), 1.0) * 60)]
	_altitude.text = "SIM ALT  %s  ·  %s" % [("%.0f m" % maxf(0, mission.lunar.altitude_m - 1.0)) if mission.reliable_height or mission.stage_index == 0 else "NO RELIABLE DATA", mission.phase_label()]
	_voice_button.text = "Voice: on" if mission.audio.voice_enabled else "Voice: off"
	_sound_button.text = "Audio: on" if mission.audio.sound_enabled else "Audio: muted"
	_music_button.text = "Music: on" if get_node("/root/SpaceMusic").music_enabled else "Music: off"
	_subtitle.text = mission.subtitle
	_subtitle_panel.visible = not panel_visible() and (mission.audio.speaking() or mission.subtitle_time < 18.0)
	_hover.visible = not panel_visible()
	_cross.visible = not panel_visible() and mission.player.mouse_look_active


func _build_mission_alert() -> void:
	_mission_alert = PanelContainer.new()
	_mission_alert.anchor_left = .5
	_mission_alert.anchor_right = .5
	_mission_alert.offset_left = -370
	_mission_alert.offset_right = 370
	_mission_alert.offset_top = 150
	_mission_alert.add_theme_stylebox_override("panel", style(Color(0.12, 0.10, 0.055, .96), AMBER, 10))
	_mission_alert.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mission_alert_text = paragraph("", 20, AMBER)
	_mission_alert_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mission_alert.add_child(_mission_alert_text)
	root.add_child(_mission_alert)

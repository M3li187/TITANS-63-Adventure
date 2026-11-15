extends Node3D
## Four authored, in-engine camera sequences using the bridge and lunar terrain.
## The shot clock is independent of narration; no network/video dependencies.
var mission: Node
var camera: Camera3D
var active := false
var elapsed := 0.0
var duration := 14.0
var kind := ""
var reason := ""
var shot := -1
var caption: Label
var title: Label
var fade: ColorRect
var overlay: CanvasLayer
var _done: Callable
var _impact_played := false
var _dust: Array[MeshInstance3D] = []

func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "EndingCamera"
	camera.fov = 60
	camera.near = .05
	camera.far = 10000
	camera.cull_mask = 1
	add_child(camera)
	overlay = CanvasLayer.new()
	overlay.layer = 15
	add_child(overlay)
	for bottom in [false, true]:
		var bar := ColorRect.new()
		bar.color = Color(.005, .012, .02, .96)
		bar.anchor_right = 1
		bar.offset_bottom = 76
		if bottom:
			bar.anchor_top = 1
			bar.anchor_bottom = 1
			bar.offset_top = -106
			bar.offset_bottom = 0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(bar)
	title = _label(24, Color("88f1e6"))
	title.position = Vector2(36, 20)
	overlay.add_child(title)
	caption = _label(19, Color("e8f4f5"))
	caption.anchor_top = 1
	caption.anchor_bottom = 1
	caption.anchor_right = 1
	caption.offset_left = 36
	caption.offset_right = -36
	caption.offset_top = -89
	caption.offset_bottom = -12
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay.add_child(caption)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(fade)
	overlay.hide()
	# Sparse ballistic regolith fragments. They settle quickly in lunar gravity.
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.33, .31, .27)
	material.roughness = 1
	for i in 36:
		var particle := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = .035 + float(i % 4) * .012
		mesh.height = mesh.radius * 2
		mesh.radial_segments = 5
		mesh.rings = 2
		particle.mesh = mesh
		particle.material_override = material
		particle.visible = false
		add_child(particle)
		_dust.append(particle)

func _label(size: int, color: Color) -> Label:
	var result := Label.new()
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

func play(ending: String, why: String, done: Callable) -> void:
	stop()
	kind = ending
	title.add_theme_color_override("font_color", Color("ff9b83") if ending == "bad" else Color("88f1e6"))
	reason = why
	_done = done
	duration = {"secret": 16.0, "normal": 14.0, "safe": 13.0, "bad": 13.0}[kind]
	elapsed = 0
	shot = -1
	_impact_played = false
	active = true
	mission.ui.close_panel()
	mission.ui.root.hide()
	mission.player.input_locked = true
	mission.player.set_mouse_look(false)
	camera.make_current()
	overlay.show()
	if kind == "safe":
		mission.lunar.fly_abort(func() -> void: pass)
	elif kind != "bad" or reason != "resource":
		mission.lunar.fly_landing(mission.last_choice == "C", func() -> void: pass, reason != "height")
	elif mission.lunar._flight != null:
		mission.lunar._flight.kill()
	_update_shot()

func stop() -> void:
	active = false
	if overlay != null: overlay.hide()
	for particle in _dust: particle.hide()
	if mission != null and is_instance_valid(mission.player):
		mission.player.input_locked = false
		mission.player.camera.make_current()
		if mission.ui != null: mission.ui.root.show()

func _process(delta: float) -> void:
	if not active: return
	elapsed += delta
	_update_shot()
	if elapsed >= duration:
		var callback := _done
		stop()
		mission.player.set_mouse_look(true)
		callback.call()

func _update_shot() -> void:
	var next_shot := 0 if elapsed < 3.0 else (1 if elapsed < 8.5 else 2)
	if next_shot != shot:
		shot = next_shot
		var names := {"secret": "SECRET ENDING / FRA MAURO PATHFINDER", "normal": "GOOD ENDING / SAFE TOUCHDOWN", "safe": "SAFE ENDING / RETURN TO ORBIT", "bad": "BAD ENDING / LANDING UNSAFE"}
		title.text = names[kind]
		var lines: Array
		if kind == "safe":
			lines = ["Abort command accepted. Ascent engines engaged.", "The surface falls away as the ship returns to a safe holding orbit.", "Crew secure. Landing cancelled. There will be another mission."]
		elif kind == "secret":
			lines = ["Reliable height data confirmed. Diverting to the clear zone.", "Controlled descent. Fuel, power and time reserves meet the Pathfinder requirements.", "Touchdown confirmed. Fra Mauro Pathfinder unlocked. Next stop: the Moon base."]
		elif kind == "normal":
			lines = ["Clear landing zone selected. Beginning the final approach.", "Descending under instrument guidance. Stand by for contact.", "Touchdown. Crew safe at Fra Mauro. Training mission complete."]
		elif reason == "rocks":
			lines = ["Landing committed between the rocks. Clearance is dangerously low.", "Hazard proximity! The landing gear is approaching the boulders.", "Hard contact. Landing safety compromised. Training simulation ended."]
		elif reason == "height":
			lines = ["Reliable altitude unavailable. The landing cannot be verified.", "Descent halted above the surface. Crew awaits recovery instructions.", "Unsafe landing attempt. Restore radar or use the backup height sensor next time."]
		else:
			lines = ["A required mission resource has been exhausted.", "Landing guidance offline. The approach cannot continue.", "Training simulation ended. Review the mission budget and try again."]
		caption.text = lines[shot]
	var location: Vector3
	var aim: Vector3
	if shot == 0:
		location = Vector3(0, 1.8, 1.5).lerp(Vector3(0, 1.76, .6), clampf(elapsed / 3.0, 0, 1))
		aim = Vector3(0, 1.05, -6)
	elif shot == 1:
		var t := clampf((elapsed - 3) / 5.5, 0, 1)
		location = Vector3(13, 7, -16).lerp(Vector3(10, 4.5, -13), t)
		aim = Vector3(0, .7, -.7)
	else:
		var t := clampf((elapsed - 8.5) / (duration - 8.5), 0, 1)
		if kind == "safe":
			location = Vector3(12, 7, -14).lerp(Vector3(24, 14, -26), t)
		elif kind == "secret":
			location = Vector3(-9, 3, -12).lerp(Vector3(-16, 7, -18), t)
		elif kind == "bad" and reason == "rocks":
			location = Vector3(8, 2, -9).lerp(Vector3(10, 3, -11), t)
		else:
			location = Vector3(10, 3, -12).lerp(Vector3(15, 6, -16), t)
		aim = Vector3(0, .5, -.7)
	camera.position = location
	camera.look_at(aim)
	camera.rotation.z = 0
	if kind == "bad" and reason == "rocks" and elapsed >= 9 and elapsed < 10.2:
		var strength := (10.2 - elapsed) * .025
		camera.position += Vector3(sin(elapsed * 83), sin(elapsed * 107), 0) * strength
		camera.rotation.z = sin(elapsed * 33) * strength
	var contact := kind in ["secret", "normal"] or (kind == "bad" and reason == "rocks")
	if contact and elapsed >= 9.0:
		if not _impact_played:
			_impact_played = true
			mission.audio.play_sfx("touchdown", -12 if kind == "bad" else -19)
		for i in _dust.size():
			var particle := _dust[i]
			var t := elapsed - 9.0
			var a := float(i) * 2.399
			var speed := 1.4 + float(i % 7) * .25
			particle.visible = t < 2.0
			particle.position = Vector3(cos(a) * (2 + t * speed), -1 + maxf(0, .6 * t - .81 * t * t), sin(a) * (2 + t * speed))
	# Short fades mask the entry/exit; shot changes themselves are hard camera cuts.
	fade.color.a = maxf(clampf(1.0 - elapsed / .55, 0, 1), clampf((elapsed - duration + .7) / .7, 0, 1))
	if kind == "bad" and reason == "resource":
		fade.color.a = maxf(fade.color.a, clampf((elapsed - 7) / 12.0, 0, .4))

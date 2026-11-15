extends Node
## Validation helper. Inactive unless the game is launched with
##   godot --path . -- --screenshots=<output_dir>
## It then captures a set of views and quits.
## Also provides a non-visual self test:  godot --headless --path . -- --selftest

const SHOTS := [
	["interior", Vector3(0.0, 1.62, 2.6), 0.0, -0.14, 0.0],
	["pilot", Vector3(-1.0, 1.28, -1.78), 0.0, -0.18, 0.0],
	["dash_close", Vector3(0.0, 1.25, -2.0), 0.0, -0.45, 0.0],
	["seats", Vector3(1.6, 1.5, -0.4), 0.85, -0.35, 0.0],
	["left_side", Vector3(-0.6, 1.5, 0.4), 1.35, -0.12, 0.0],
	["right_side", Vector3(0.6, 1.5, 0.4), -1.35, -0.12, 0.0],
	["overhead", Vector3(0.0, 1.3, 0.3), 0.0, 1.0, 0.0],
	["rear", Vector3(0.0, 1.55, -0.8), PI, -0.05, 0.0],
	["exterior", Vector3(0.0, 1.2, 3.5), 2.45, -0.3, 13.0],
	["exterior_rear", Vector3(0.0, 1.2, 5.0), -0.6, -0.35, 22.0],
	["exterior_side", Vector3(0.0, 1.0, 4.0), -1.57, -0.1, 18.0],
	["throttle", Vector3(0.0, 1.45, -1.0), 0.0, -0.75, 0.0],
]

var _dir := ""
var _i := 0
var _wait := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screenshots="):
			_dir = a.trim_prefix("--screenshots=")
		if a.begins_with("--shot-start="):
			_i = int(a.trim_prefix("--shot-start="))
		if a == "--selftest":
			_selftest.call_deferred()
	set_process(_dir != "")
	if _dir != "":
		DirAccess.make_dir_recursive_absolute(_dir)
		var demo := get_node_or_null("../MissionDemo")
		if demo != null:
			demo.set("enabled", false)
		var hud := get_node_or_null("../HUD")
		if hud != null:
			hud.visible = false


func _process(_delta: float) -> void:
	var cam := get_node("../Camera")
	if _wait == 0:
		if _i >= SHOTS.size():
			get_tree().quit()
			return
		var s: Array = SHOTS[_i]
		cam.set("pivot", s[1])
		cam.set("yaw", s[2])
		cam.set("pitch", s[3])
		cam.set("dist", s[4])
		cam.call("_update_transform")
	_wait += 1
	if _wait >= 40:
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%02d_%s.png" % [_dir, _i, SHOTS[_i][0]])
		print("saved ", SHOTS[_i][0])
		_wait = 0
		_i += 1


func _selftest() -> void:
	var cockpit := get_node("../Cockpit")
	var cam: Camera3D = get_node("../Camera")
	var events := []
	cockpit.control_event.connect(func(id: String, st: Variant) -> void: events.append([id, st]))
	for f in 5:
		await get_tree().physics_frame
	# 1) ray-pick test: aim the camera at a few controls and pick through the screen centre
	var picked := 0
	for id in ["MASTER_CAUTION", "THROTTLE_1", "DASH_3", "LIFE_SUPPORT", "DOOR_CONTROL", "RED_ALERT"]:
		var c: Node3D = cockpit.get_control(id)
		var target := c.global_position
		var from := target + c.global_transform.basis.z.normalized() * 0.6
		cam.set("pivot", from)
		cam.set("dist", 0.0)
		cam.look_at_from_position(from, target, Vector3.UP if absf(c.global_transform.basis.z.y) < 0.9 else Vector3.FORWARD)
		var e := cam.global_transform.basis.get_euler()
		cam.set("pitch", e.x)
		cam.set("yaw", e.y)
		cam.call("_update_transform")
		await get_tree().physics_frame
		await get_tree().physics_frame
		var hit: Object = cam.call("_pick", get_viewport().get_visible_rect().size * 0.5)
		var ok := hit == c
		picked += 1 if ok else 0
		print("pick %-16s -> %s" % [id, "OK" if ok else "MISS (%s)" % [hit]])
	# 2) activate every control
	var n := 0
	for id in cockpit.list_controls():
		cockpit.get_control(id).activate()
		n += 1
	# 3) mission API
	cockpit.set_warning("MASTER_WARNING", true)
	cockpit.set_screen_alert("DASH_3", true, "TEST")
	cockpit.set_screen_mode("DASH_1", 4)
	cockpit.set_screen_value("DASH_3", "ALT", 300.0)
	for f in 30:
		await get_tree().process_frame
	print("SELFTEST: picked %d/6, activated %d controls, %d events received" % [picked, n, events.size()])
	get_tree().quit()

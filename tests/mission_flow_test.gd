extends SceneTree
var failures := 0
var mission: Node
var main: Node3D
func _initialize() -> void: call_deferred("run")
func ticks(n: int) -> void:
	for i in n: await process_frame
func check(ok: bool, label: String) -> void:
	if ok: print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)
func ready_next() -> void:
	mission._mission_delay_remaining = 0.03
	await ticks(4)
func run() -> void:
	main = (load("res://Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await ticks(4)
	mission = main.get_node("LandingMission")
	check(not mission.ui.panel_visible(), "no automatic mission panel at startup")
	check(mission.phase == "briefing" and mission.minutes() < 20, "clock starts before first mission")
	var before: float = mission.minutes()
	await ticks(30)
	check(mission.minutes() < before - .004, "real-time countdown runs during exploration")
	await ready_next()
	check(mission.phase == "choice" and not mission.ui.panel_visible(), "first mission arrives without popup")
	check("TAB" in mission.alert_text(), "mission alert asks player to press Tab")
	var key := InputEventKey.new()
	key.keycode = KEY_TAB
	key.pressed = true
	Input.parse_input_event(key)
	await ticks(2)
	check(mission.ui.panel_visible(), "Tab opens mission")
	for node in mission.ui.body.get_children():
		if node is Button:
			check(not "%" in node.text and not "Time" in node.text, "options hide resource consequences")
	check(not str(mission.ui.get_script().source_code).contains('button("NASA data'), "NASA data tab removed")
	before = mission.minutes()
	await ticks(15)
	check(mission.minutes() < before, "clock also runs while mission panel is open")
	await perform_choice("A")
	check(mission.phase == "result" and mission.power() == 95, "choice applies effects")
	check(mission.last_effects["power_percentage_points"] == 5, "post-choice effect values retained")
	var shown := false
	for node in mission.ui.body.get_children():
		if node is Label and "RESOURCE EFFECTS" in node.text: shown = true
	check(shown, "resource changes shown after selecting")
	mission.advance()
	check(mission.phase == "coasting" and not mission.ui.panel_visible(), "gap between missions; panel closes")
	await ticks(30)
	check(mission.phase == "coasting", "next mission is not immediate")
	await ready_next()
	check(mission.stage_index == 1 and mission.phase == "choice" and not mission.ui.panel_visible(), "second mission arrives as alert")
	mission.ui.open_panel()
	await perform_choice("B")
	mission.advance()
	await ready_next()
	mission.ui.open_panel()
	await perform_choice("C")
	check(mission.fuel() == 70 and mission.power() == 75, "A-B-C fuel and power remain unchanged")
	check(absf(mission.minutes() - (11.0 - mission.elapsed_seconds / 60.0)) < .003, "time includes both real elapsed time and choice penalties")
	mission.advance()
	main.get_node("LunarWorld")._flight.set_speed_scale(1000)
	mission.cinematic.elapsed = mission.cinematic.duration - .001
	await ticks(6)
	check(mission.ending == "secret" and not mission.ui.panel_visible(), "secret ending does not force a panel open")
	mission._secret_transfer_remaining = 0
	await ticks(12)
	var base := current_scene
	check(base != null and base.name == "MoonBase", "secret ending switches to supplied Moon-base scene")
	if base == null or base.name != "MoonBase":
		quit(1)
		return
	for i in 120: await physics_frame
	var player := base.get_node("Astronaut") as CharacterBody3D
	check(player.is_on_floor(), "base player safely grounded")
	check(player.fall_reset_y == -35.0, "outdoor fall reset plane configured")
	var start := player.position
	Input.action_press("front")
	Input.action_press("sprint")
	for i in 30: await physics_frame
	Input.action_release("front")
	Input.action_release("sprint")
	check(player.position.distance_to(start) > .3, "sprint works in Moon base")
	check(get_meta("moon_base_arrival")["ending"] == "secret", "mission result carried to base")
	base.queue_free()
	await ticks(3)
	print("MISSION FLOW / BASE: ", failures, " failures")
	quit(0 if failures == 0 else 1)

func perform_choice(id: String) -> void:
	mission.choose(id)
	await complete_assigned_task()

func complete_assigned_task() -> void:
	for i in 4:
		if mission.phase != "task": return
		if mission.tasks.wait_remaining >= 0:
			mission.tasks.wait_remaining = .001
			await ticks(3)
		var control: Node = mission.cockpit.get_control(mission.tasks.target_id)
		if control != null: control.activate()

extends SceneTree
var failures := 0
var mission: Node
var main: Node3D
func _initialize() -> void: call_deferred("run")
func ticks(n: int) -> void:
	for i in n: await process_frame
func check(ok: bool, text: String) -> void:
	if ok: print("PASS ", text)
	else:
		failures += 1
		push_error("FAIL " + text)
func start_stage(stage: int) -> void:
	mission.reset_mission()
	mission.stage_index = stage
	mission._present_stage()
func run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await ticks(5)
	mission = main.get_node("LandingMission")
	start_stage(0)
	mission.ui.open_panel()
	mission.choose("A")
	check(mission.phase == "task" and not mission.ui.panel_visible(), "selecting a plan returns player to the bridge")
	check(mission.power() == 100 and mission.history.is_empty(), "selecting alone spends no resource cost")
	mission.cockpit.get_control("LIDAR").activate()
	check(mission.phase == "task" and mission.history.is_empty(), "wrong switch does not complete task")
	mission.cockpit.get_control("S_BAND").activate()
	check(mission.phase == "result" and mission.power() == 95 and mission.history.size() == 1, "physical communications uplink applies choice once")
	mission.cockpit.get_control("S_BAND").activate()
	check(mission.history.size() == 1, "repeated control use does not repeat resource cost")
	start_stage(0)
	mission.choose("B")
	mission.cockpit.get_control("MASTER_CAUTION").activate()
	check(mission.phase == "task" and mission.tasks.wait_remaining > 0, "recheck requires a waiting stage")
	mission.tasks.wait_remaining = .001
	await ticks(3)
	check(mission.tasks.target_id == "S_BAND", "persistent warning redirects player to Mission Control")
	mission.replay_message()
	check(mission.audio.current_voice_id == "task_recheck_done", "replay follows the current recheck objective")
	mission.cockpit.get_control("S_BAND").activate()
	check(mission.phase == "result" and not mission.safe_decisions, "delayed report preserves its authored outcome")
	start_stage(1)
	mission.choose("A")
	mission.cockpit.get_control("RADAR").activate()
	check(mission.phase == "task" and not mission.reliable_height, "radar OFF alone is insufficient")
	mission.replay_message()
	check(mission.audio.current_voice_id == "task_radar_on", "replay follows the radar power-cycle step")
	mission.cockpit.get_control("RADAR").activate()
	check(mission.phase == "result" and mission.reliable_height, "radar OFF then ON restores altitude")
	start_stage(1)
	mission.choose("B")
	var player: CharacterBody3D = mission.player
	player.position = Vector3(1.8, .05, .3)
	player.rotation = Vector3.ZERO
	for i in 15: await physics_frame
	var sensor: Node3D = mission.cockpit.get_control("LIDAR")
	player.head_pivot.look_at(sensor.global_position)
	for i in 3: await physics_frame
	var interaction: Node = player.get_node("Interaction")
	check(interaction.pick() == sensor, "backup sensor is under the physical first-person interaction ray")
	var use := InputEventAction.new()
	use.action = "interact"
	use.pressed = true
	Input.parse_input_event(use)
	for i in 3: await physics_frame
	check(mission.phase == "result" and mission.reliable_height and mission.power() == 85, "E actually activates the backup height sensor")
	# The threshold is inclusive and is not rounded up from a lower value.
	mission.safe_decisions = true
	mission.last_choice = "C"
	mission.resources = {"fuel":70.0, "power":75.0, "minutes":7.0}
	check(mission.evaluate_landing() == "secret", "exactly 7 minutes meets secret threshold")
	mission.resources["minutes"] = 6.999
	check(mission.evaluate_landing() == "normal", "less than 7 minutes receives good ending")
	for kind in ["bad", "normal", "safe", "secret"]:
		mission.reset_mission()
		mission.phase = "descent"
		mission._pending_ending = kind
		mission.ending_reason = "rocks" if kind == "bad" else ""
		mission.last_choice = "C"
		mission.cinematic.play(kind, mission.ending_reason, mission._finish_flight)
		check(mission.cinematic.camera.current and player.input_locked and not player.mouse_look_active, kind + " cinematic takes the camera and locks movement")
		mission.ui.open_panel()
		player.set_mouse_look(true)
		check(not mission.ui.panel_visible() and not player.mouse_look_active, kind + " cinematic blocks recapture and menus")
		var before: float = mission.minutes()
		mission.cinematic.elapsed = 4
		await ticks(2)
		check(mission.cinematic.shot == 1 and mission.cinematic.camera.position.x > 5, kind + " exterior tracking shot")
		check(mission.minutes() == before, "noninteractive ending does not charge extra time")
		if mission.lunar._flight != null: mission.lunar._flight.set_speed_scale(1000)
		mission.cinematic.elapsed = 10
		await ticks(2)
		check(mission.cinematic.shot == 2 and mission.cinematic.camera.transform.is_finite(), kind + " final shot")
		mission.cinematic.elapsed = mission.cinematic.duration
		await ticks(2)
		check(mission.phase == "ending" and mission.ending == kind and not player.input_locked and player.camera.current, kind + " completes and restores first-person control")
		check(not mission.cinematic.overlay.visible and mission.ui.root.visible, kind + " restores HUD")
	main.queue_free()
	await ticks(3)
	print("PRACTICAL TASKS AND FOUR CINEMATICS: ", failures, " failures")
	quit(0 if failures == 0 else 1)

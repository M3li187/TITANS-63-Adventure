extends SceneTree
var failures := 0
var mission: Node
var main: Node3D

func _initialize() -> void: call_deferred("run")
func ticks(n: int) -> void:
	for i in n: await process_frame
func check(ok: bool, text: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL " + text)
func finish_flight() -> void:
	var lunar: Node3D = main.get_node("LunarWorld")
	if lunar._flight != null: lunar._flight.set_speed_scale(1000.0)
	mission.cinematic.elapsed = mission.cinematic.duration - .001
	await ticks(6)

func run() -> void:
	main = (load("res://Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await ticks(4)
	mission = main.get_node("LandingMission")
	check(mission.phase == "briefing" and not mission.ui.panel_visible(), "welcome panel and briefing")
	check(mission.audio.voice_lines.has("s1"), "offline bot narration")
	check(mission.audio.voice_lines["s1"].begins_with("Oh no! A warning light is flashing!"), "requested warning dialogue")
	check(mission.audio.voice.stream is AudioStreamWAV, "actual audio stream")
	for id in mission.audio.envelopes:
		var stream := load("res://assets/audio/voice/" + str(id) + ".wav") as AudioStream
		check(stream != null and stream.get_length() > 1, "voice asset " + str(id))
		check(absf(stream.get_length() - float(mission.audio.envelopes[id]["duration"])) < .1, "voice envelope duration " + str(id))
	for id in ["DASH_3", "SIDE_L_AFT", "SIDE_R_AFT"]:
		check(main.get_node("Cockpit").screens[id].get_script().resource_path.ends_with("LunaScreen.gd"), "in-world guide " + id)
	check(mission.lunar.heights.size() == 513 * 513, "bundled real elevation crop")
	check(mission.lunar.slopes.size() == 513 * 513, "bundled numeric slope crop")
	check(absf(mission.lunar.elevation(0, 0)) < .001, "terrain reference offset")
	check(float(mission.lunar.metadata["sample_spacing_m"]) < 2.001, "NASA source sample spacing")
	var paths := 0
	for first in ["A", "B"]:
		for second in ["A", "B", "C"]:
			for lights in [false, true]:
				for final in ["B", "C"]:
					mission.reset_mission()
					await advance_flow()
					await perform_choice(first)
					var once: float = mission.power()
					await perform_choice(first)
					check(mission.power() == once, "duplicate choice not charged")
					await advance_flow()
					await perform_choice(second)
					await advance_flow()
					if lights:
						await perform_choice("A")
						check(mission.phase == "result" and mission.lights_used, "landing lights are nonterminal")
						await advance_flow()
						var before: float = mission.fuel()
						await perform_choice("A")
						check(mission.fuel() == before and mission.phase == "choice", "lights charged once")
					await perform_choice(final)
					var expected_fuel: float = 100 - (10 if second == "A" else 5) - (25 if final == "C" else 5) - (10 if lights else 0)
					var expected_power: float = 100 - 5 - {"A": 5, "B": 15, "C": 0}[second] - (5 if final == "C" else 0) - (10 if lights else 0)
					var expected_minutes: float = 20 - (3 if first == "A" else 7) - {"A": 5, "B": 2, "C": 1}[second] - (4 if final == "C" else 1) - (2 if lights else 0)
					check(mission.fuel() == expected_fuel and mission.power() == expected_power and absf(mission.minutes() - (expected_minutes - mission.elapsed_seconds / 60.0)) < .003, "costs " + first + second + final + str(lights))
					await advance_flow()
					check(mission.phase == "descent", "descent begins")
					await finish_flight()
					var expected := "bad" if second == "C" or final == "B" else "normal"
					if first == "A" and second == "B" and final == "C" and not lights: expected = "secret"
					check(mission.phase == "ending" and mission.ending == expected, "ending " + first + second + final + str(lights) + " expected " + expected + " got " + mission.ending)
					paths += 1
	mission.reset_mission()
	await advance_flow()
	await perform_choice("C")
	check(mission.fuel() == 100 and mission.power() == 100 and absf(mission.minutes() - (20.0 - mission.elapsed_seconds / 60.0)) < .003, "abort costs left as unspecified")
	await advance_flow()
	await finish_flight()
	check(mission.ending == "safe", "safe abort ending")
	mission.reset_mission()
	await advance_flow()
	mission.resources["minutes"] = 1.0
	await perform_choice("A")
	await advance_flow()
	await finish_flight()
	check(mission.ending == "bad" and mission.ending_reason == "resource", "resource exhaustion future-proofed")
	mission.reset_mission()
	await advance_flow()
	mission.ui.open_panel()
	var event := InputEventKey.new()
	event.keycode = KEY_1
	event.pressed = true
	Input.parse_input_event(event)
	await ticks(2)
	check(mission.phase == "task", "keyboard choice assigns a physical task")
	await complete_assigned_task()
	check(mission.phase == "result" and mission.last_choice == "A", "physical task completes keyboard choice")
	mission.ui.close_panel()
	check(mission.player.mouse_look_active, "comms closes to first-person controls")
	mission.audio.toggle_voice()
	check(not mission.audio.voice_enabled, "independent voice mute")
	mission.audio.toggle_voice()
	mission.audio.toggle_sound()
	check(AudioServer.is_bus_mute(0), "master sound mute")
	mission.audio.toggle_sound()
	print("LANDING MISSION: ", paths, " complete landing paths + safe abort + depletion; ", failures, " failures")
	main.queue_free()
	await ticks(3)
	quit(0 if failures == 0 else 1)


func advance_flow() -> void:
	mission.advance()
	if mission.phase == "coasting":
		mission._mission_delay_remaining = 0.0
		await ticks(2)

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

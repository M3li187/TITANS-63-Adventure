extends SceneTree
var failures := 0
var main: Node3D
var player: CharacterBody3D
var music: Node
func _initialize() -> void: call_deferred("run")
func ticks(n: int) -> void:
	for i in n: await physics_frame
func check(ok: bool, text: String) -> void:
	if ok: print("PASS ", text)
	else:
		failures += 1
		push_error("FAIL " + text)
func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
func place() -> void:
	player.reset_to_spawn()
	player.position = Vector3(0, .05, 3.5)
	player.rotation.y = 0
	player.velocity = Vector3.ZERO
	await ticks(25)
func run() -> void:
	main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await ticks(30)
	player = main.get_node("Astronaut")
	music = root.get_node("SpaceMusic")
	var music_id: int = music.player.get_instance_id()
	check(music.player.stream is AudioStreamOggVorbis and music.player.stream.loop, "bundled ambient music loops")
	check(absf(music.player.stream.get_length() - 96) < .1, "96-second relaxing score")
	check(AudioServer.get_bus_index("Music") > 0 and AudioServer.get_bus_index("Footsteps") > 0, "separate music and footsteps mix buses")
	var steps: Node = player.get_node("Footsteps")
	for surface in ["bridge", "moon"]:
		check(steps._streams[surface].size() == 3, surface + " has three boot variants")
		for stream in steps._streams[surface]:
			check(stream is AudioStreamWAV and stream.get_length() > .3, surface + " real waveform loaded")
	await place()
	var before: int = steps.step_count
	await ticks(45)
	check(steps.step_count == before, "idle has no footsteps")
	Input.action_press("front")
	await ticks(64)
	Input.action_release("front")
	var walk_steps: int = steps.step_count - before
	check(walk_steps >= 2 and steps.last_surface == "bridge", "walking plays audible bridge boot samples")
	await place()
	before = steps.step_count
	Input.action_press("front")
	Input.action_press("sprint")
	await ticks(64)
	Input.action_release("front")
	Input.action_release("sprint")
	check(steps.step_count - before > walk_steps, "running increases footstep cadence")
	await place()
	main.get_node("LandingMission").ui.open_panel()
	before = steps.step_count
	Input.action_press("front")
	await ticks(40)
	Input.action_release("front")
	check(steps.step_count == before, "open comms suppresses footsteps")
	main.get_node("LandingMission").ui.close_panel()
	Input.action_press("jump")
	await ticks(3)
	Input.action_release("jump")
	before = steps.step_count
	await ticks(20)
	check(not player.is_on_floor() and steps.step_count == before, "airborne footsteps are silent")
	await ticks(120)
	before = steps.step_count
	Input.action_press("back")
	await ticks(50)
	before = steps.step_count
	await ticks(60)
	Input.action_release("back")
	check(steps.step_count == before, "pushing against a wall produces no steps")
	key(KEY_N)
	await ticks(2)
	check(not music.music_enabled and not AudioServer.is_bus_mute(0), "N pauses only background music")
	key(KEY_N)
	await ticks(2)
	check(music.music_enabled and not music.player.stream_paused, "N resumes music")
	change_scene_to_file("res://moon_base/MoonBase.tscn")
	await ticks(120)
	var base := current_scene
	check(base.name == "MoonBase", "Moon base loads")
	player = base.get_node("Astronaut")
	steps = player.get_node("Footsteps")
	check(music.player.get_instance_id() == music_id, "one music player persists through scene transfer")
	check(steps.surface_profile == "moon" and player.is_on_floor(), "Moon arrival selects lunar boot sounds")
	before = steps.step_count
	Input.action_press("front")
	await ticks(65)
	Input.action_release("front")
	check(steps.step_count > before and steps.last_surface == "moon", "actual lunar walking triggers lunar samples")
	var flag: Node3D = base.get_node("UniversityFlag")
	check(flag.get_meta("grounded", false), "flag placed on clear lunar ground")
	check(flag.global_position.distance_to(player.spawn_transform.origin) < 12, "flag is near the arrival path")
	check(flag.front.material_override.albedo_texture.resource_path == "res://assets/flags/kfupm_flag.png", "front uses supplied university image")
	check(flag.back.material_override.albedo_texture == flag.front.material_override.albedo_texture, "both sides use the exact same supplied image")
	var a: Array = flag.front.mesh.surface_get_arrays(0)
	var b: Array = flag.back.mesh.surface_get_arrays(0)
	check(a[Mesh.ARRAY_NORMAL][0].z > .9 and b[Mesh.ARRAY_NORMAL][0].z < -.9, "front and back normals face outward")
	check(a[Mesh.ARRAY_TEX_UV][0].x == 0 and b[Mesh.ARRAY_TEX_UV][0].x == 1, "reverse side UVs keep lettering readable")
	check(flag.has_node("TopSupport") and flag.has_node("PoleCollision"), "flag supported by crossbar and solid pole")
	key(KEY_M)
	await ticks(2)
	check(AudioServer.is_bus_mute(0), "M mutes all audio in Moon base")
	key(KEY_M)
	await ticks(2)
	check(not AudioServer.is_bus_mute(0), "M restores Moon-base audio")
	base.queue_free()
	await ticks(3)
	print("AUDIO / UNIVERSITY FLAG: ", failures, " failures")
	quit(0 if failures == 0 else 1)

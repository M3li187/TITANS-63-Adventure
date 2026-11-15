extends SceneTree
var main: Node3D
var player: CharacterBody3D
var mission: Node
var failures := 0

func _initialize() -> void: call_deferred("run")
func ticks(n: int) -> void:
	for i in n: await physics_frame
func check(ok: bool, what: String) -> void:
	if ok: print("PASS ", what)
	else:
		failures += 1
		push_error("FAIL " + what)
func release_keys() -> void:
	for key in ["front", "back", "left", "right", "sprint", "jump"]: Input.action_release(key)
func place(point := Vector3(0, .025, 1.5)) -> void:
	release_keys()
	player.position = point
	player.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO

func run() -> void:
	main = (load("res://Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await ticks(5)
	mission = main.get_node("LandingMission")
	player = main.get_node("Astronaut") as CharacterBody3D
	mission.ui.close_panel()
	await ticks(30)
	check(InputMap.action_get_events("sprint")[0].physical_keycode == KEY_SHIFT, "Shift binding")
	check(InputMap.action_get_events("jump")[0].physical_keycode == KEY_SPACE, "Space binding")
	for action in ["front", "back", "left", "right"]:
		place()
		await ticks(20)
		Input.action_press("sprint")
		Input.action_press(action)
		await ticks(12)
		var speed := Vector2(player.velocity.x, player.velocity.z).length()
		check(is_equal_approx(speed, 3.0), action + " + Shift runs at 3m/s")
		check(player.get("animation_player").current_animation == "run", "run animation " + action)
		Input.action_release("sprint")
		await ticks(3)
		check(is_equal_approx(Vector2(player.velocity.x, player.velocity.z).length(), 1.5), "release Shift resumes walking " + action)
		check(player.get("animation_player").current_animation == "Moon_Walk", "walking animation restored")
		release_keys()
	place()
	await ticks(20)
	Input.action_press("front")
	Input.action_press("right")
	Input.action_press("sprint")
	await ticks(5)
	check(is_equal_approx(Vector2(player.velocity.x, player.velocity.z).length(), 3.0), "diagonal run normalized")
	# Stand under normal rear-cabin headroom to observe a complete moon-gravity jump.
	place(Vector3(0, .025, 2.7))
	await ticks(30)
	check(player.is_on_floor(), "jump starts grounded")
	var ground := player.position.y
	Input.action_press("jump")
	await ticks(2)
	check(player.position.y > ground + .01 and player.velocity.y > 0, "Space launches jump")
	check(not player.is_on_floor(), "airborne after jump")
	var before := player.velocity.y
	Input.action_release("jump")
	await ticks(1)
	Input.action_press("jump")
	await ticks(2)
	check(player.velocity.y < before, "no double jump while airborne")
	var maximum := player.position.y
	for i in 180:
		await ticks(1)
		maximum = maxf(maximum, player.position.y)
	check(maximum > ground + .15 and maximum < ground + .65, "bounded moon-gravity jump arc")
	check(player.is_on_floor() and absf(player.position.y - ground) < .03, "lands back on deck")
	await ticks(30)
	check(player.is_on_floor() and absf(player.velocity.y) < .01, "holding Space does not bunny-hop")
	release_keys()
	mission.ui.open_panel()
	await ticks(2)
	var parked := player.position
	Input.action_press("front")
	Input.action_press("sprint")
	Input.action_press("jump")
	await ticks(5)
	check(player.position.distance_to(parked) < .005, "comms panel blocks running and jumping")
	release_keys()
	mission.ui.close_panel()
	await ticks(3)
	Input.action_press("jump")
	Input.action_press("front")
	Input.action_press("sprint")
	await ticks(4)
	check(player.velocity.y > 0 and is_equal_approx(Vector2(player.velocity.x, player.velocity.z).length(), 3.0), "running jump works")
	release_keys()
	print("RUN/JUMP RESULT: ", failures, " failures")
	main.queue_free()
	for i in 3: await process_frame
	quit(0 if failures == 0 else 1)

extends SceneTree
## End-to-end regression checks. Run with --headless --fixed-fps 60 --script.

var failures := 0
var player: CharacterBody3D
var cockpit: Node3D
var interaction: Node

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

func ticks(count: int) -> void:
	for i in count:
		await physics_frame

func place(position: Vector3, yaw: float = 0.0) -> void:
	player.position = position
	player.rotation.y = yaw
	player.velocity = Vector3.ZERO
	player.get_node("HeadPivot").rotation = Vector3.ZERO
	player.get_node("HeadPivot/Camera3D").position = Vector3.ZERO

func run() -> void:
	var packed := load("res://Main.tscn") as PackedScene
	check(packed != null, "main scene loads")
	var main := packed.instantiate()
	root.add_child(main)
	main.get_node("MissionDemo").set("enabled", false)
	player = main.get_node("Astronaut") as CharacterBody3D
	cockpit = main.get_node("Cockpit") as Node3D
	interaction = player.get_node("Interaction")
	await ticks(60)
	main.get_node("LandingMission").ui.close_panel()
	check(player.is_on_floor() and absf(player.position.y - 0.018) < 0.03, "safe spawn on bridge deck")
	check(player.get("head_bone") >= 0, "astronaut head tracking and animation connected")
	check(player.get_node("HeadPivot/Camera3D").current, "only player eye camera is active")
	check(cockpit.get("controls").size() == 77, "all 73 original controls retained, plus four mission targets")
	# Preserve the camera effects supplied with the astronaut.
	var eye_camera: Camera3D = player.get_node("HeadPivot/Camera3D")
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	Input.action_press("front")
	for i in 70:
		await ticks(1)
		low = low.min(eye_camera.position)
		high = high.max(eye_camera.position)
	Input.action_release("front")
	check(high.distance_to(low) > 0.002 and maxf(absf(low.y), absf(high.y)) <= 0.121, "animation-driven first-person bob is active and bounded")
	await ticks(100)
	check(eye_camera.position.length() < 0.002 and eye_camera.rotation.length() < 0.002, "first-person camera settles when standing still")
	for action in ["front", "back", "left", "right"]:
		place(Vector3(0, 0.025, 1.5))
		await ticks(3)
		var start := player.position
		Input.action_press(action)
		await ticks(20)
		var diff := player.position - start
		Input.action_release(action)
		await ticks(2)
		var expected: Vector3 = {"front": Vector3.FORWARD, "back": Vector3.BACK, "left": Vector3.LEFT, "right": Vector3.RIGHT}[action]
		check(diff.dot(expected) > 0.35, "WASD " + action)
	check(not (player.get("animation_player") as AnimationPlayer).is_playing(), "animation pauses when stopped")
	place(Vector3(0, 0.025, 1.5), PI / 2.0)
	await ticks(3)
	Input.action_press("front")
	await ticks(20)
	Input.action_release("front")
	check(player.position.x < -0.35, "walking follows viewing direction")
	# Wall, canopy, furniture: run into them through the actual controller.
	place(Vector3(0, 0.025, 1.5))
	Input.action_press("right")
	await ticks(180)
	Input.action_release("right")
	check(player.position.x < 2.5 and player.position.y < 0.1, "side wall and console stop the astronaut")
	place(Vector3(0, 0.025, -0.2))
	Input.action_press("front")
	await ticks(180)
	Input.action_release("front")
	check(player.position.z > -2.8, "pedestal/dashboard stop forward movement")
	place(Vector3(-1, 0.025, -0.2))
	Input.action_press("front")
	await ticks(100)
	Input.action_release("front")
	check(player.position.z > -1.9, "pilot seat collision")
	# Short, unobstructed rays against real interaction shapes.
	var hits := 0
	for id in ["DOOR_CONTROL", "DOOR_CONTROL_REAR", "LIFE_SUPPORT", "DASH_3", "THROTTLE_1", "MASTER_CAUTION"]:
		var control: Node3D = cockpit.call("get_control", id)
		var origin := control.global_position + control.global_basis.z * 0.5
		var hit: Object = interaction.call("pick_ray", origin, -control.global_basis.z)
		if hit == control:
			hits += 1
		else:
			print("MISSED control ", id, " hit ", hit)
	check(hits == 6, "ray-pick switches, screens, lever and door from close range")
	var door_control: Node3D = cockpit.call("get_control", "DOOR_CONTROL")
	var out_of_range: Object = interaction.call("pick_ray", door_control.global_position + Vector3(0, 0, -3), Vector3.BACK)
	check(out_of_range != door_control, "cannot activate distant controls")
	# E key activates the door through the camera's center ray.
	place(Vector3(0.85, 0.025, 2.85), PI)
	await ticks(3)
	var camera: Camera3D = player.get_node("HeadPivot/Camera3D")
	var direction := door_control.global_position - camera.global_position
	player.rotation.y = atan2(-direction.x, -direction.z)
	player.get_node("HeadPivot").rotation.x = atan2(direction.y, Vector2(direction.x, direction.z).length())
	await ticks(2)
	var input := InputEventAction.new()
	input.action = "interact"
	input.pressed = true
	Input.parse_input_event(input)
	await ticks(3)
	check(cockpit.get("_door_open"), "E activates bridge door from player camera")
	input.pressed = false
	Input.parse_input_event(input)
	# First click after Escape recaptures; a later click operates the switch.
	player.call("set_mouse_look", false)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	await ticks(3)
	check(player.get("mouse_look_active") and cockpit.get("_door_open"), "click resumes look without accidentally activating a control")
	click.pressed = false
	Input.parse_input_event(click)
	await ticks(2)
	click.pressed = true
	Input.parse_input_event(click)
	await ticks(3)
	check(not cockpit.get("_door_open"), "left click operates the aimed control")
	click.pressed = false
	Input.parse_input_event(click)
	await ticks(55)
	# Door closed stops passage; open door lets the player walk through.
	place(Vector3(0, 0.025, 3.1), PI)
	await ticks(3)
	cockpit.call("set_door_open", false)
	await ticks(55)
	Input.action_press("front")
	await ticks(80)
	Input.action_release("front")
	check(player.position.z < 3.97, "closed moving door has solid collision")
	place(Vector3(0, 0.025, 3.1), PI)
	cockpit.call("set_door_open", true)
	await ticks(55)
	Input.action_press("front")
	await ticks(100)
	Input.action_release("front")
	check(player.position.z > 4.8 and player.position.z < 6.0 and player.is_on_floor(), "open doorway is walkable into corridor")
	# Operate the return-side switch from the corridor.
	place(Vector3(0, 0.025, 5.4))
	await ticks(3)
	var rear_switch: Node3D = cockpit.call("get_control", "DOOR_CONTROL_REAR")
	var to_switch := rear_switch.global_position - camera.global_position
	player.rotation.y = atan2(-to_switch.x, -to_switch.z)
	player.get_node("HeadPivot").rotation.x = atan2(to_switch.y, Vector2(to_switch.x, to_switch.z).length())
	await ticks(2)
	input.pressed = true
	Input.parse_input_event(input)
	await ticks(3)
	check(not cockpit.get("_door_open"), "corridor switch closes the bridge door")
	input.pressed = false
	Input.parse_input_event(input)
	await ticks(55)
	input.pressed = true
	Input.parse_input_event(input)
	await ticks(3)
	check(cockpit.get("_door_open"), "corridor switch opens the bridge door for return")
	input.pressed = false
	Input.parse_input_event(input)
	await ticks(55)
	place(Vector3(0, 0.025, 4.25))
	cockpit.call("set_door_open", false)
	check(cockpit.get("_door_open"), "door refuses to close on astronaut")
	# Collision also blocks use through a closed door.
	place(Vector3(0, 0.025, 5.5))
	cockpit.call("set_door_open", false)
	await ticks(55)
	var ray_origin := Vector3(0, 1.2, 4.65)
	var obscured: Object = interaction.call("pick_ray", ray_origin, Vector3.FORWARD)
	check(obscured == null, "solid doorway occludes interaction rays")
	# Existing mission logic still responds to real control activation.
	var mission: Node = main.get_node("MissionDemo")
	mission.set("enabled", true)
	mission.set("start_delay", 0.0)
	await ticks(3)
	check(mission.get("_stage") == 1, "O2 training mission starts")
	cockpit.call("get_control", "LIFE_SUPPORT").activate()
	await ticks(2)
	check(mission.get("_stage") == 2, "life support backup resolves O2 alert")
	cockpit.call("get_control", "MASTER_CAUTION").activate()
	check(mission.get("_stage") == 3, "master caution completes mission")
	player.call("reset_to_spawn")
	await ticks(5)
	check(player.position.distance_to(Vector3(0, 0.018, 2.6)) < 0.05, "R reset returns safely to entry")
	print("BRIDGE INTEGRATION RESULT: ", failures, " failures")
	quit(0 if failures == 0 else 1)

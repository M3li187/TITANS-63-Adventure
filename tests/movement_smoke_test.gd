extends SceneTree

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var packed := load("res://mars.tscn") as PackedScene
	assert(packed != null, "Main scene loads")
	var scene := packed.instantiate()
	root.add_child(scene)
	var player := scene.get_node("asronat") as CharacterBody3D
	assert(player != null, "Player uses CharacterBody3D")
	for i in range(90):
		await physics_frame
	assert(player.is_on_floor(), "Player lands on floor")
	assert(absf(player.position.y) < 0.1, "No oversized floor collider")
	var anim := player.get("animation_player") as AnimationPlayer
	assert(anim != null and anim.has_animation("Moon_Walk"), "Animation wired")
	for action in ["front", "back", "left", "right"]:
		var start := player.position
		Input.action_press(action)
		for i in range(30):
			await physics_frame
		var motion := player.position - start
		assert(anim.is_playing(), "Moving plays animation")
		match action:
			"front": assert(motion.z < -0.6)
			"back": assert(motion.z > 0.6)
			"left": assert(motion.x < -0.6)
			"right": assert(motion.x > 0.6)
		Input.action_release(action)
		for i in range(2):
			await physics_frame
		assert(not anim.is_playing(), "Idle pauses animation")
		var idle := player.position
		for i in range(10):
			await physics_frame
		assert(player.position.distance_to(idle) < 0.01, "Idle is stationary")
		print("PASS ", action, " motion=", motion)
	Input.action_press("front")
	Input.action_press("right")
	for i in range(5):
		await physics_frame
	var planar_speed := Vector2(player.velocity.x, player.velocity.z).length()
	assert(absf(planar_speed - 1.5) < 0.01, "Diagonal normalized")
	Input.action_release("front")
	Input.action_release("right")
	print("PASS diagonal speed, floor collision, animation start/stop, idle")
	for i in range(5):
		await physics_frame
	var camera := player.get_node("HeadPivot/Camera3D") as Camera3D
	assert(camera.current and is_equal_approx(camera.get_parent().position.y, 1.65), "Eye level camera")
	assert(camera.cull_mask & 2 == 0, "Local body hidden from camera")
	var skeleton := player.get("head_skeleton") as Skeleton3D
	assert(skeleton != null and int(player.get("head_bone")) >= 0, "Head bone found")
	Input.action_press("front")
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	for i in range(90):
		await physics_frame
		minimum = minimum.min(camera.position)
		maximum = maximum.max(camera.position)
	assert(maximum.distance_to(minimum) > 0.001, "Camera follows animated head")
	assert(absf(maximum.y) <= 0.121 and absf(minimum.y) <= 0.121, "Head motion bounded")
	Input.action_release("front")
	for i in range(120):
		await physics_frame
	assert(camera.position.length() < 0.002, "Camera settles at idle")
	assert(camera.rotation.length() < 0.002, "Camera tilt settles at idle")
	player.rotation.y = PI / 2.0
	var turn_start := player.position
	Input.action_press("front")
	for i in range(30):
		await physics_frame
	Input.action_release("front")
	assert(player.position.x < turn_start.x - 0.6, "W follows viewing yaw")
	var before_pitch: float = player.get_node("HeadPivot").rotation.x
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(10, 10)
	player.call("apply_mouse_look", mouse.relative)
	assert(player.get_node("HeadPivot").rotation.x < before_pitch, "Mouse look")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	player.call("_unhandled_input", escape)
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Escape releases cursor")
	print("PASS eye height, head tracking, bounded bob, idle settling, camera-relative movement, mouse look, cursor release")
	quit(0)

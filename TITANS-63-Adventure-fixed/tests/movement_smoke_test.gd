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
	quit(0)

extends Node3D
## Moon base from the available Part 1 scene; uses the current sprint/jump player.
var player: CharacterBody3D
var _steps: AudioStreamPlayer
var _step_clock := 0.0

func _ready() -> void:
	var environment: Environment = $WorldEnvironment.environment
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	player = $Astronaut
	player.set_physics_process(false)
	player.fall_reset_y = -35.0
	# Bake the scene's scaled primitive collision shapes into their dimensions.
	for node in find_children("*", "CollisionShape3D", true, false):
		var collider := node as CollisionShape3D
		var scale := collider.transform.basis.get_scale()
		if scale.is_equal_approx(Vector3.ONE): continue
		if collider.shape is BoxShape3D:
			var box := collider.shape.duplicate() as BoxShape3D
			box.size *= scale.abs()
			collider.shape = box
		elif collider.shape is SphereShape3D:
			var sphere := SphereMesh.new()
			sphere.radius = collider.shape.radius
			sphere.height = collider.shape.radius * 2
			sphere.radial_segments = 16
			sphere.rings = 8
			var points: PackedVector3Array = sphere.get_mesh_arrays()[Mesh.ARRAY_VERTEX]
			for i in points.size(): points[i] *= scale
			var convex := ConvexPolygonShape3D.new()
			convex.points = points
			collider.shape = convex
		collider.transform.basis = collider.transform.basis.orthonormalized()
	_steps = AudioStreamPlayer.new()
	_steps.stream = load("res://assets/audio/step.wav")
	_steps.volume_db = -18
	add_child(_steps)
	_build_hud()
	call_deferred("_place_player")

func _place_player() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var capsule: Shape3D = player.get_node("CollisionShape3D").shape
	var placed := false
	for point in [Vector2(9.5, -29), Vector2(12, -29), Vector2(10, -25), Vector2(20, 10)]:
		var q := PhysicsRayQueryParameters3D.create(Vector3(point.x, 100, point.y), Vector3(point.x, -30, point.y), 1)
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty() or hit.normal.y < 0.65: continue
		var foot: Vector3 = hit.position + Vector3.UP * 0.06
		var test := PhysicsShapeQueryParameters3D.new()
		test.shape = capsule
		test.transform = Transform3D(Basis(), foot + Vector3.UP * 0.9)
		test.collision_mask = 1
		test.exclude = [player.get_rid()]
		if not space.intersect_shape(test, 1).is_empty(): continue
		player.global_transform = Transform3D(Basis(Vector3.UP, PI), foot)
		placed = true
		break
	if not placed:
		push_error("Moon-base spawn could not find clear ground.")
	player.velocity = Vector3.ZERO
	player.spawn_transform = player.global_transform
	player.set_mouse_look(true)
	player.set_physics_process(true)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.position = Vector2(28, 24)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color("71e9e0"))
	label.text = "SECRET AREA UNLOCKED / MOON BASE\nExplore the colony · WASD move · Shift run · Space jump · R return to arrival"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)

func _process(delta: float) -> void:
	if player == null: return
	var motion := player.get_real_velocity()
	if player.is_on_floor() and Vector2(motion.x, motion.z).length() > 0.1:
		_step_clock += delta * Vector2(motion.x, motion.z).length()
		if _step_clock > .95 and DisplayServer.get_name() != "headless":
			_step_clock = 0
			_steps.play()
	else: _step_clock = .5

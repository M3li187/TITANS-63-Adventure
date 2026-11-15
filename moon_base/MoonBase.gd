extends Node3D
## Moon base from the available Part 1 scene; uses the current sprint/jump player.
var player: CharacterBody3D

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
	player.get_node("Footsteps").surface_profile = "moon"
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
	_place_flag()

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.position = Vector2(28, 24)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color("71e9e0"))
	label.text = "SECRET AREA UNLOCKED / MOON BASE\nExplore the colony · WASD move · Shift run · Space jump · R return to arrival\nN music on/off · M mute all audio"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)


func _place_flag() -> void:
	# Place beside the arrival path on clear measured collision ground, not a roof.
	var flag: Node3D = $UniversityFlag
	var space := get_world_3d().direct_space_state
	var spawn: Vector3 = player.spawn_transform.origin
	for offset in [Vector2(4, 6), Vector2(-4, 6), Vector2(4, 3), Vector2(6, 6)]:
		var point: Vector2 = Vector2(spawn.x, spawn.z) + offset
		var ray := PhysicsRayQueryParameters3D.create(Vector3(point.x, spawn.y + 4, point.y), Vector3(point.x, spawn.y - 5, point.y), 1)
		ray.exclude = [player.get_rid(), flag.get_node("PoleCollision").get_rid()]
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or hit.normal.y < .8 or absf(hit.position.y - spawn.y) > 1.0: continue
		var clearance := PhysicsShapeQueryParameters3D.new()
		var volume := BoxShape3D.new()
		volume.size = Vector3(3.0, 4.0, .7)
		clearance.shape = volume
		clearance.transform = Transform3D(Basis(), hit.position + Vector3(1.1, 2.08, 0))
		clearance.collision_mask = 1
		clearance.exclude = [player.get_rid(), flag.get_node("PoleCollision").get_rid()]
		if not space.intersect_shape(clearance, 1).is_empty(): continue
		flag.global_position = hit.position + Vector3.UP * .015
		flag.set_meta("grounded", true)
		return
	push_warning("Flag could not find clear ground beside the arrival; using the ground below its authored location.")
	var fallback := PhysicsRayQueryParameters3D.create(flag.position + Vector3.UP * 50, flag.position + Vector3.DOWN * 50, 1)
	fallback.exclude = [flag.get_node("PoleCollision").get_rid(), player.get_rid()]
	var ground := space.intersect_ray(fallback)
	if not ground.is_empty():
		flag.global_position = ground.position + Vector3.UP * .015
		flag.set_meta("grounded", true)

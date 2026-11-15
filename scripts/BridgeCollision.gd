extends RefCounted
## One-time static collision built from the same geometry as the bridge.
## The closed canopy, seats, consoles and walls all obstruct the player/rays.

static func setup(cockpit: Node3D) -> void:
	for mesh_name in ["InteriorMesh", "CanopyGlass"]:
		var mesh := cockpit.get_node(mesh_name) as MeshInstance3D
		var body := StaticBody3D.new()
		body.name = mesh_name + "Collision"
		body.collision_layer = 1
		body.collision_mask = 2
		var shape := CollisionShape3D.new()
		var triangles := mesh.mesh.create_trimesh_shape()
		triangles.backface_collision = true
		shape.shape = triangles
		body.add_child(shape)
		cockpit.add_child(body)
	# A level collision deck covers tiny grooves/bolts in the visual floor.
	_add_box(cockpit, "SmoothDeck", Vector3(0, -0.032, 0.35), Vector3(5.15, 0.1, 7.7))
	_add_box(cockpit, "CorridorDeck", Vector3(0, -0.032, 5.65), Vector3(1.9, 0.1, 2.9))
	for door_name in ["DoorHalf_L", "DoorHalf_R"]:
		var door := cockpit.get_node(door_name) as AnimatableBody3D
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.75, 2.2, 0.085)
		shape.shape = box
		shape.position.y = 1.1
		door.add_child(shape)


static func _add_box(root: Node3D, body_name: String, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = body_name
	body.position = center
	body.collision_layer = 1
	body.collision_mask = 2
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	body.add_child(collider)
	root.add_child(body)

extends SceneTree
## Check that key controls can be reached from standing positions connected
## to the player's spawn, accounting for the full capsule and solid geometry.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene := (load("res://Main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	scene.get_node("MissionDemo").set("enabled", false)
	var player := scene.get_node("Astronaut") as CharacterBody3D
	var cockpit: Node3D = scene.get_node("Cockpit")
	var interaction: Node = player.get_node("Interaction")
	for i in 5:
		await physics_frame
	scene.get_node("LandingMission").ui.close_panel()
	var space := player.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = player.get_node("CollisionShape3D").shape
	query.collision_mask = 1
	var free := {}
	var spawn_cell := Vector2i(0, 13)
	for x in range(-12, 13):
		for z in range(-17, 22):
			var cell := Vector2i(x, z)
			var point := Vector3(x * 0.2, 0.94, z * 0.2)
			query.transform = Transform3D(Basis(), point)
			if space.intersect_shape(query, 1).is_empty():
				free[cell] = true
	var visited := {spawn_cell: true}
	var queue: Array[Vector2i] = [spawn_cell]
	var index := 0
	while index < queue.size():
		var cell := queue[index]
		index += 1
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + offset
			if free.has(next) and not visited.has(next):
				visited[next] = true
				queue.append(next)
	var reachable := []
	var missing := []
	for id in cockpit.call("list_controls"):
		if id == "DOOR_CONTROL_REAR":
			continue # Closed door intentionally separates the corridor.
		var control: Node3D = cockpit.call("get_control", id)
		var can_reach := false
		for cell in queue:
			var eye := Vector3(cell.x * 0.2, 1.69, cell.y * 0.2)
			var direction := control.global_position - eye
			if direction.length() > float(interaction.get("reach")):
				continue
			if interaction.call("pick_ray", eye, direction) == control:
				can_reach = true
				break
		if can_reach:
			reachable.append(id)
		else:
			missing.append(id)
	print("Accessible standing cells: ", queue.size())
	print("Reachable controls: ", reachable.size(), "/", cockpit.list_controls().size() - 1, "; unavailable: ", missing)
	var failures := 0
	for id in missing:
		if id in missing:
			push_error("Essential control inaccessible: " + id)
			failures += 1
	quit(0 if failures == 0 else 1)

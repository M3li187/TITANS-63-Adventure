extends Node3D
## Real LROC Fra Mauro crop, with authored background/rocks for the branching game.
var metadata: Dictionary
var heights := PackedFloat32Array()
var slopes := PackedFloat32Array()
var terrain_root: Node3D
var altitude_m := 140.0
var landing_target := Vector2.ZERO
var stage := 0
var _flight: Tween
var _lights: Array[SpotLight3D] = []
var _raster_size := 513
var _spacing := 2.0
var clear_target := Vector2.ZERO

func _ready() -> void:
	metadata = JSON.parse_string(FileAccess.get_file_as_string("res://assets/moon/terrain_metadata.json"))
	heights = FileAccess.get_file_as_bytes("res://assets/moon/fra_mauro_heights.f32").to_float32_array()
	slopes = FileAccess.get_file_as_bytes("res://assets/moon/fra_mauro_slopes.f32").to_float32_array()
	_spacing = float(metadata["sample_spacing_m"])
	var clear: Array = metadata["clear_zone_local_xz_m"]
	clear_target = Vector2(float(clear[0]), float(clear[1]))
	terrain_root = Node3D.new()
	terrain_root.name = "LROC_FraMauro_Crop"
	add_child(terrain_root)
	_build_measured_terrain()
	_build_background()
	_build_rocks()
	_build_landing_lights()
	var cockpit := get_node("../Cockpit")
	var env: Dictionary = cockpit.get("_env")
	if env.has("planet"):
		env["planet"].scale = Vector3.ONE * 0.09
		env["planet"].position = Vector3(-400, 350, -2200)
	if env.has("moon"):
		env["moon"].visible = false

func elevation(x: float, z: float) -> float:
	var ix := clampi(roundi(x / _spacing) + 256, 0, 512)
	var iz := clampi(roundi(z / _spacing) + 256, 0, 512)
	return heights[iz * _raster_size + ix]

func _build_measured_terrain() -> void:
	# Display a 4m mesh sampled from the bundled 2m crop; keep the full data intact.
	var n := 257
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in n:
		for col in n:
			var x := (col * 2 - 256) * _spacing
			var z := (row * 2 - 256) * _spacing
			vertices.append(Vector3(x, elevation(x, z), z))
			normals.append(Vector3(elevation(x - 2, z) - elevation(x + 2, z), 4.0, elevation(x, z - 2) - elevation(x, z + 2)).normalized())
			uvs.append(Vector2(float(col) / (n - 1), float(row) / (n - 1)))
	for row in n - 1:
		for col in n - 1:
			var a := row * n + col
			indices.append_array(PackedInt32Array([a, a + 1, a + n, a + 1, a + n + 1, a + n]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = "MeasuredTerrain_4mDisplay"
	instance.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/lunar_surface.gdshader")
	mat.set_shader_parameter("survey", load("res://assets/moon/fra_mauro_ortho.png"))
	mat.set_shader_parameter("grain", load("res://assets/moon/user_moon_surface.jpg"))
	instance.material_override = mat
	terrain_root.add_child(instance)

func _build_background() -> void:
	# A broad, clearly documented procedural extension beyond the measured crop.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.23, 0.22, 0.20)
	mat.roughness = 1.0
	var noise := FastNoiseLite.new()
	noise.seed = 140
	noise.frequency = 0.003
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(-4000, 4000, 125):
		for x in range(-4000, 4000, 125):
			if x >= -625 and x < 625 and z >= -625 and z < 625:
				continue
			var points: Array[Vector3] = []
			for offset in [Vector2(0, 0), Vector2(125, 0), Vector2(0, 125), Vector2(125, 125)]:
				var xx: float = x + offset.x
				var zz: float = z + offset.y
				points.append(Vector3(xx, -25.0 + noise.get_noise_2d(xx, zz) * 14.0 - (xx * xx + zz * zz) / 3500000.0, zz))
			for i in [0, 1, 2, 1, 3, 2]:
				surface.add_vertex(points[i])
	surface.generate_normals()
	var instance := MeshInstance3D.new()
	instance.mesh = surface.commit()
	instance.material_override = mat
	terrain_root.add_child(instance)
	# An underlay closes the visual join under the real cropped terrain edges.
	var plane := MeshInstance3D.new()
	var p := PlaneMesh.new()
	p.size = Vector2(1500, 1500)
	plane.mesh = p
	plane.position.y = -45.0
	plane.material_override = mat
	terrain_root.add_child(plane)

func _build_rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1403
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/lunar_rock.gdshader")
	for i in 30:
		var point := Vector2(rng.randf_range(-65, 25), rng.randf_range(-100, -18))
		if point.distance_to(clear_target) < 22.0:
			continue
		var radius := rng.randf_range(0.7, 3.0)
		# Authored hazard cluster around the unsafe landing target (-5, -40).
		if i < 3:
			point = [Vector2(-1, -42), Vector2(-9, -43), Vector2(-3, -47)][i]
			radius = 1.8 + float(i) * .25
		var rock := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = radius
		sphere.height = radius * 1.4
		sphere.radial_segments = 10
		sphere.rings = 5
		rock.mesh = sphere
		rock.material_override = mat
		rock.position = Vector3(point.x, elevation(point.x, point.y) + radius * 0.35, point.y)
		rock.rotation = Vector3(rng.randf(), rng.randf() * TAU, rng.randf())
		terrain_root.add_child(rock)

func _build_landing_lights() -> void:
	for x in [-2.0, 2.0]:
		var light := SpotLight3D.new()
		light.position = Vector3(x, 0.4, -3.7)
		light.rotation.x = -0.5
		light.spot_range = 120.0
		light.spot_angle = 40.0
		light.light_energy = 8.0
		light.light_color = Color(1.0, 0.94, 0.78)
		light.visible = false
		add_child(light)
		_lights.append(light)

func set_landing_lights(enabled: bool) -> void:
	for light in _lights:
		light.visible = enabled

func set_stage(value: int) -> void:
	stage = value
	if _flight != null:
		_flight.kill()
	_flight = create_tween()
	_flight.tween_property(self, "altitude_m", [140.0, 75.0, 24.0][clampi(value, 0, 2)], 3.0).set_trans(Tween.TRANS_SINE)

func fly_landing(clear_area: bool, done: Callable, touchdown_allowed: bool = true) -> void:
	if _flight != null:
		_flight.kill()
	var target := clear_target if clear_area else Vector2(-5, -40)
	_flight = create_tween().set_parallel(true)
	_flight.tween_property(self, "landing_target", target, 7.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_flight.tween_property(self, "altitude_m", 1.0 if touchdown_allowed else 8.0, 9.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_flight.chain().tween_callback(done)

func fly_abort(done: Callable) -> void:
	if _flight != null:
		_flight.kill()
	_flight = create_tween()
	_flight.tween_property(self, "altitude_m", 350.0, 5.0).set_trans(Tween.TRANS_SINE)
	_flight.tween_callback(done)

func reset_flight() -> void:
	if _flight != null:
		_flight.kill()
	altitude_m = 140.0
	landing_target = Vector2.ZERO
	set_landing_lights(false)

func _process(_delta: float) -> void:
	if terrain_root != null:
		terrain_root.position = Vector3(-landing_target.x, -altitude_m - elevation(landing_target.x, landing_target.y), -landing_target.y)

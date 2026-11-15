@tool
extends Node3D
## A supported lunar flag with two separately UV-mapped, readable faces.
## Fixed folds and a top crossbar: no wind animation on the Moon.
const IMAGE = preload("res://assets/flags/kfupm_flag.png")
const WIDTH := 2.4
const HEIGHT := 1.6
const TOP := 3.45
var front: MeshInstance3D
var back: MeshInstance3D

func _ready() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(.62, .67, .71)
	metal.metallic = .75
	metal.roughness = .35
	_cylinder("Pole", .032, 3.7, Vector3(0, 1.85, 0), metal)
	var support := _cylinder("TopSupport", .016, WIDTH + .08, Vector3(WIDTH * .5, TOP + .025, 0), metal)
	support.rotation.z = PI * .5
	_cylinder("Footplate", .18, .07, Vector3(0, .035, 0), metal)
	var finial := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = .065
	sphere.height = .13
	finial.mesh = sphere
	finial.material_override = metal
	finial.position.y = 3.72
	add_child(finial)
	front = _face(false)
	front.name = "FrontImage"
	back = _face(true)
	back.name = "BackImage"
	var body := StaticBody3D.new()
	body.name = "PoleCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = .055
	shape.height = 3.7
	collider.shape = shape
	collider.position.y = 1.85
	body.add_child(collider)
	add_child(body)

func _cylinder(label: String, radius: float, length: float, at: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 16
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	add_child(instance)
	return instance

func _face(reverse: bool) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 36
	var rows := 20
	for y in rows + 1:
		for x in cols + 1:
			var u := float(x) / cols
			var v := float(y) / rows
			var fold := .065 * u * v * sin(u * TAU * 1.5 + v * 2.0)
			surface.set_uv(Vector2(1.0 - u if reverse else u, v))
			surface.add_vertex(Vector3(.045 + u * WIDTH, TOP - v * HEIGHT, fold + (-.004 if reverse else .004)))
	for y in rows:
		for x in cols:
			var a := y * (cols + 1) + x
			# Godot uses clockwise front-face winding; the two surfaces face out.
			var indices := [a, a + 1, a + cols + 1, a + 1, a + cols + 2, a + cols + 1]
			if reverse: indices.reverse()
			for index in indices: surface.add_index(index)
	surface.generate_normals()
	var instance := MeshInstance3D.new()
	instance.mesh = surface.commit()
	var fabric := StandardMaterial3D.new()
	fabric.albedo_texture = IMAGE
	fabric.albedo_color = Color.WHITE
	fabric.roughness = 1
	fabric.metallic_specular = .15
	fabric.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# Modest emission preserves the supplied green/white artwork in lunar shadows.
	fabric.emission_enabled = true
	fabric.emission_texture = IMAGE
	fabric.emission = Color.WHITE
	fabric.emission_energy_multiplier = .23
	instance.material_override = fabric
	add_child(instance)
	return instance

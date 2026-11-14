extends CharacterBody3D

@export var move_speed: float = 1.5
@export var moon_gravity: float = 1.62
@export var walk_animation: StringName = &"Moon_Walk"

# Set Camera Motion Strength to 0 for a steady first-person view.
@export_range(0.0, 1.0) var camera_motion_strength: float = 0.35
@export var camera_smoothing: float = 7.0
@export var mouse_sensitivity: float = 0.0025

@onready var head_pivot: Node3D = $HeadPivot
@onready var camera: Camera3D = $HeadPivot/Camera3D
var head_skeleton: Skeleton3D
var head_bone: int = -1
var head_center := Vector3.ZERO

@onready var model: Node3D = $astronaut_moon_walk
var animation_player: AnimationPlayer
var was_moving: bool = false


func _ready() -> void:
	setup_first_person()
	# Find the AnimationPlayer inside the imported GLB automatically.
	animation_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation_player == null:
		push_error("The astronaut model has no AnimationPlayer.")
		return
	if not animation_player.has_animation(walk_animation):
		push_error("Missing astronaut animation: " + str(walk_animation))
		return
	animation_player.get_animation(walk_animation).loop_mode = Animation.LOOP_LINEAR
	animation_player.stop()
	if animation_player.has_animation(&"RESET"):
		animation_player.play(&"RESET")
		animation_player.advance(0.0)
		animation_player.stop(true)


func _physics_process(delta: float) -> void:
	# W: -Z, S: +Z, A: -X, D: +X. Diagonals keep the same speed.
	var input_direction := Input.get_vector("left", "right", "front", "back")
	var direction := global_basis * Vector3(input_direction.x, 0.0, input_direction.y)
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	if not is_on_floor():
		velocity.y -= moon_gravity * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	update_animation(not input_direction.is_zero_approx())


func update_animation(is_moving: bool) -> void:
	if animation_player == null or not animation_player.has_animation(walk_animation):
		return
	if is_moving == was_moving:
		return
	was_moving = is_moving
	if is_moving:
		animation_player.play(walk_animation)
	else:
		animation_player.pause()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		apply_mouse_look(motion.relative)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	var target_offset := Vector3.ZERO
	var target_tilt := Vector3.ZERO
	var blend := 1.0 - exp(-camera_smoothing * delta)
	if head_skeleton != null and head_bone >= 0:
		var head_pose := head_skeleton.get_bone_global_pose(head_bone)
		var head_position := to_local(head_skeleton.to_global(head_pose.origin))
		# Remove slow animation drift; keep the floating step motion.
		head_center = head_center.lerp(head_position, 1.0 - exp(-2.0 * delta))
		if was_moving:
			var offset := (head_position - head_center) * camera_motion_strength
			target_offset = Vector3(
				clampf(offset.x, -0.045, 0.045),
				clampf(offset.y, -0.12, 0.12),
				clampf(offset.z, -0.025, 0.025)
			)
	# Small leaning motion when strafing or moving forward/backward.
	if was_moving:
		var movement := Input.get_vector("left", "right", "front", "back")
		target_tilt.x = deg_to_rad(0.6) * movement.y * camera_motion_strength
		target_tilt.z = -deg_to_rad(2.0) * movement.x * camera_motion_strength
	camera.position = camera.position.lerp(target_offset, blend)
	camera.rotation = camera.rotation.lerp(target_tilt, blend)


func setup_first_person() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# The camera cannot see inside the astronaut's own helmet/body.
	# Keep the model on layer 2 so it remains available to other cameras.
	for node in model.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		geometry.layers = (geometry.layers | 2) & ~1
	camera.cull_mask = camera.cull_mask & ~2
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		head_skeleton = skeletons[0] as Skeleton3D
		head_bone = head_skeleton.find_bone("Head")
		if head_bone >= 0:
			var pose := head_skeleton.get_bone_global_pose(head_bone)
			head_center = to_local(head_skeleton.to_global(pose.origin))


func apply_mouse_look(relative: Vector2) -> void:
	rotate_y(-relative.x * mouse_sensitivity)
	head_pivot.rotation.x = clampf(
		head_pivot.rotation.x - relative.y * mouse_sensitivity,
		deg_to_rad(-80.0), deg_to_rad(80.0)
	)

extends CharacterBody3D

@export var move_speed: float = 1.5
@export var moon_gravity: float = 1.62
@export var walk_animation: StringName = &"Moon_Walk"

@onready var model: Node3D = $astronaut_moon_walk
var animation_player: AnimationPlayer
var was_moving: bool = false


func _ready() -> void:
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
	velocity.x = input_direction.x * move_speed
	velocity.z = input_direction.y * move_speed
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

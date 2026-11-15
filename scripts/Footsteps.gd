extends Node
## Distance-based boot contacts: no steps when airborne, blocked or in menus.
signal step_played(surface: String, variant: int)
@export_enum("bridge", "moon") var surface_profile := "bridge"
@export var bridge_volume_db := -8.0
@export var moon_volume_db := -9.0
var step_count := 0
var last_variant := -1
var last_surface := ""
var _distance := 0.0
var _was_moving := false
var _was_grounded := false
var _air_time := 0.0
var _channels: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _next_channel := 0
@onready var player: CharacterBody3D = get_parent()

func _ready() -> void:
	for profile in ["bridge", "moon"]:
		var variants: Array[AudioStream] = []
		for i in 3:
			variants.append(load("res://assets/audio/footstep_%s_%d.wav" % [profile, i + 1]))
		_streams[profile] = variants
	for i in 3:
		var channel := AudioStreamPlayer.new()
		channel.bus = &"Footsteps"
		add_child(channel)
		_channels.append(channel)

func _physics_process(delta: float) -> void:
	if not player.is_physics_processing() or not player.mouse_look_active or player.input_locked:
		_distance = 0
		_was_moving = false
		_was_grounded = player.is_on_floor()
		_air_time = 0
		return
	var grounded := player.is_on_floor()
	if not grounded:
		_air_time += delta
		_was_grounded = false
		_was_moving = false
		_distance = 0
		return
	var landed := not _was_grounded and _air_time > .15
	_was_grounded = true
	_air_time = 0
	var velocity := player.get_real_velocity()
	var speed := Vector2(velocity.x, velocity.z).length()
	if landed:
		_play_step(-1.0)
		_distance = 0
	if speed < .15:
		_distance = 0
		_was_moving = false
		return
	var stride := (1.38 if player.is_running else .92) if surface_profile == "moon" else (1.15 if player.is_running else .78)
	if not _was_moving and not landed: _distance = stride * .72
	_was_moving = true
	_distance += speed * delta
	if _distance >= stride:
		_distance = fmod(_distance, stride)
		_play_step()

func _play_step(extra_db: float = 0.0) -> void:
	var profile := surface_profile if _streams.has(surface_profile) else "bridge"
	var variant := step_count % 3
	var channel := _channels[_next_channel]
	_next_channel = (_next_channel + 1) % _channels.size()
	channel.stream = _streams[profile][variant]
	channel.volume_db = (moon_volume_db if profile == "moon" else bridge_volume_db) + extra_db
	var flight := get_tree().current_scene.get_node_or_null("FlightAudio") if get_tree().current_scene != null else null
	if flight != null and flight.speaking(): channel.volume_db -= 3
	channel.pitch_scale = [.97, 1.02, 1.0][variant] + (.035 if player.is_running else 0.0)
	last_variant = variant
	last_surface = profile
	step_count += 1
	# Headless tests still exercise timing and stream selection without a decoder.
	if DisplayServer.get_name() != "headless": channel.play()
	step_played.emit(profile, variant)

func _exit_tree() -> void:
	for channel in _channels:
		channel.stop()
		channel.stream = null
	_streams.clear()

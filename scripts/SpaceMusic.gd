extends Node
## Persistent quiet score; crosses scenes without restarting or overlapping.
var player: AudioStreamPlayer
var music_enabled := true
var target_volume_db := -14.0
var _headless := false
var _flight: Node

func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	player = AudioStreamPlayer.new()
	player.name = "FraMauroStillness"
	player.bus = &"Music"
	var stream := load("res://assets/audio/music/fra_mauro_stillness.ogg") as AudioStreamOggVorbis
	stream.loop = true
	stream.loop_offset = 0
	player.stream = stream
	player.volume_db = target_volume_db
	add_child(player)
	if not _headless: player.play()

func toggle_music() -> void:
	music_enabled = not music_enabled
	player.stream_paused = not music_enabled

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_N:
			toggle_music()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_M:
			var scene := get_tree().current_scene
			# The bridge already owns M; retain the same master mute outdoors.
			if scene != null and not scene.has_node("FlightAudio"):
				AudioServer.set_bus_mute(0, not AudioServer.is_bus_mute(0))
				get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	var scene := get_tree().current_scene
	if scene == null: return
	if not is_instance_valid(_flight) or _flight.get_parent() != scene:
		_flight = scene.get_node_or_null("FlightAudio")
	var talking: bool = is_instance_valid(_flight) and _flight.speaking()
	var desired := target_volume_db - (9.0 if talking else 0.0)
	player.volume_db = lerpf(player.volume_db, desired, 1.0 - exp(-delta * (4.0 if talking else 1.2)))

func _exit_tree() -> void:
	if is_instance_valid(player):
		player.stop()
		player.stream = null

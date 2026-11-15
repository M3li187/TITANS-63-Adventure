extends Node
## Offline narration and original synthesized cabin audio. No vacuum "wind".
signal speech_started(text: String)
signal speech_finished

var voice: AudioStreamPlayer3D
var air: AudioStreamPlayer
var engine: AudioStreamPlayer
var sfx: Array[AudioStreamPlayer] = []
var voice_enabled := true
var sound_enabled := true
var current_voice_id := ""
var voice_lines: Dictionary = {}
var envelopes: Dictionary = {}
var _streams: Dictionary = {}
var _headless := false
var _alarm_clock := 0.0
var warning_active := false
var landing_active := false
var _last_door := false
@onready var player: CharacterBody3D = $"../Astronaut"
@onready var cockpit: Node3D = $"../Cockpit"

func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	voice_lines = JSON.parse_string(FileAccess.get_file_as_string("res://mission/voice_lines.json"))
	envelopes = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/voice/envelopes.json"))
	voice = AudioStreamPlayer3D.new()
	voice.name = "LunaScreenSpeaker"
	voice.unit_size = 5.0
	voice.max_distance = 30.0
	voice.volume_db = -3.0
	voice.attenuation_filter_cutoff_hz = 15000
	add_child(voice)
	voice.finished.connect(func() -> void: speech_finished.emit())
	air = _loop("cabin_air", -22.0)
	engine = _loop("engine", -30.0)
	for i in 6:
		var channel := AudioStreamPlayer.new()
		add_child(channel)
		sfx.append(channel)
	cockpit.control_event.connect(func(_id: String, _state: Variant) -> void: play_sfx("control", -14.0))

func _stream(id: String) -> AudioStream:
	if not _streams.has(id):
		_streams[id] = load("res://assets/audio/" + id + ".wav") as AudioStream
	return _streams[id]

func _loop(id: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _stream(id)
	if p.stream is AudioStreamWAV:
		(p.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(p.stream as AudioStreamWAV).loop_begin = 0
		(p.stream as AudioStreamWAV).loop_end = int(p.stream.get_length() * (p.stream as AudioStreamWAV).mix_rate)
	p.volume_db = db
	add_child(p)
	if not _headless:
		p.play()
	return p

func play_sfx(id: String, db: float = -12.0) -> void:
	if _headless:
		return
	for channel in sfx:
		if not channel.playing:
			channel.stream = _stream(id)
			channel.volume_db = db
			channel.play()
			return

func say(id: String) -> void:
	voice.stop()
	current_voice_id = id
	if not voice_lines.has(id):
		return
	# The guide's voice originates at the nearest physical LUNA monitor.
	var nearest := INF
	for screen_id in ["DASH_3", "SIDE_L_AFT", "SIDE_R_AFT"]:
		var control: Node3D = cockpit.call("get_control", screen_id)
		if control != null:
			var distance := control.global_position.distance_squared_to(player.global_position)
			if distance < nearest:
				nearest = distance
				voice.global_position = control.global_position
	voice.stream = _stream("voice/" + id)
	voice.stream_paused = false
	if voice_enabled and not _headless:
		voice.play()
	speech_started.emit(str(voice_lines[id]))

func speaking() -> bool:
	return voice != null and voice.playing and not voice.stream_paused and voice_enabled

func speech_activity() -> float:
	if not speaking() or not envelopes.has(current_voice_id):
		return 0.0
	var info: Dictionary = envelopes[current_voice_id]
	var values: Array = info["envelope"]
	var index := clampi(int(voice.get_playback_position() * float(info["envelope_fps"])), 0, values.size() - 1)
	return float(values[index])

func toggle_voice() -> void:
	voice_enabled = not voice_enabled
	voice.stream_paused = not voice_enabled

func toggle_sound() -> void:
	sound_enabled = not sound_enabled
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), not sound_enabled)

func _process(delta: float) -> void:
	var duck := -6.0 if speaking() else 0.0
	air.volume_db = lerpf(air.volume_db, -22.0 + duck, minf(1.0, delta * 5.0))
	engine.volume_db = lerpf(engine.volume_db, (-19.0 if landing_active else -31.0) + duck, minf(1.0, delta * 2.0))
	if warning_active:
		_alarm_clock += delta
		if _alarm_clock > 4.0:
			_alarm_clock = 0.0
			play_sfx("warning", -20.0 if speaking() else -15.0)
	else:
		_alarm_clock = 3.0
	var door_open: bool = cockpit.get("_door_open")
	if door_open != _last_door:
		_last_door = door_open
		play_sfx("door", -17.0)

func _exit_tree() -> void:
	# Explicitly release decoder playbacks before the audio server shuts down.
	if is_instance_valid(voice):
		voice.stop()
		voice.stream = null
	for channel in sfx:
		if is_instance_valid(channel):
			channel.stop()
			channel.stream = null
	for loop_player in [air, engine]:
		if is_instance_valid(loop_player):
			loop_player.stop()
			loop_player.stream = null
	_streams.clear()

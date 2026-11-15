extends Node
## Three deterministic decision scenarios, authored costs, and four endings.
const Interface = preload("res://scripts/MissionInterface.gd")
const GuideScreen = preload("res://scripts/LunaScreen.gd")
const Tasks = preload("res://scripts/MissionTasks.gd")
const Cinematic = preload("res://scripts/EndingCinematic.gd")
var tasks: Node3D
var cinematic: Node3D
@export var first_mission_delay: float = 10.0
@export var between_missions_delay: float = 8.0
@export_file("*.tscn") var secret_scene: String = "res://moon_base/MoonBase.tscn"
var _mission_delay_remaining := 0.0
var _queued_stage := -1
var _secret_transfer_remaining := -1.0
var _transferring := false
var _stage_voice_played := false
var last_effects: Dictionary = {}
var elapsed_seconds := 0.0
var phase := "briefing"
var stage_index := 0
var definition: Dictionary
var resources := {"fuel": 100.0, "power": 100.0, "minutes": 20.0}
var history: Array[Dictionary] = []
var reliable_height := false
var safe_decisions := true
var lights_used := false
var last_choice := ""
var last_outcome := ""
var ending := ""
var ending_reason := ""
var subtitle := ""
var subtitle_time := 0.0
var ui: CanvasLayer
var _busy := false
var _pending_ending := ""
@onready var cockpit: Node3D = $"../Cockpit"
@onready var player: CharacterBody3D = $"../Astronaut"
@onready var audio: Node = $"../FlightAudio"
@onready var lunar: Node3D = $"../LunarWorld"

func _ready() -> void:
	definition = JSON.parse_string(FileAccess.get_file_as_string("res://mission/scenarios.json"))
	ui = Interface.new()
	ui.mission = self
	add_child(ui)
	audio.speech_started.connect(func(text: String) -> void:
		subtitle = text
		subtitle_time = 0.0
	)
	tasks = Tasks.new()
	tasks.mission = self
	add_child(tasks)
	cinematic = Cinematic.new()
	cinematic.mission = self
	add_child(cinematic)
	call_deferred("_begin")

func _begin() -> void:
	for id in ["DASH_3", "SIDE_L_AFT", "SIDE_R_AFT"]:
		var old: Control = cockpit.screens[id]
		var viewport := old.get_parent()
		viewport.remove_child(old)
		old.queue_free()
		var screen := GuideScreen.new()
		screen.mission = self
		screen.size = Vector2(viewport.size)
		viewport.add_child(screen)
		cockpit.screens[id] = screen
		var control: Node = cockpit.get_control(id)
		control.target = screen
		control.label = "LUNA / MISSION GUIDE"
		control.set_meta("mission_guide", true)
	cockpit.control_event.connect(_on_control)
	reset_mission()

func fuel() -> float: return resources["fuel"]
func power() -> float: return resources["power"]
func minutes() -> float: return resources["minutes"]

func current_scenario() -> Dictionary:
	return definition["scenarios"][stage_index]

func phase_label() -> String:
	if phase == "briefing": return "APPROACH / FRA MAURO"
	if phase == "ending": return ("GOOD" if ending == "normal" else ending.to_upper()) + " ENDING"
	if phase == "task": return "CARRY OUT YOUR DECISION"
	if phase == "coasting": return "SYSTEMS STABLE / STAND BY"
	if phase == "transfer": return "TRANSFER TO MOON BASE"
	if phase == "descent": return "FINAL DESCENT" if _pending_ending != "safe" else "RETURN TO ORBIT"
	return "%02d / %s" % [stage_index + 1, ["LANDING WARNING", "RADAR FAILURE", "ROCK HAZARD"][stage_index]]

func screen_summary() -> String:
	if phase == "task": return tasks.instruction + ". " + tasks.location_hint
	if phase == "briefing": return "Your mission clock is running. Watch for alerts, then press Tab to open comms."
	if phase == "ending": return ending_title() + ". Open comms for your debrief."
	if phase == "coasting": return "Continue exploring the bridge. LUNA will alert you when the next mission is ready."
	if phase == "descent": return "Watch through the windows. " + ("Returning safely to orbit." if _pending_ending == "safe" else "Lunar terrain approaching.")
	if phase == "result": return "Decision received. Open comms to review the result and continue."
	return ["A warning light is flashing. Something might be wrong with the landing system.", "The landing radar is not working. We need reliable height data.", "Large rocks ahead. Fuel is low. Choose a landing plan."][stage_index]

func reset_mission() -> void:
	cinematic.stop()
	tasks.clear()
	_busy = false
	phase = "briefing"
	_queued_stage = 0
	_mission_delay_remaining = first_mission_delay
	_secret_transfer_remaining = -1.0
	_transferring = false
	_stage_voice_played = false
	last_effects.clear()
	elapsed_seconds = 0.0
	stage_index = 0
	resources = {"fuel": 100.0, "power": 100.0, "minutes": 20.0}
	history.clear()
	reliable_height = false
	safe_decisions = true
	lights_used = false
	last_choice = ""
	last_outcome = ""
	ending = ""
	ending_reason = ""
	_pending_ending = ""
	lunar.reset_flight()
	player.reset_to_spawn()
	audio.warning_active = false
	audio.landing_active = false
	_set_warning(false)
	ui.refresh()
	ui.close_panel()
	audio.say("welcome")

func advance() -> void:
	if _busy:
		return
	if phase == "briefing":
		_present_stage()
	elif phase == "result":
		if _pending_ending == "safe":
			_start_abort()
		elif resources_exhausted():
			_pending_ending = "bad"
			ending_reason = "resource"
			_start_resource_failure()
		elif stage_index < 2:
			_queue_stage(stage_index + 1)
		elif last_choice == "A":
			_present_stage()
		else:
			_start_landing()

func _present_stage() -> void:
	phase = "choice"
	lunar.set_stage(stage_index)
	audio.warning_active = true
	_set_warning(true)
	_queued_stage = -1
	_stage_voice_played = false
	ui.refresh()
	audio.say("mission_alert")
	if ui.panel_visible(): on_comms_opened()
	cockpit.post_message("MISSION ALERT: Press Tab to open LUNA. " + phase_label())

func choose(choice_id: String) -> void:
	if phase != "choice" or _busy: return
	if stage_index == 2 and choice_id == "A" and lights_used: return
	if choice_id not in ["A", "B", "C"]: return
	phase = "task"
	tasks.begin(stage_index, choice_id)
	ui.close_panel()
	ui.refresh()

func complete_task(choice_id: String) -> void:
	if phase != "task" or _busy:
		return
	if stage_index == 2 and choice_id == "A" and lights_used:
		return
	var selected: Dictionary = {}
	for option in current_scenario()["choices"]:
		if option["id"] == choice_id:
			selected = option
	if selected.is_empty():
		return
	_busy = true
	last_choice = choice_id
	last_outcome = str(selected["outcome"])
	last_effects = selected["cost"].duplicate() if selected["cost"] != null else {}
	if selected["cost"] != null:
		var cost: Dictionary = selected["cost"]
		resources["fuel"] = maxf(0, fuel() - float(cost["fuel_percentage_points"]))
		resources["power"] = maxf(0, power() - float(cost["power_percentage_points"]))
		resources["minutes"] = maxf(0, minutes() - float(cost["time_minutes"]))
	history.append({"stage": stage_index + 1, "choice": choice_id, "cost": selected["cost"], "outcome": last_outcome})
	if stage_index == 0:
		if choice_id == "C":
			_pending_ending = "safe"
		elif choice_id == "B":
			safe_decisions = false
	elif stage_index == 1:
		reliable_height = choice_id in ["A", "B"]
		if not reliable_height:
			safe_decisions = false
	elif choice_id == "A":
		lights_used = true
		lunar.set_landing_lights(true)
	elif choice_id == "B":
		safe_decisions = false
	phase = "result"
	audio.warning_active = false
	_set_warning(false)
	audio.play_sfx("confirm", -15)
	audio.say(str(selected["voice_id"]))
	cockpit.post_message("LUNA: choice %s / fuel %d%% / power %d%% / time %d min" % [choice_id, fuel(), power(), minutes()])
	_busy = false
	ui.refresh()

func resources_exhausted() -> bool:
	return fuel() <= 0 or power() <= 0 or minutes() <= 0

func evaluate_landing() -> String:
	if resources_exhausted():
		ending_reason = "resource"
		return "bad"
	if not reliable_height:
		ending_reason = "height"
		return "bad"
	if last_choice == "B":
		ending_reason = "rocks"
		return "bad"
	if safe_decisions and fuel() >= 70 and power() >= 75 and minutes() >= float(definition["ending_thresholds"]["secret"]["time_remaining_at_least_minutes"]):
		return "secret"
	return "normal"

func _start_landing() -> void:
	_pending_ending = evaluate_landing()
	phase = "descent"
	audio.warning_active = false
	audio.landing_active = true
	audio.say("descent")
	ui.close_panel()
	ui.refresh()
	cinematic.play(_pending_ending, ending_reason, _finish_flight)

func _start_abort() -> void:
	phase = "descent"
	audio.warning_active = false
	audio.landing_active = true
	ui.close_panel()
	ui.refresh()
	cinematic.play("safe", "", _finish_flight)

func _start_resource_failure() -> void:
	if cinematic.active or phase == "ending": return
	_pending_ending = "bad"
	ending_reason = "resource"
	phase = "descent"
	tasks.clear()
	audio.warning_active = true
	audio.landing_active = false
	cinematic.play("bad", "resource", _finish_flight)

func _finish_flight() -> void:
	# Also supports future resource-depletion scenarios without unsafe state reuse.
	if phase != "descent" and not resources_exhausted():
		return
	ending = _pending_ending
	phase = "ending"
	audio.landing_active = false
	audio.warning_active = false
	_set_warning(false)
	if ending == "secret":
		audio.play_sfx("success", -12)
		audio.say("secret")
	elif ending == "normal":
		audio.play_sfx("normal", -12)
		audio.say("normal")
	elif ending == "safe":
		audio.play_sfx("abort", -12)
		audio.say("safe")
	else:
		audio.play_sfx("failure", -14)
		audio.say("bad_" + ending_reason)
	ui.refresh()
	# The debrief is opt-in, like every mission panel. Secret arrival is automatic.
	if ending == "secret":
		_secret_transfer_remaining = maxf(8.0, float(audio.envelopes.get("secret", {}).get("duration", 8.0)) + 1.0)

func ending_title() -> String:
	return {"secret": "FRA MAURO PATHFINDER", "normal": "GOOD ENDING / SAFE TOUCHDOWN", "bad": "UNSAFE LANDING ATTEMPT", "safe": "CREW SAFE / LANDING ABORTED"}.get(ending, "MISSION DEBRIEF")

func ending_description() -> String:
	if ending == "secret": return "Safe landing. Every resource threshold met. Your prompt communication and reliable height data unlocked the secret ending."
	if ending == "normal": return "Your crew landed safely, but one or more secret-ending conditions were not met. Review the decisions below and try another route."
	if ending == "safe": return "You chose to abort the landing. The crew is safe in lunar orbit; the mission ended without reaching the surface."
	return {"height": "A view through the window did not provide reliable height data. Restore the radar or activate the backup sensor before attempting a landing.", "rocks": "Landing between the rocks saved fuel but left the ship dangerously close to hazards. Choose a clear landing zone when fuel permits.", "resource": "A required resource reached zero. Plan your remaining fuel, power and mission-time budget."}.get(ending_reason, "Review your decisions before trying again.")

func _set_warning(active: bool) -> void:
	cockpit.set_warning("MASTER_CAUTION", active)
	cockpit.set_warning("MASTER_WARNING", active and stage_index > 0)
	for id in ["DASH_1", "DASH_5"]:
		cockpit.set_screen_alert(id, active, ["LANDING SYSTEM", "RADAR DATA INVALID", "LANDING HAZARDS"][stage_index])

func replay_message() -> void:
	if phase == "task": audio.say(tasks.voice_id)
	elif phase == "choice": audio.say("s" + str(stage_index + 1))
	elif phase == "result": audio.say("s%d_%s" % [stage_index + 1, last_choice.to_lower()])
	elif phase == "briefing": audio.say("welcome")
	elif phase == "ending": audio.say("bad_" + ending_reason if ending == "bad" else ending)

func _on_control(id: String, _state: Variant) -> void:
	if cinematic.active: return
	tasks.on_control(id, _state)
	if id in ["DASH_3", "SIDE_L_AFT", "SIDE_R_AFT"]:
		ui.open_panel()

func _input(event: InputEvent) -> void:
	if cinematic != null and cinematic.active:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_M: audio.toggle_sound()
			elif event.keycode == KEY_V: audio.toggle_voice()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		match key.keycode:
			KEY_TAB:
				if ui.panel_visible(): ui.close_panel()
				else: ui.open_panel()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				if ui.panel_visible():
					ui.close_panel()
					get_viewport().set_input_as_handled()
			KEY_M: audio.toggle_sound()
			KEY_V: audio.toggle_voice()
			KEY_T: replay_message()
			KEY_1, KEY_2, KEY_3:
				if ui.panel_visible() and phase == "choice":
					choose(["A", "B", "C"][key.keycode - KEY_1])
					get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	subtitle_time += delta
	# Player time ends when the final flight command is committed.
	# Authored noninteractive ending shots do not spend the player's budget.
	if phase not in ["ending", "transfer", "descent"]:
		elapsed_seconds += delta
		resources["minutes"] = maxf(0.0, minutes() - delta / 60.0)
		if resources_exhausted():
			_start_resource_failure()
	if phase in ["briefing", "coasting"] and _queued_stage >= 0:
		_mission_delay_remaining -= delta
		if _mission_delay_remaining <= 0:
			stage_index = _queued_stage
			_present_stage()
	if phase == "ending" and ending == "secret" and not _transferring:
		_secret_transfer_remaining -= delta
		if _secret_transfer_remaining <= 0:
			_transfer_to_base()
	# Drive original ship telemetry with the mission budget and simulated altitude.
	for id in ["DASH_2", "DASH_4", "PEDESTAL_DISP"]:
		if cockpit.screens.has(id):
			var screen: Node = cockpit.screens[id]
			screen.data["ALT"] = maxf(0, lunar.altitude_m - 1.0) if reliable_height or stage_index == 0 else -1.0
			screen.data["FUEL"] = fuel()
			screen.data["POWER"] = power()


func _queue_stage(index: int) -> void:
	phase = "coasting"
	_queued_stage = index
	_mission_delay_remaining = between_missions_delay
	audio.warning_active = false
	_set_warning(false)
	ui.close_panel()
	ui.refresh()

func on_comms_opened() -> void:
	if phase == "choice" and not _stage_voice_played:
		_stage_voice_played = true
		audio.say("s" + str(stage_index + 1))

func alert_text() -> String:
	if phase == "task": return tasks.hud_text()
	if phase == "choice": return "MISSION ALERT  /  Press TAB to see your mission"
	if phase == "result": return "DECISION RESULT READY  /  Press TAB to review and continue"
	if phase == "ending" and ending == "secret": return "SECRET ENDING UNLOCKED  /  Moon-base arrival in %d s" % maxi(0, ceili(_secret_transfer_remaining))
	if phase == "ending": return "MISSION COMPLETE  /  Press TAB to view your debrief"
	return ""

func _transfer_to_base() -> void:
	if _transferring: return
	_transferring = true
	if not ResourceLoader.exists(secret_scene):
		push_error("Secret Moon-base scene missing: " + secret_scene)
		return
	get_tree().set_meta("moon_base_arrival", {"ending": ending, "resources": resources.duplicate(), "history": history.duplicate(true)})
	phase = "transfer"
	var error := get_tree().change_scene_to_file(secret_scene)
	if error != OK: push_error("Could not open Moon base: " + str(error))

extends Node3D
## A choice assigns work; only the highlighted physical control completes it.
var mission: Node
var target_id := ""
var instruction := ""
var location_hint := ""
var pending_choice := ""
var voice_id := ""
var step := 0
var wait_remaining := -1.0
var marker: Label3D

func _ready() -> void:
	_build_flight_controls()
	marker = Label3D.new()
	marker.font_size = 30
	marker.pixel_size = .002
	marker.modulate = Color("78fff0")
	marker.outline_size = 8
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.no_depth_test = true
	marker.visible = false
	add_child(marker)
	mission.cockpit.get_control("LIDAR").label = "BACKUP HEIGHT SENSOR / LIDAR"
	mission.cockpit.get_control("S_BAND").label = "MISSION CONTROL UPLINK / S-BAND"

func _build_flight_controls() -> void:
	# Wall-mounted flight panel, beside the rear door. No walking-space obstruction.
	var xf := Transform3D(Basis(Vector3.UP, PI), Vector3(1.48, 1.48, 4.03))
	var panel := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(.88, .85, .055)
	panel.mesh = box
	panel.material_override = mission.cockpit.mats["console"]
	panel.transform = xf
	add_child(panel)
	mission.cockpit._label("LANDING FLIGHT CONTROL", xf, 0, .34, 24, Color("87ede0"), .04, .0017)
	var ids := ["MISSION_ABORT", "LAND_NEAR_ROCKS", "LAND_CLEAR_ZONE"]
	var labels := ["ABORT / RETURN TO ORBIT", "COMMIT: BETWEEN ROCKS", "DIVERT: CLEAR LANDING ZONE"]
	for i in 3:
		var y := .16 - i * .20
		mission.cockpit._add_control(ids[i], "button", xf, -.31, y, Vector3(.10, .10, .035), ["red", "amber", "cyan"][i], .045, labels[i])
		mission.cockpit._label(labels[i], xf, .08, y, 22, Color("c7e7ee"), .045, .0016)
	# Observation target at the port canopy: report what you see through the window.
	var window_xf := Transform3D(Basis(), Vector3(-1.95, 1.48, -2.5))
	mission.cockpit._add_control("OBSERVE_WINDOW", "observe", window_xf, 0, 0, Vector3(.34, .28, .05), "", 0, "PORT WINDOW / REPORT SURFACE OBSERVATION")

func clear() -> void:
	target_id = ""
	instruction = ""
	pending_choice = ""
	step = 0
	wait_remaining = -1
	if marker != null: marker.visible = false

func begin(stage: int, choice: String) -> void:
	clear()
	pending_choice = choice
	var key := "%d%s" % [stage + 1, choice]
	match key:
		"1A": _target("S_BAND", "Contact Mission Control", "LEFT AFT / COMMUNICATIONS")
		"1B": _target("MASTER_CAUTION", "Acknowledge and recheck the landing warning", "FRONT DASHBOARD")
		"1C": _target("MISSION_ABORT", "Press ABORT / RETURN TO ORBIT", "REAR WALL / FLIGHT CONTROL")
		"2A":
			mission.cockpit.set_control_state("RADAR", true)
			_target("RADAR", "Switch RADAR OFF, then switch it ON", "RIGHT AFT / SENSOR CONSOLE")
		"2B":
			mission.cockpit.set_control_state("LIDAR", false)
			_target("LIDAR", "Activate the BACKUP HEIGHT SENSOR / LIDAR", "RIGHT AFT / SENSOR CONSOLE")
		"2C": _target("OBSERVE_WINDOW", "Look through the port window and press E to report", "FRONT LEFT / CANOPY WINDOW")
		"3A":
			mission.cockpit.set_control_state("EXT_LIGHTS", false)
			_target("EXT_LIGHTS", "Switch the LANDING / EXTERIOR LIGHTS ON", "OVERHEAD PANEL")
		"3B": _target("LAND_NEAR_ROCKS", "Press COMMIT: BETWEEN ROCKS", "REAR WALL / FLIGHT CONTROL")
		"3C": _target("LAND_CLEAR_ZONE", "Press DIVERT: CLEAR LANDING ZONE", "REAR WALL / FLIGHT CONTROL")
	voice_id = "task_" + key.to_lower()
	mission.audio.say(voice_id)

func _target(id: String, text: String, location: String) -> void:
	target_id = id
	instruction = text
	location_hint = location
	marker.visible = true
	marker.text = "↓  " + mission.cockpit.get_control(id).label + "\n[E] USE"

func on_control(id: String, state: Variant) -> void:
	if mission.phase != "task" or id != target_id or wait_remaining >= 0:
		return
	var key := "%d%s" % [mission.stage_index + 1, pending_choice]
	if key == "1B" and step == 0:
		step = 1
		wait_remaining = 4.0
		instruction = "Checking the warning… stand by"
		marker.visible = false
		return
	if key == "2A" and step == 0:
		if bool(state): return
		step = 1
		instruction = "RADAR is OFF. Switch RADAR ON to retest"
		voice_id = "task_radar_on"
		mission.audio.say(voice_id)
		return
	if key == "2A" and not bool(state): return
	if key in ["2B", "3A"] and not bool(state): return
	var completed := pending_choice
	clear()
	mission.complete_task(completed)

func hud_text() -> String:
	if wait_remaining >= 0: return "LUNA / SYSTEM RECHECK  ·  %d s" % ceili(wait_remaining)
	var control: Node3D = mission.cockpit.get_control(target_id)
	if control == null: return ""
	var camera: Camera3D = mission.player.camera
	var distance := camera.global_position.distance_to(control.global_position)
	var direction := (control.global_position - camera.global_position).normalized()
	var forward := -camera.global_basis.z
	var hint := "AHEAD"
	if forward.dot(direction) < .3:
		hint = "TURN RIGHT" if camera.global_basis.x.dot(direction) > 0 else "TURN LEFT"
	return "OBJECTIVE / %s\n%s  ·  %.1f m  ·  %s  ·  [E] USE" % [instruction, location_hint, distance, hint]

func _process(delta: float) -> void:
	if mission.phase != "task":
		marker.visible = false
		return
	if wait_remaining >= 0:
		wait_remaining -= delta
		if wait_remaining <= 0:
			wait_remaining = -1
			mission._set_warning(true)
			_target("S_BAND", "Warning persists. Contact Mission Control", "LEFT AFT / COMMUNICATIONS")
			voice_id = "task_recheck_done"
			mission.audio.say(voice_id)
	elif target_id != "":
		var control: Node3D = mission.cockpit.get_control(target_id)
		marker.global_position = control.global_position + Vector3(0, .22, 0)
		marker.modulate.a = .8 + .2 * sin(Time.get_ticks_msec() * .004)

extends Area3D
## A clickable cockpit control (button, toggle switch, lever, warning light,
## display screen or door control). The camera ray-casts against these Area3D
## nodes; activate() is called on click.
##
## Hook mission logic to the `activated` signal (or to Cockpit.control_event,
## which re-emits every control's activation).

signal activated(control_id: String, state: Variant)

@export var control_id: String = ""
## "button" | "switch" | "lever" | "warning" | "screen" | "door"
@export var control_type: String = "button"
@export var label: String = ""

var state: Variant = false
var indicator: MeshInstance3D      ## receives mat_on / mat_off
var lever: Node3D                  ## rotated around local X for switches/levers
var lever_angles := Vector2(-0.4, 0.4)
var mat_on: Material
var mat_off: Material
var target: Object                 ## screen UI or cockpit (door) callback target
var blinking := false
var _blink_t := 0.0
var _blink_on := false
var _flash := 0.0


func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	input_ray_pickable = true
	monitoring = false
	monitorable = true


func describe() -> String:
	var s := label if label != "" else control_id
	match control_type:
		"screen":
			return "%s  [display — click to change page]" % s
		"warning":
			return "%s  [%s — click to acknowledge]" % [s, "ALERT" if blinking else "normal"]
		"door":
			return "%s  [%s — click to toggle]" % [s, "OPEN" if bool(state) else "CLOSED"]
		_:
			return "%s  [%s]" % [s, "ON" if bool(state) else "OFF"]


func activate() -> void:
	match control_type:
		"warning":
			blinking = false
			state = false
		"screen":
			if target != null and target.has_method("cycle_mode"):
				target.call("cycle_mode")
				state = target.get("mode")
		"door":
			state = not bool(state)
			if target != null and target.has_method("set_door_open"):
				target.call("set_door_open", bool(state))
		_:
			state = not bool(state)
	_flash = 0.12
	refresh()
	activated.emit(control_id, state)


## Programmatic state change (does not emit unless asked).
func set_state(value: Variant, emit: bool = false) -> void:
	state = value
	refresh()
	if emit:
		activated.emit(control_id, state)


func set_warning(active: bool) -> void:
	blinking = active
	state = active
	_blink_t = 0.0
	refresh()


func refresh() -> void:
	if indicator != null:
		var lit := bool(state) if control_type != "warning" else (blinking and _blink_on)
		if control_type == "screen":
			lit = false
		indicator.material_override = mat_on if lit else mat_off


func _process(delta: float) -> void:
	if blinking:
		_blink_t += delta
		var on := fmod(_blink_t, 0.8) < 0.45
		if on != _blink_on:
			_blink_on = on
			refresh()
	elif _blink_on:
		_blink_on = false
		refresh()
	if lever != null:
		var target_angle := lever_angles.y if bool(state) else lever_angles.x
		lever.rotation.x = lerpf(lever.rotation.x, target_angle, minf(1.0, delta * 14.0))
	if _flash > 0.0:
		_flash -= delta
		scale = Vector3.ONE * (0.92 if _flash > 0.0 else 1.0)

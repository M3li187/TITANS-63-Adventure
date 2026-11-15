extends Node
## Example mission scenario showing how to drive the cockpit from game logic.
## Replace / extend this for NASA-style training scenarios.
##
## Scenario: after `start_delay` seconds cabin O2 pressure drops. The trainee
## must switch LIFE SUPPORT to backup (rear-left wall panel) and then
## acknowledge MASTER CAUTION on the main instrument panel.

@export var enabled := true
@export var start_delay := 25.0

var cockpit: Node
var _t := 0.0
var _stage := 0


func _ready() -> void:
	cockpit = get_node_or_null("../Cockpit")
	if cockpit != null:
		cockpit.control_event.connect(_on_event)


func _process(delta: float) -> void:
	if not enabled or cockpit == null:
		return
	_t += delta
	if _stage == 0 and _t > start_delay:
		_stage = 1
		cockpit.set_warning("MASTER_CAUTION", true)
		cockpit.set_warning("O2_LOW", true)
		cockpit.set_screen_alert("SIDE_L_FWD", true, "O2 PRESSURE LOW")
		cockpit.post_message("MISSION ▶ Cabin O2 pressure dropping! Switch LIFE SUPPORT BACKUP (rear-left wall panel), then acknowledge MASTER CAUTION.")


func _on_event(id: String, state: Variant) -> void:
	if _stage == 1 and id == "LIFE_SUPPORT" and bool(state):
		_stage = 2
		cockpit.set_warning("O2_LOW", false)
		cockpit.set_screen_alert("SIDE_L_FWD", false)
		cockpit.post_message("MISSION ▶ Backup life support online. O2 pressure stabilising.")
	elif _stage == 2 and id == "MASTER_CAUTION":
		_stage = 3
		cockpit.post_message("MISSION ▶ Caution acknowledged. Scenario complete — well done!")

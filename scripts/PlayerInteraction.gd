extends Node
## Physics-tick picking with a short reach and solid-surface occlusion.

signal hover_changed(text: String)

@export var reach: float = 2.4
@onready var player: CharacterBody3D = get_parent()
@onready var camera: Camera3D = $"../HeadPivot/Camera3D"
var hovered: Object
var _pending_activation := false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not event.is_echo():
		_pending_activation = true
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			# Click-to-recapture must not also operate a switch.
			if player.mouse_look_active:
				_pending_activation = true


func _physics_process(_delta: float) -> void:
	hovered = pick() if player.mouse_look_active and not player.input_locked else null
	if _pending_activation:
		_pending_activation = false
		if is_instance_valid(hovered):
			hovered.call("activate")
	var text := ""
	if is_instance_valid(hovered):
		text = "[E / Click] " + str(hovered.call("describe"))
	hover_changed.emit(text)


func pick() -> Object:
	return pick_ray(camera.global_position, -camera.global_basis.z)


func pick_ray(origin: Vector3, direction: Vector3) -> Object:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * reach, 1 | 4)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var object: Object = hit["collider"]
	if object.has_method("activate") and object.has_method("describe"):
		return object
	return null

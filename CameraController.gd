extends Camera3D
## Orbit / pan / zoom / free-fly / first-person camera for exploring the bridge.
##
##   Left drag ........ rotate (orbit around the pivot, or look around when zoomed in)
##   Right drag ....... pan
##   Mouse wheel ...... zoom (dollies forward/back once you are at the pivot)
##   W A S D .......... fly            Q / E .... down / up        Shift = fast
##   F or Middle click  toggle mouse-look (first-person, mouse captured)
##   1 / 2 / 3 ........ interior / exterior / pilot-seat presets
##   R ................ reset           Esc ...... release mouse capture
##   Left click (no drag) on a control: activate it

signal hover_changed(text: String)
signal mouse_look_changed(active: bool)

const PRESETS := {
	"interior": {"pivot": Vector3(0.0, 1.62, 2.6), "yaw": 0.0, "pitch": -0.14, "dist": 0.0},
	"exterior": {"pivot": Vector3(0.0, 1.2, 3.5), "yaw": 2.45, "pitch": -0.3, "dist": 13.0},
	"pilot": {"pivot": Vector3(-1.0, 1.28, -1.78), "yaw": 0.0, "pitch": -0.18, "dist": 0.0},
}

@export var move_speed := 2.2
@export var rotate_sensitivity := 0.006
@export var look_sensitivity := 0.0025
@export var max_distance := 120.0

var pivot := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var dist := 0.0
var mouse_look := false

var _ldown := false
var _rdown := false
var _drag_px := 0.0
var _pending_click := false
var _click_pos := Vector2.ZERO
var _hover: Object = null
var _hover_tick := 0


func _ready() -> void:
	near = 0.02
	far = 6000.0
	fov = 70.0
	current = true
	apply_preset("interior")


func apply_preset(preset_name: String) -> void:
	var p: Dictionary = PRESETS[preset_name]
	pivot = p["pivot"]
	yaw = p["yaw"]
	pitch = p["pitch"]
	dist = p["dist"]
	_update_transform()


func set_mouse_look(active: bool) -> void:
	if active == mouse_look:
		return
	mouse_look = active
	if active:
		# collapse orbit into first person at the current camera position
		pivot = global_position
		dist = 0.0
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	mouse_look_changed.emit(active)


func _basis() -> Basis:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0))


func _update_transform() -> void:
	var b := _basis()
	global_transform = Transform3D(b, pivot + b.z * dist)


func _zoom(direction: int) -> void:
	var b := _basis()
	if direction < 0:
		if dist > 0.5:
			dist *= 0.85
			if dist < 0.5:
				pivot += b.z * dist
				dist = 0.0
		else:
			pivot -= b.z * 0.3
	else:
		if dist >= 0.5:
			dist = minf(dist * 1.18, max_distance)
		else:
			pivot += b.z * 0.3
	_update_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_ldown = true
					_drag_px = 0.0
					if mouse_look:
						_pending_click = true
						_click_pos = get_viewport().get_visible_rect().size * 0.5
				else:
					if _ldown and _drag_px < 5.0 and not mouse_look:
						_pending_click = true
						_click_pos = mb.position
					_ldown = false
			MOUSE_BUTTON_RIGHT:
				_rdown = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				if mb.pressed:
					set_mouse_look(not mouse_look)
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom(-1)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom(1)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mouse_look:
			yaw -= mm.relative.x * look_sensitivity
			pitch = clampf(pitch - mm.relative.y * look_sensitivity, -1.55, 1.55)
		elif _ldown:
			_drag_px += mm.relative.length()
			if _drag_px >= 5.0:
				yaw -= mm.relative.x * rotate_sensitivity
				pitch = clampf(pitch - mm.relative.y * rotate_sensitivity, -1.55, 1.55)
		elif _rdown:
			var b := _basis()
			var k := maxf(dist, 2.0) * 0.0018
			pivot += -b.x * mm.relative.x * k + b.y * mm.relative.y * k
		_update_transform()
	elif event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		match key.keycode:
			KEY_1:
				set_mouse_look(false)
				apply_preset("interior")
			KEY_2:
				set_mouse_look(false)
				apply_preset("exterior")
			KEY_3:
				set_mouse_look(false)
				apply_preset("pilot")
			KEY_R:
				set_mouse_look(false)
				apply_preset("interior")
			KEY_F:
				set_mouse_look(not mouse_look)
			KEY_ESCAPE:
				set_mouse_look(false)


func _process(delta: float) -> void:
	var b := _basis()
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move -= b.z
	if Input.is_key_pressed(KEY_S):
		move += b.z
	if Input.is_key_pressed(KEY_A):
		move -= b.x
	if Input.is_key_pressed(KEY_D):
		move += b.x
	if Input.is_key_pressed(KEY_E):
		move += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		move -= Vector3.UP
	if move != Vector3.ZERO:
		var speed := move_speed * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		if dist > 0.5:
			speed *= maxf(1.0, dist * 0.25)
		pivot += move.normalized() * speed * delta
		_update_transform()


func _physics_process(_delta: float) -> void:
	if _pending_click:
		_pending_click = false
		var hit := _pick(_click_pos)
		if hit != null:
			hit.call("activate")
			_hover = null   # force HUD refresh
	_hover_tick += 1
	if _hover_tick % 3 == 0:
		var pos := get_viewport().get_visible_rect().size * 0.5 if mouse_look else get_viewport().get_mouse_position()
		var h := _pick(pos)
		if h != _hover or h != null:
			_hover = h
			hover_changed.emit(h.call("describe") if h != null else "")


func _pick(screen_pos: Vector2) -> Object:
	var from := project_ray_origin(screen_pos)
	var to := from + project_ray_normal(screen_pos) * 40.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	var c: Object = hit["collider"]
	if c != null and c.has_method("activate"):
		return c
	return null

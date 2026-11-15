extends Node3D
## SCI-FI COCKPIT BRIDGE 6
## Builds the complete spacecraft bridge procedurally at runtime:
##   interior architecture, canopy, instrument panels, pilot seats, consoles,
##   overhead panel, rear entrance + corridor, exterior hull, lighting,
##   interactive controls, live display screens and the space backdrop.
##
## Coordinate system: metres, +Y up, the pilots face -Z. Floor at y = 0.
## Static geometry is merged per material by MeshBatcher (few draw calls).

signal control_event(control_id: String, state: Variant)
signal status_message(text: String)

const MeshBatcher = preload("res://scripts/MeshBatcher.gd")
const Mats = preload("res://scripts/CockpitMaterials.gd")
const CockpitControl = preload("res://scripts/CockpitControl.gd")
const ScreenUI = preload("res://scripts/ScreenUI.gd")
const BridgeCollision = preload("res://scripts/BridgeCollision.gd")
const SpaceEnv = preload("res://scripts/SpaceEnvironment.gd")

# ---------------------------------------------------------------- layout
const CEIL := 2.6
const ZC := -1.0                 ## centre of the canopy ellipse (plan view)
const Z_JOIN := -1.3             ## canopy / main cabin joint
const Z_REAR := 4.2              ## rear bulkhead
const Z_HULL_REAR := 4.4
const SIN84 := 0.9945219
const THETAS := [-84.0, -60.0, -36.0, -12.0, 12.0, 36.0, 60.0, 84.0]   ## canopy facet edges
const RING_Y := [1.0, 1.8, 2.5]                                         ## sill / mid / top rings
## Half cross-section of the cabin interior (x >= 0), bottom -> top.
const PROFILE := [Vector2(2.6, 0.0), Vector2(2.95, 0.35), Vector2(2.95, 1.2), Vector2(2.65, 2.2), Vector2(1.9, 2.6)]
## Half cross-section of the outer hull.
const OUTER_HALF := [Vector2(2.7, -0.45), Vector2(3.2, 0.3), Vector2(3.25, 1.2), Vector2(2.95, 2.35), Vector2(2.05, 2.85)]
const ROOF_Y := 2.95
const RIB_Z := [-1.3, -0.2, 0.9, 2.0, 3.1, 4.2]
const DASH_IN := 0.95
const DASH_OUT := 0.05

var mats: Dictionary
var B: MeshBatcher      ## interior
var X: MeshBatcher      ## exterior
var G: MeshBatcher      ## glass
var rng := RandomNumberGenerator.new()

var controls: Dictionary = {}
var screens: Dictionary = {}
var interior_lights: Array = []
var _light_base: Array = []
var _env: Dictionary = {}
var _controls_root: Node3D
var _screens_root: Node
var _displays_root: Node3D
var _labels_root: Node3D
var _door_l: Node3D
var _door_r: Node3D
var _door_open := false
var _door_t := 0.0
var _time := 0.0
var _red_alert := false
var _cabin_lights := true
var _mesh_cache: Dictionary = {}


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	rng.seed = 6061
	mats = Mats.build()
	B = MeshBatcher.new(mats)
	X = MeshBatcher.new(mats)
	G = MeshBatcher.new(mats)
	_controls_root = _mk("Controls")
	_displays_root = _mk("Displays")
	_labels_root = _mk("Labels")
	_screens_root = Node.new()
	_screens_root.name = "ScreenViewports"
	add_child(_screens_root)

	_build_floor()
	_build_walls()
	_build_ribs()
	_build_ceiling()
	_build_canopy()
	_build_dashboard()
	_build_pedestal()
	_build_seat(Vector3(-1.0, 0.0, -1.85), -1.0)
	_build_seat(Vector3(1.0, 0.0, -1.85), 1.0)
	_build_side_consoles()
	_build_overhead()
	_build_rear_section()
	_build_rear_wall_and_door()
	_build_corridor()
	_build_exterior()

	var interior := B.build("InteriorMesh")
	add_child(interior)
	var exterior := X.build("ExteriorMesh")
	add_child(exterior)
	var glass := G.build("CanopyGlass")
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glass)

	BridgeCollision.setup(self)
	_build_lights()
	_env = SpaceEnv.setup(self)
	print("[Bridge 6] built in %d ms | interior %d tris, exterior %d tris, glass %d tris | %d controls, %d screens" % [
		Time.get_ticks_msec() - t0, B.tri_count, X.tri_count, G.tri_count, controls.size(), screens.size()])


func _mk(n: String) -> Node3D:
	var node := Node3D.new()
	node.name = n
	add_child(node)
	return node


# =====================================================================
# Public API for mission / educational scenarios
# =====================================================================
func get_control(id: String) -> CockpitControl:
	return controls.get(id)


func list_controls() -> PackedStringArray:
	return PackedStringArray(controls.keys())


func set_warning(id: String, active: bool) -> void:
	if controls.has(id):
		controls[id].set_warning(active)


func set_control_state(id: String, value: Variant) -> void:
	if controls.has(id):
		controls[id].set_state(value)


func set_screen_mode(id: String, mode: int) -> void:
	if screens.has(id):
		screens[id].mode = mode


func set_screen_alert(id: String, active: bool, text: String = "WARNING") -> void:
	if screens.has(id):
		screens[id].set_alert(active, text)


func set_screen_value(id: String, key: String, value: float) -> void:
	if screens.has(id):
		screens[id].data[key] = value


func post_message(text: String) -> void:
	status_message.emit(text)


func set_door_open(open: bool) -> void:
	if not open and _doorway_occupied():
		open = true
		post_message("Door held open: doorway occupied.")
	_door_open = open
	for id in ["DOOR_CONTROL", "DOOR_CONTROL_REAR"]:
		if controls.has(id):
			controls[id].state = open
			controls[id].refresh()


func _on_control_activated(id: String, state: Variant) -> void:
	match id:
		"RED_ALERT":
			_red_alert = bool(state)
			if not _red_alert:
				_apply_light_mode()
		"CABIN_LIGHTS":
			_cabin_lights = not bool(state)
			_apply_light_mode()
	control_event.emit(id, state)


# =====================================================================
# Geometry helpers
# =====================================================================
func _profile_x(prof: Array, y: float) -> float:
	var first: Vector2 = prof[0]
	if y <= first.y:
		return first.x
	for i in range(prof.size() - 1):
		var p0: Vector2 = prof[i]
		var p1: Vector2 = prof[i + 1]
		if y <= p1.y:
			return lerpf(p0.x, p1.x, (y - p0.y) / maxf(p1.y - p0.y, 1e-4))
	var last: Vector2 = prof[prof.size() - 1]
	return last.x


func wall_x(y: float) -> float:
	return _profile_x(PROFILE, y)


func _b_of(y: float) -> float:
	if y < 1.0:
		return lerpf(2.6, 2.9, clampf(y, 0.0, 1.0))
	return lerpf(2.9, 1.9, clampf((y - 1.0) / 1.5, 0.0, 1.0))


## Point on the canopy "ellipse" at angle theta (deg, 0 = straight ahead).
func ring_point(theta: float, y: float, inset: float = 0.0) -> Vector3:
	if absf(theta) > 83.0:
		return Vector3(signf(theta) * (wall_x(y) - inset), y, Z_JOIN)
	var t := deg_to_rad(theta)
	var a := wall_x(y) / SIN84 - inset
	var b := _b_of(y) - inset
	return Vector3(a * sin(t), y, ZC - b * cos(t))


## Plan-view point on the dashboard arc (uses the sill ellipse) at height y.
func dash_pt(theta: float, d: float, y: float) -> Vector3:
	var p := ring_point(theta, 1.0, d)
	p.y = y
	return p


func _ext_pt(theta: float, y: float, a: float, b: float) -> Vector3:
	if absf(theta) > 83.0:
		return Vector3(signf(theta) * _profile_x(OUTER_HALF, y), y, Z_JOIN)
	var t := deg_to_rad(theta)
	return Vector3(a * sin(t), y, ZC - b * cos(t))


## Local surface frame: x = right, y = up (in plane), z = surface normal.
func _frame(origin: Vector3, right: Vector3, up: Vector3) -> Transform3D:
	var r := right.normalized()
	var n := r.cross(up).normalized()
	var u := n.cross(r).normalized()
	return Transform3D(Basis(r, u, n), origin)


## Same, but guarantees that the frame normal points along `n`.
func _frame_n(origin: Vector3, right: Vector3, up: Vector3, n: Vector3) -> Transform3D:
	var f := _frame(origin, right, up)
	if f.basis.z.dot(n) < 0.0:
		f = _frame(origin, -right, up)
	return f


func _sub(xf: Transform3D, u: float, v: float, w: float = 0.0) -> Transform3D:
	return xf * Transform3D(Basis(), Vector3(u, v, w))


func _fbox(b: MeshBatcher, key: String, xf: Transform3D, u: float, v: float, sw: float, sh: float, depth: float, lift: float = 0.0) -> void:
	b.add_box_xf(key, _sub(xf, u, v, lift + depth * 0.5), Vector3(sw, sh, depth))


func _fcyl(b: MeshBatcher, key: String, xf: Transform3D, u: float, v: float, r: float, h: float, seg: int = 12, lift: float = 0.0) -> void:
	b.add_cyl_xf(key, _sub(xf, u, v, lift + h * 0.5) * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), r, h, seg)


func _orient_normal(n: Vector3, toward: Vector3) -> Vector3:
	return n if n.dot(toward) >= 0.0 else -n


func _quad_normal(a: Vector3, b: Vector3, d: Vector3) -> Vector3:
	return (b - a).cross(d - a).normalized()


# ---------------------------------------------------------------- details
func _button_grid(b: MeshBatcher, xf: Transform3D, u0: float, v0: float, cols: int, rows: int, du: float, dv: float, bw: float, bh: float, keys: Array, lift: float = 0.0) -> void:
	_fbox(b, "trim_dark", xf, u0 + du * (cols - 1) * 0.5, v0 - dv * (rows - 1) * 0.5, du * cols + 0.01, dv * rows + 0.01, 0.004, lift)
	for r in rows:
		for c in cols:
			var u := u0 + c * du
			var v := v0 - r * dv
			var key: String = keys[rng.randi() % keys.size()]
			_fbox(b, key, xf, u, v, bw, bh, 0.012, lift + 0.004)


func _switch_row(b: MeshBatcher, xf: Transform3D, u0: float, v0: float, count: int, du: float, lift: float = 0.0) -> void:
	for i in count:
		var u := u0 + i * du
		_fbox(b, "trim_dark", xf, u, v0, 0.026, 0.034, 0.006, lift)
		var base := _sub(xf, u, v0, lift + 0.006)
		var ang := 0.4 if rng.randf() > 0.5 else -0.4
		var tip := base * Vector3(0.0, sin(ang) * 0.03, cos(ang) * 0.03)
		b.add_cyl_between("chrome", base.origin, tip, 0.0045, 6)
		b.add_box_xf("rubber", Transform3D(base.basis, tip), Vector3(0.011, 0.011, 0.011))
		_fbox(b, "glow_green" if rng.randf() > 0.35 else "glow_amber", xf, u, v0 + 0.03, 0.008, 0.008, 0.006, lift)


func _vent(b: MeshBatcher, xf: Transform3D, u: float, v: float, w: float, h: float, slats: int, lift: float = 0.0) -> void:
	_fbox(b, "trim_dark", xf, u, v, w, h, 0.01, lift)
	for i in slats:
		var vv := v - h * 0.5 + (i + 0.5) * h / slats
		_fbox(b, "hull_dark", xf, u, vv, w - 0.03, h / slats * 0.45, 0.02, lift)


func _gauge(b: MeshBatcher, xf: Transform3D, u: float, v: float, r: float, lift: float = 0.0) -> void:
	_fcyl(b, "trim", xf, u, v, r, 0.02, 18, lift)
	_fcyl(b, "glow_dim", xf, u, v, r * 0.82, 0.024, 18, lift)
	for k in 7:
		var a := -2.2 + 4.4 * k / 6.0
		_fbox(b, "glow_white", xf, u + sin(a) * r * 0.7, v + cos(a) * r * 0.7, 0.004, 0.004, 0.003, lift + 0.024)
	var na := rng.randf_range(-2.0, 2.0)
	var c := _sub(xf, u, v, lift + 0.027)
	var tip := c * Vector3(sin(na) * r * 0.65, cos(na) * r * 0.65, 0.0)
	b.add_beam("glow_amber", c.origin, tip, 0.004, 0.003, c.basis.z)


func _knob(b: MeshBatcher, xf: Transform3D, u: float, v: float, r: float, lift: float = 0.0) -> void:
	_fcyl(b, "trim_dark", xf, u, v, r * 1.35, 0.006, 14, lift)
	_fcyl(b, "rubber", xf, u, v, r, 0.026, 14, lift + 0.006)
	_fbox(b, "glow_white", xf, u, v + r * 0.5, 0.004, r * 0.6, 0.003, lift + 0.032)


func _led_row(b: MeshBatcher, xf: Transform3D, u0: float, v0: float, count: int, du: float, keys: Array, sz: float = 0.012, lift: float = 0.0) -> void:
	for i in count:
		var key: String = keys[rng.randi() % keys.size()]
		_fbox(b, key, xf, u0 + i * du, v0, sz, sz, 0.006, lift)


func _label(text: String, xf: Transform3D, u: float, v: float, px: int = 28, col: Color = Color(0.55, 0.8, 1.0), lift: float = 0.004, pixel: float = 0.0007) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = px
	l.pixel_size = pixel
	l.modulate = col
	l.outline_size = 0
	l.double_sided = false
	l.transform = _sub(xf, u, v, lift)
	_labels_root.add_child(l)
	return l


func _box_mesh(size: Vector3) -> BoxMesh:
	var key := "box_%s" % str(size)
	if not _mesh_cache.has(key):
		var m := BoxMesh.new()
		m.size = size
		_mesh_cache[key] = m
	return _mesh_cache[key]


func _cyl_mesh(r: float, h: float) -> CylinderMesh:
	var key := "cyl_%f_%f" % [r, h]
	if not _mesh_cache.has(key):
		var m := CylinderMesh.new()
		m.top_radius = r
		m.bottom_radius = r
		m.height = h
		m.radial_segments = 10
		m.rings = 1
		_mesh_cache[key] = m
	return _mesh_cache[key]


## Creates a clickable control on a surface frame.
func _add_control(id: String, type: String, xf: Transform3D, u: float, v: float, size: Vector3, color: String, lift: float = 0.0, label: String = "") -> CockpitControl:
	var c: CockpitControl = CockpitControl.new()
	c.name = id
	c.control_id = id
	c.control_type = type
	c.label = label if label != "" else id.replace("_", " ")
	c.transform = _sub(xf, u, v, lift + size.z * 0.5)
	_controls_root.add_child(c)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(maxf(size.x, 0.03) + 0.01, maxf(size.y, 0.03) + 0.01, maxf(size.z, 0.03) + 0.02)
	cs.shape = sh
	c.add_child(cs)
	if color != "":
		c.mat_on = mats["led_on_" + color]
		c.mat_off = mats["led_off_" + color]
	match type:
		"button", "warning":
			var mi := MeshInstance3D.new()
			mi.mesh = _box_mesh(size)
			c.add_child(mi)
			c.indicator = mi
			var bezel := MeshInstance3D.new()
			bezel.mesh = _box_mesh(Vector3(size.x + 0.012, size.y + 0.012, size.z * 0.5))
			bezel.material_override = mats["trim_dark"]
			bezel.position.z = -size.z * 0.3
			c.add_child(bezel)
		"switch":
			var plate := MeshInstance3D.new()
			plate.mesh = _box_mesh(Vector3(0.03, 0.045, 0.006))
			plate.material_override = mats["trim_dark"]
			plate.position.z = -size.z * 0.5 + 0.003
			c.add_child(plate)
			var pivot := Node3D.new()
			pivot.position.z = -size.z * 0.5 + 0.006
			c.add_child(pivot)
			var lev := MeshInstance3D.new()
			lev.mesh = _cyl_mesh(0.0045, 0.034)
			lev.material_override = mats["chrome"]
			lev.rotation.x = PI * 0.5
			lev.position.z = 0.017
			pivot.add_child(lev)
			var cap := MeshInstance3D.new()
			cap.mesh = _box_mesh(Vector3(0.011, 0.011, 0.012))
			cap.material_override = mats["rubber"]
			cap.position.z = 0.034
			pivot.add_child(cap)
			c.lever = pivot
			c.lever_angles = Vector2(-0.45, 0.45)
			var led := MeshInstance3D.new()
			led.mesh = _box_mesh(Vector3(0.009, 0.009, 0.006))
			led.position = Vector3(0.0, size.y * 0.5 - 0.004, -size.z * 0.5 + 0.004)
			c.add_child(led)
			c.indicator = led
		"lever":
			var slot := MeshInstance3D.new()
			slot.mesh = _box_mesh(Vector3(0.03, size.y, 0.01))
			slot.material_override = mats["rubber"]
			slot.position.z = -size.z * 0.5 + 0.005
			c.add_child(slot)
			var pivot := Node3D.new()
			pivot.position.z = -size.z * 0.5
			c.add_child(pivot)
			var arm := MeshInstance3D.new()
			arm.mesh = _box_mesh(Vector3(0.016, 0.016, 0.13))
			arm.material_override = mats["chrome"]
			arm.position.z = 0.065
			pivot.add_child(arm)
			var grip := MeshInstance3D.new()
			grip.mesh = _box_mesh(Vector3(0.075, 0.032, 0.035))
			grip.material_override = mats["rubber"]
			grip.position.z = 0.135
			pivot.add_child(grip)
			var led := MeshInstance3D.new()
			led.mesh = _box_mesh(Vector3(0.02, 0.012, 0.008))
			led.position = Vector3(0.0, 0.0, 0.155)
			pivot.add_child(led)
			c.indicator = led
			c.lever = pivot
			c.lever_angles = Vector2(0.55, -0.45)
	c.activated.connect(_on_control_activated)
	controls[id] = c
	c.refresh()
	return c


## Live display: SubViewport + procedural UI shown on a quad, with bezel.
func _add_screen(id: String, xf: Transform3D, u: float, v: float, sw: float, sh: float, mode: int, res: Vector2i = Vector2i(512, 320)) -> void:
	var vp := SubViewport.new()
	vp.name = id + "_VP"
	vp.size = res
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_screens_root.add_child(vp)
	var ui: ScreenUI = ScreenUI.new()
	ui.mode = mode
	ui.screen_name = id.replace("_", " ")
	ui.seed_offset = rng.randf() * 100.0
	ui.position = Vector2.ZERO
	ui.size = Vector2(res)
	vp.add_child(ui)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 0.0, 0.0)
	mat.emission_enabled = true
	mat.emission = Color(0, 0, 0)
	mat.emission_texture = vp.get_texture()
	mat.emission_energy_multiplier = 1.3
	mat.roughness = 0.12
	mat.metallic_specular = 0.6
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	var q := QuadMesh.new()
	q.size = Vector2(sw, sh)
	var mi := MeshInstance3D.new()
	mi.name = id
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = _sub(xf, u, v, 0.012)
	_displays_root.add_child(mi)

	# bezel (batched)
	var bw := 0.022
	_fbox(B, "console", xf, u, v, sw + 0.05, sh + 0.06, 0.008)
	_fbox(B, "trim_dark", xf, u, v + sh * 0.5 + bw * 0.5, sw + bw * 2.0, bw, 0.02)
	_fbox(B, "trim_dark", xf, u, v - sh * 0.5 - bw * 0.5, sw + bw * 2.0, bw, 0.02)
	_fbox(B, "trim_dark", xf, u - sw * 0.5 - bw * 0.5, v, bw, sh, 0.02)
	_fbox(B, "trim_dark", xf, u + sw * 0.5 + bw * 0.5, v, bw, sh, 0.02)
	_fbox(B, "groove", xf, u, v, sw + 0.004, sh + 0.004, 0.011)
	for k in 6:
		_fbox(B, "btn_light", xf, u - sw * 0.4 + k * sw * 0.16, v - sh * 0.5 - bw * 0.5, 0.022, 0.009, 0.026)
	_fbox(B, "glow_cyan", xf, u + sw * 0.5 + bw * 0.5, v + sh * 0.5 - 0.02, 0.006, 0.006, 0.024)

	var c := _add_control(id, "screen", xf, u, v, Vector3(sw, sh, 0.02), "", 0.0, id.replace("_", " "))
	c.target = ui
	c.state = mode
	screens[id] = ui


# =====================================================================
# FLOOR
# =====================================================================
func _floor_inside(x: float, z: float) -> bool:
	if z < Z_JOIN:
		var a := 2.5
		var b := 2.45
		return pow(x / a, 2.0) + pow((z - ZC) / b, 2.0) <= 1.0
	return absf(x) <= 2.45 and z <= Z_REAR


func _build_floor() -> void:
	# sub-floor (visible through the plate grooves)
	B.add_box("groove", Vector3(0, -0.08, (Z_JOIN + Z_REAR) * 0.5), Vector3(5.9, 0.08, Z_REAR - Z_JOIN))
	var poly := []
	for th in THETAS:
		poly.append(ring_point(th, 0.0) + Vector3(0, -0.04, 0))
	B.add_slab("groove", poly, Vector3.UP, 0.08)
	# deck plates
	var cell := 0.6
	for ix in range(-4, 4):
		for iz in 12:
			var x0 := ix * cell
			var z0 := -3.0 + iz * cell
			if not (_floor_inside(x0, z0) and _floor_inside(x0 + cell, z0) and _floor_inside(x0, z0 + cell) and _floor_inside(x0 + cell, z0 + cell)):
				continue
			var cx := x0 + cell * 0.5
			var cz := z0 + cell * 0.5
			var aisle := absf(cx) < 0.6
			B.add_box("grate" if aisle else "floor", Vector3(cx, -0.025, cz), Vector3(cell - 0.03, 0.05, cell - 0.03))
			if aisle:
				for k in 7:
					var zz := z0 + 0.06 + k * (cell - 0.12) / 6.0
					B.add_box("trim_dark", Vector3(cx, 0.004, zz), Vector3(cell - 0.08, 0.008, 0.018))
				B.add_box("trim_dark", Vector3(cx - cell * 0.5 + 0.035, 0.005, cz), Vector3(0.02, 0.01, cell - 0.06))
				B.add_box("trim_dark", Vector3(cx + cell * 0.5 - 0.035, 0.005, cz), Vector3(0.02, 0.01, cell - 0.06))
			else:
				for dx: float in [-1.0, 1.0]:
					for dz: float in [-1.0, 1.0]:
						B.add_box("trim", Vector3(cx + dx * (cell * 0.5 - 0.045), 0.002, cz + dz * (cell * 0.5 - 0.045)), Vector3(0.022, 0.006, 0.022))
	# side edge strips + light strips
	for s: float in [-1.0, 1.0]:
		B.add_box("hull_dark", Vector3(s * 2.52, -0.02, (Z_JOIN + Z_REAR) * 0.5), Vector3(0.16, 0.04, Z_REAR - Z_JOIN))
		B.add_box("glow_blue", Vector3(s * 2.43, 0.002, (Z_JOIN + Z_REAR) * 0.5), Vector3(0.022, 0.008, Z_REAR - Z_JOIN - 0.1))
		B.add_box("glow_cyan", Vector3(s * 0.615, 0.003, 1.0), Vector3(0.026, 0.008, 6.1))
		B.add_box("trim", Vector3(s * 0.615, 0.001, 1.0), Vector3(0.05, 0.004, 6.15))
	# threshold at rear door
	B.add_box("glow_cyan", Vector3(0, 0.003, Z_REAR - 0.12), Vector3(1.5, 0.008, 0.025))
	for k in 10:
		B.add_box("hazard" if k % 2 == 0 else "trim_dark", Vector3(-0.675 + k * 0.15, 0.003, Z_REAR - 0.05), Vector3(0.15, 0.008, 0.1))


# =====================================================================
# WALLS (main cabin)
# =====================================================================
func _seg_normal(p0: Vector2, p1: Vector2, s: float) -> Vector3:
	var d := p1 - p0
	var n2 := Vector2(-d.y, d.x).normalized()
	if n2.dot(Vector2(0, 1.3) - (p0 + p1) * 0.5 * Vector2(1, 1)) < 0.0:
		n2 = -n2
	return Vector3(s * n2.x, n2.y, 0).normalized()


func _build_walls() -> void:
	for s: float in [-1.0, 1.0]:
		for j in range(PROFILE.size() - 1):
			var p0: Vector2 = PROFILE[j]
			var p1: Vector2 = PROFILE[j + 1]
			var n := _seg_normal(p0, p1, s)
			var a0 := Vector3(s * p0.x, p0.y, Z_JOIN)
			var a1 := Vector3(s * p1.x, p1.y, Z_JOIN)
			# continuous dark backing behind the panels (shows in seams)
			B.add_slab("groove", [a0 - n * 0.045, a1 - n * 0.045, a1 - n * 0.045 + Vector3(0, 0, Z_REAR - Z_JOIN), a0 - n * 0.045 + Vector3(0, 0, Z_REAR - Z_JOIN)], n, 0.03)
			for k in range(RIB_Z.size() - 1):
				var z0: float = RIB_Z[k] + 0.08
				var z1: float = RIB_Z[k + 1] - 0.08
				var q := [Vector3(s * p0.x, p0.y, z0), Vector3(s * p1.x, p1.y, z0), Vector3(s * p1.x, p1.y, z1), Vector3(s * p0.x, p0.y, z1)]
				var key := "hull"
				if j == 3:
					key = "hull_dark"
				B.add_slab(key, MeshBatcher.shrink(q, 0.018), n, 0.04)
				var q0: Vector3 = q[0]
				var q1: Vector3 = q[1]
				var q2: Vector3 = q[2]
				var mid := (q0 + q2) * 0.5
				var up := (q1 - q0).normalized()
				var xf := _frame_n(mid, Vector3(0, 0, 1), up, n)
				var seg_len := (Vector2(p1) - Vector2(p0)).length()
				var bay := z1 - z0
				_wall_details(xf, j, k, s, seg_len, bay)


func _wall_details(xf: Transform3D, j: int, k: int, s: float, seg_len: float, bay: float) -> void:
	match j:
		0:  # angled kick panel: floor vents
			_vent(B, xf, 0.0, 0.0, bay * 0.55, seg_len * 0.45, 6)
			_fbox(B, "trim_dark", xf, 0.0, seg_len * 0.42, bay - 0.04, 0.02, 0.012)
		1:  # vertical lower wall
			if k >= 2:
				_fbox(B, "panel", xf, 0.0, 0.05, bay * 0.7, seg_len * 0.55, 0.012)
				_led_row(B, xf, -bay * 0.25, seg_len * 0.36, 6, bay * 0.1, ["glow_green", "glow_green", "glow_amber", "led_off_green"], 0.012, 0.012)
				_fbox(B, "trim_dark", xf, -bay * 0.3, -0.1, 0.06, 0.14, 0.02, 0.012)
		2:  # angled upper wall: integrated light strip + panels
			_fbox(B, "trim_dark", xf, 0.0, seg_len * 0.4, bay - 0.06, 0.05, 0.012)
			_fbox(B, "glow_white", xf, 0.0, seg_len * 0.4, bay - 0.14, 0.018, 0.02)
			if k >= 2:
				_fbox(B, "hull_dark", xf, 0.0, -0.1, bay * 0.6, seg_len * 0.45, 0.015)
				_vent(B, xf, 0.0, -0.1, bay * 0.45, seg_len * 0.3, 7, 0.015)
		3:  # ceiling cove: round air vents
			for e: float in [-0.25, 0.25]:
				_fcyl(B, "trim_dark", xf, e * bay, 0.0, 0.07, 0.02, 16)
				_fcyl(B, "groove", xf, e * bay, 0.0, 0.055, 0.024, 16)
				for f in 4:
					var a := f * PI * 0.25
					var c := _sub(xf, e * bay, 0.0, 0.022)
					B.add_beam("trim", c * Vector3(cos(a) * -0.055, sin(a) * -0.055, 0), c * Vector3(cos(a) * 0.055, sin(a) * 0.055, 0), 0.008, 0.01, c.basis.z)


func _build_ribs() -> void:
	for zi in RIB_Z.size():
		var z: float = RIB_Z[zi]
		for s: float in [-1.0, 1.0]:
			for j in range(PROFILE.size() - 1):
				var p0: Vector2 = PROFILE[j]
				var p1: Vector2 = PROFILE[j + 1]
				var n := _seg_normal(p0, p1, s)
				var a := Vector3(s * p0.x, p0.y, z) + n * 0.06
				var b := Vector3(s * p1.x, p1.y, z) + n * 0.06
				B.add_beam("hull_dark", a, b, 0.16, 0.12, n)
				B.add_beam("trim", a + n * 0.062, b + n * 0.062, 0.05, 0.006, n)
				if j == 2:
					var m := (a + b) * 0.5 + n * 0.065
					B.add_beam("glow_blue", m - (b - a).normalized() * 0.15, m + (b - a).normalized() * 0.15, 0.03, 0.008, n)
				# bolts
				for f: float in [0.2, 0.8]:
					var bp := a.lerp(b, f) + n * 0.062
					B.add_box("trim", bp + Vector3(0, 0, 0.05), Vector3(0.018, 0.018, 0.018))
					B.add_box("trim", bp + Vector3(0, 0, -0.05), Vector3(0.018, 0.018, 0.018))
		# ceiling cross beam
		B.add_beam("hull_dark", Vector3(-1.95, CEIL - 0.06, z), Vector3(1.95, CEIL - 0.06, z), 0.16, 0.12, Vector3.DOWN)
		B.add_beam("trim", Vector3(-1.9, CEIL - 0.122, z), Vector3(1.9, CEIL - 0.122, z), 0.05, 0.006, Vector3.DOWN)


# =====================================================================
# CEILING
# =====================================================================
func _build_ceiling() -> void:
	B.add_box("groove", Vector3(0, CEIL + 0.06, (Z_JOIN + Z_REAR) * 0.5), Vector3(3.9, 0.04, Z_REAR - Z_JOIN))
	var strips := [[-1.9, -0.6], [-0.6, 0.6], [0.6, 1.9]]
	for k in range(RIB_Z.size() - 1):
		var z0: float = RIB_Z[k] + 0.08
		var z1: float = RIB_Z[k + 1] - 0.08
		var zm := (z0 + z1) * 0.5
		var bay := z1 - z0
		for st in strips:
			var x0: float = st[0]
			var x1: float = st[1]
			B.add_box("hull", Vector3((x0 + x1) * 0.5, CEIL + 0.02, zm), Vector3(x1 - x0 - 0.03, 0.04, bay - 0.03))
		# light panels
		for s: float in [-1.0, 1.0]:
			B.add_box("trim_dark", Vector3(s * 1.2, CEIL - 0.005, zm), Vector3(0.36, 0.02, bay - 0.2))
			B.add_box("glow_white", Vector3(s * 1.2, CEIL - 0.016, zm), Vector3(0.26, 0.012, bay - 0.32))
			B.add_box("trim", Vector3(s * 1.2, CEIL - 0.022, zm), Vector3(0.012, 0.004, bay - 0.3))
			# vent grille near the cove
			if k >= 2:
				B.add_box("trim_dark", Vector3(s * 1.68, CEIL - 0.005, zm), Vector3(0.28, 0.02, bay * 0.5))
				for f in 8:
					B.add_box("hull_dark", Vector3(s * 1.68, CEIL - 0.02, zm - bay * 0.22 + f * bay * 0.063), Vector3(0.24, 0.02, 0.018))
		if k >= 2:
			# rear ceiling: central cable tray + hatch
			B.add_box("hull_dark", Vector3(0, CEIL - 0.03, zm), Vector3(0.7, 0.04, bay - 0.1))
			B.add_box("panel", Vector3(0, CEIL - 0.055, zm), Vector3(0.6, 0.02, bay * 0.6))
			for f in 4:
				B.add_box("trim", Vector3(-0.27 + f * 0.18, CEIL - 0.068, zm - bay * 0.3), Vector3(0.02, 0.008, 0.02))
	# longitudinal support beams
	for s: float in [-1.0, 1.0]:
		B.add_beam("hull_dark", Vector3(s * 0.62, CEIL - 0.07, Z_JOIN), Vector3(s * 0.62, CEIL - 0.07, Z_REAR), 0.1, 0.12, Vector3.DOWN)
		B.add_beam("glow_blue", Vector3(s * 0.62, CEIL - 0.132, 0.95), Vector3(s * 0.62, CEIL - 0.132, Z_REAR - 0.1), 0.02, 0.006, Vector3.DOWN)
		# conduit bundle along the cove
		var cove_n := _seg_normal(PROFILE[3], PROFILE[4], s)
		var base := Vector3(s * 2.28, 2.4, 0) + cove_n * 0.07
		for p in 3:
			var off := Vector3(0, -0.06 * p, 0) + Vector3(s * 0.035 * p, 0, 0)
			var key := "trim_dark" if p != 1 else "red_paint"
			B.add_cyl_between(key, base + off + Vector3(0, 0, Z_JOIN + 0.12), base + off + Vector3(0, 0, Z_REAR - 0.12), 0.024, 8, true)
		for zi in RIB_Z.size():
			var z: float = RIB_Z[zi]
			B.add_box("trim", base + Vector3(s * 0.03, -0.06, z + 0.11), Vector3(0.14, 0.2, 0.03))


# =====================================================================
# CANOPY: panoramic front + angled side windows
# =====================================================================
func _build_canopy() -> void:
	var rings := []
	for y in RING_Y:
		var row := []
		for th in THETAS:
			row.append(ring_point(th, y))
		rings.append(row)
	var cabin_c := Vector3(0, 1.4, -1.0)
	var nf := THETAS.size() - 1
	# glass panes
	for r in 2:
		for i in nf:
			var a: Vector3 = rings[r][i]
			var b: Vector3 = rings[r][i + 1]
			var c: Vector3 = rings[r + 1][i + 1]
			var d: Vector3 = rings[r + 1][i]
			var n := _orient_normal(_quad_normal(a, b, d), cabin_c - (a + c) * 0.5)
			G.add_quad("glass", a, b, c, d, n)
	# horizontal mullions (sill, transom, header)
	for r in 3:
		for i in nf:
			var a: Vector3 = rings[r][i]
			var b: Vector3 = rings[r][i + 1]
			var out := Vector3((a + b).x * 0.5, 0, (a + b).z * 0.5 - ZC).normalized()
			var w := 0.16 if r == 0 else (0.09 if r == 1 else 0.14)
			var h := 0.18 if r == 0 else 0.13
			B.add_beam("trim_dark", a, b, w, h, out)
			X.add_beam("hull_ext_dark", a + out * 0.09, b + out * 0.09, w + 0.03, 0.05, out)
			if r == 1:
				B.add_beam("glow_blue", a - out * 0.07 + Vector3(0, -0.03, 0), b - out * 0.07 + Vector3(0, -0.03, 0), 0.012, 0.006, out)
	# vertical mullions / A-pillars
	for i in THETAS.size():
		var pillar := i == 0 or i == THETAS.size() - 1
		for r in 2:
			var a: Vector3 = rings[r][i]
			var b: Vector3 = rings[r + 1][i]
			var out := Vector3(a.x, 0, a.z - ZC).normalized()
			if pillar:
				out = Vector3(signf(a.x), 0, -0.3).normalized()
			var w := 0.24 if pillar else 0.1
			var h := 0.22 if pillar else 0.14
			B.add_beam("trim_dark" if not pillar else "hull_dark", a, b, w, h, out)
			X.add_beam("hull_ext_dark", a + out * 0.1, b + out * 0.1, w + 0.04, 0.06, out)
		for r in 3:
			var p: Vector3 = rings[r][i]
			var out2 := Vector3(p.x, 0, p.z - ZC).normalized()
			B.add_box_xf("trim", Transform3D(Basis.looking_at(-out2, Vector3.UP), p - out2 * 0.04), Vector3(0.15, 0.15, 0.1))
	# interior nose wall below the sill
	for i in nf:
		var a := ring_point(THETAS[i], 0.0)
		var b := ring_point(THETAS[i + 1], 0.0)
		var c := ring_point(THETAS[i + 1], 1.0)
		var d := ring_point(THETAS[i], 1.0)
		var n := _orient_normal(_quad_normal(a, b, d), cabin_c - (a + c) * 0.5)
		B.add_slab("hull", MeshBatcher.shrink([a, b, c, d], 0.01), n, 0.05)
	# front ceiling (fan above the canopy header)
	var poly := []
	for i in THETAS.size():
		poly.append(rings[2][i] + Vector3(0, 0.05, 0))
	poly.append(Vector3(1.9, CEIL, Z_JOIN))
	poly.append(Vector3(-1.9, CEIL, Z_JOIN))
	B.add_slab("hull_dark", poly, Vector3.DOWN, 0.08)
	# header light strip
	for i in range(1, nf - 1):
		var a: Vector3 = rings[2][i]
		var b: Vector3 = rings[2][i + 1]
		var inn := -Vector3((a + b).x * 0.5, 0, (a + b).z * 0.5 - ZC).normalized()
		B.add_beam("glow_cyan", a + inn * 0.09 + Vector3(0, 0.0, 0), b + inn * 0.09, 0.02, 0.01, Vector3.DOWN)


# =====================================================================
# MAIN INSTRUMENT PANEL (dashboard)
# =====================================================================
const DASH_MODES := [3, 1, 0, 5, 6]   # orbit, telemetry, nav, propulsion, sensors
const DASH_NAMES := ["ORBITAL", "TELEMETRY", "NAV / FLIGHT", "PROPULSION", "SENSORS"]


func _deck_y(d: float, din: float, ylow: float, yhigh: float) -> float:
	return ylow + (din - d) / (din - DASH_OUT) * (yhigh - ylow)


func _build_dashboard() -> void:
	for i in range(THETAS.size() - 1):
		var t0: float = THETAS[i]
		var t1: float = THETAS[i + 1]
		var side_shelf := i == 0 or i == THETAS.size() - 2
		var din := 0.62 if side_shelf else DASH_IN
		var ylow := 0.86 if side_shelf else 0.80
		var yhigh := 0.97
		# deck top
		var ia := dash_pt(t0, din, ylow)
		var ib := dash_pt(t1, din, ylow)
		var ob := dash_pt(t1, DASH_OUT, yhigh)
		var oa := dash_pt(t0, DASH_OUT, yhigh)
		var dn := _quad_normal(ia, ib, oa)
		if dn.y < 0.0:
			dn = -dn
		B.add_slab("console", [ia, ib, ob, oa], dn, 0.05)
		# upper fascia (pilot side)
		var fa := dash_pt(t0, din, 0.45)
		var fb := dash_pt(t1, din, 0.45)
		var fmidp := (fa + fb + ia + ib) * 0.25
		var fn := _orient_normal(_quad_normal(fa, fb, ia), Vector3(0, fmidp.y, ZC + 0.6) - fmidp)
		B.add_slab("panel", [fa, fb, ib, ia], fn, 0.04)
		# knee recess ceiling + lower kick
		var ka := dash_pt(t0, din - 0.3, 0.45)
		var kb := dash_pt(t1, din - 0.3, 0.45)
		B.add_slab("console", [fa, fb, kb, ka], Vector3.DOWN, 0.03)
		var la := dash_pt(t0, din - 0.3, 0.0)
		var lb := dash_pt(t1, din - 0.3, 0.0)
		B.add_slab("hull_dark", [la, lb, kb, ka], fn, 0.04)
		_fbox(B, "trim_dark", _frame_n((la + kb) * 0.5, lb - la, Vector3.UP, fn), 0.0, -0.17, (lb - la).length() - 0.04, 0.06, 0.012)
		# filler between deck and nose wall
		B.add_slab("console", [oa, ob, dash_pt(t1, DASH_OUT, 0.0), dash_pt(t0, DASH_OUT, 0.0)], fn, 0.03)

		# ---- details on the deck ----
		var dmid := (ia + ib + oa + ob) * 0.25
		var right := (ib - ia).normalized()
		var up := ((oa + ob) * 0.5 - (ia + ib) * 0.5).normalized()
		var dxf := _frame_n(dmid, right, up, dn)
		var dlen := ((oa + ob) * 0.5 - (ia + ib) * 0.5).length()
		var chord := (ib - ia).length()
		# fascia frame
		var fmid := (fa + fb + ia + ib) * 0.25
		var fxf := _frame_n(fmid, right, Vector3.UP, fn)
		B.add_beam("glow_blue", ia + fn * 0.005 + Vector3(0, -0.012, 0), ib + fn * 0.005 + Vector3(0, -0.012, 0), 0.012, 0.006, fn)
		B.add_beam("trim", ia + Vector3(0, 0.005, 0), ib + Vector3(0, 0.005, 0), 0.03, 0.02, dn)

		if side_shelf:
			var sid := "L" if t0 < 0.0 else "R"
			_button_grid(B, dxf, -chord * 0.25, dlen * 0.2, 4, 3, 0.05, 0.045, 0.035, 0.03, ["btn", "btn_light", "glow_dim", "glow_amber"])
			_switch_row(B, dxf, chord * 0.05, dlen * 0.2, 4, 0.045)
			_gauge(B, dxf, chord * 0.12, -dlen * 0.2, 0.045)
			for k in 3:
				_add_control("RCS_%s%d" % [sid, k + 1], "switch", dxf, -chord * 0.28 + k * 0.07, -dlen * 0.22, Vector3(0.03, 0.05, 0.05), "green", 0.0, "RCS QUAD %s%d" % [sid, k + 1])
			_label("RCS / AUX", dxf, -chord * 0.18, -dlen * 0.38, 26)
			_led_row(B, fxf, -0.18, 0.08, 8, 0.05, ["glow_green", "glow_amber", "led_off_green", "glow_blue"])
			_vent(B, fxf, 0.0, -0.06, chord * 0.6, 0.12, 5)
			continue

		var si := i - 1   # 0..4 screen index
		# screen housing standing on the deck, tilted back toward the windows
		var d_screen := 0.70
		var pb := dash_pt((t0 + t1) * 0.5, d_screen, _deck_y(d_screen, din, ylow, yhigh) + 0.02)
		var horiz := Vector3(up.x, 0, up.z).normalized()
		var scr_up := (Vector3.UP * 0.9 + horiz * 0.42).normalized()
		var sh := 0.34
		var sw := (dash_pt(t1, d_screen, 0) - dash_pt(t0, d_screen, 0)).length() * 0.8
		var sxf := _frame_n(pb + scr_up * (sh * 0.5 + 0.045), right, scr_up, Vector3(-horiz.x, 0, -horiz.z))
		_fbox(B, "console", sxf, 0.0, 0.0, sw + 0.08, sh + 0.1, 0.06, -0.06)
		_add_screen("DASH_%d" % (si + 1), sxf, 0.0, 0.0, sw, sh, DASH_MODES[si])
		# glare hood + strut
		_fbox(B, "console", sxf, 0.0, sh * 0.5 + 0.05, sw + 0.1, 0.018, 0.13, -0.02)
		_fbox(B, "glow_cyan", sxf, 0.0, sh * 0.5 + 0.04, sw * 0.9, 0.004, 0.004, 0.08)
		B.add_beam("seat_frame", sxf * Vector3(0, -sh * 0.2, -0.07), pb + horiz * 0.18, 0.05, 0.04, Vector3.UP)
		_label(DASH_NAMES[si], sxf, -sw * 0.5 + 0.06, sh * 0.5 + 0.075, 22, Color(0.55, 0.8, 1.0), 0.07)

		# controls between the screen and the pilot
		var near_v := -dlen * 0.5 + 0.11
		if si == 2:
			_add_control("MASTER_CAUTION", "warning", dxf, -0.13, near_v, Vector3(0.09, 0.05, 0.022), "amber", 0.0, "MASTER CAUTION")
			_add_control("MASTER_WARNING", "warning", dxf, 0.13, near_v, Vector3(0.09, 0.05, 0.022), "red", 0.0, "MASTER WARNING")
			_label("CAUTION", dxf, -0.13, near_v - 0.045, 20, Color(1, 0.75, 0.3))
			_label("WARNING", dxf, 0.13, near_v - 0.045, 20, Color(1, 0.4, 0.3))
			_add_control("AUTOPILOT", "button", dxf, 0.0, near_v, Vector3(0.06, 0.04, 0.02), "green", 0.0, "AUTOPILOT ENGAGE")
			_led_row(B, dxf, -0.22, near_v + 0.08, 12, 0.04, ["glow_green", "glow_green", "glow_cyan", "led_off_amber"])
		else:
			_button_grid(B, dxf, -chord * 0.36, near_v + 0.03, 3, 3, 0.042, 0.036, 0.032, 0.028, ["btn_light", "btn", "btn_light"])
			_switch_row(B, dxf, chord * 0.05, near_v + 0.01, 4, 0.04)
			var ids := ["NAV_MODE", "TLM_REC", "ENG_ARM", "SNS_LOCK"]
			var lbls := ["NAV MODE", "TELEMETRY RECORD", "ENGINE ARM", "SENSOR LOCK"]
			var cidx := si if si < 2 else si - 1
			_add_control(ids[cidx], "button", dxf, chord * 0.32, near_v + 0.01, Vector3(0.05, 0.04, 0.02), ["cyan", "blue", "amber", "green"][cidx], 0.0, lbls[cidx])
		# behind the screens: vent slots
		_vent(B, dxf, 0.0, dlen * 0.38, chord * 0.55, 0.06, 4)

		# fascia details
		_led_row(B, fxf, -chord * 0.4, 0.13, int(chord / 0.05), 0.05, ["glow_green", "glow_cyan", "led_off_green", "glow_amber", "led_off_amber"], 0.014)
		_fbox(B, "trim_dark", fxf, 0.0, 0.0, chord - 0.08, 0.12, 0.008)
		_knob(B, fxf, -chord * 0.3, 0.0, 0.02)
		_knob(B, fxf, -chord * 0.18, 0.0, 0.02)
		_gauge(B, fxf, chord * 0.22, 0.0, 0.045)
		_label(["FLT DIR", "DATA", "MASTER", "ENGINE", "SENSOR"][si], fxf, 0.0, -0.11, 22)


# =====================================================================
# CENTRE PEDESTAL
# =====================================================================
func _build_pedestal() -> void:
	var zf := -2.78
	var zr := -1.5
	B.add_box("console", Vector3(0, 0.33, (zf + zr) * 0.5), Vector3(0.56, 0.66, zr - zf))
	B.add_box("hull_dark", Vector3(0, 0.04, (zf + zr) * 0.5), Vector3(0.6, 0.08, zr - zf + 0.04))
	var top := [Vector3(-0.3, 0.66, zr), Vector3(0.3, 0.66, zr), Vector3(0.3, 0.79, zf), Vector3(-0.3, 0.79, zf)]
	var tn := _quad_normal(top[0], top[1], top[3])
	if tn.y < 0.0:
		tn = -tn
	B.add_slab("panel", top, tn, 0.04)
	var txf := _frame_n((top[0] + top[2]) * 0.5, Vector3.RIGHT, top[3] - top[0], tn)
	var tl: float = (top[3] - top[0]).length()
	# side walls connect body to top
	for s: float in [-1.0, 1.0]:
		B.add_slab("console", [Vector3(s * 0.3, 0.66, zr), Vector3(s * 0.3, 0.79, zf), Vector3(s * 0.3, 0.6, zf), Vector3(s * 0.3, 0.6, zr)], Vector3(s, 0, 0), 0.02)
		var sxf := _frame_n(Vector3(s * 0.302, 0.35, (zf + zr) * 0.5), Vector3(0, 0, -s), Vector3.UP, Vector3(s, 0, 0))
		_vent(B, sxf, 0.25, -0.12, 0.36, 0.16, 6)
		_fbox(B, "glow_blue", sxf, 0.0, 0.25, zr - zf - 0.1, 0.012, 0.006)
		_fbox(B, "hull_dark", sxf, -0.3, 0.0, 0.34, 0.3, 0.012)
	# rear face
	var rxf := _frame_n(Vector3(0, 0.33, zr + 0.001), Vector3.RIGHT, Vector3.UP, Vector3(0, 0, 1))
	_vent(B, rxf, 0.0, 0.05, 0.4, 0.2, 6)
	_label("PEDESTAL", rxf, 0.0, 0.24, 20)
	# throttle quadrant
	_fbox(B, "trim_dark", txf, 0.0, -0.05, 0.4, 0.3, 0.01)
	_add_control("THROTTLE_1", "lever", txf, -0.08, -0.05, Vector3(0.05, 0.26, 0.03), "green", 0.01, "MAIN ENGINE 1 THROTTLE")
	_add_control("THROTTLE_2", "lever", txf, 0.08, -0.05, Vector3(0.05, 0.26, 0.03), "green", 0.01, "MAIN ENGINE 2 THROTTLE")
	for k in 6:
		_fbox(B, "glow_white", txf, -0.17, -0.17 + k * 0.05, 0.03, 0.004, 0.003, 0.01)
		_fbox(B, "glow_white", txf, 0.17, -0.17 + k * 0.05, 0.03, 0.004, 0.003, 0.01)
	_label("THR", txf, 0.0, 0.12, 22)
	# display + keypad
	_add_screen("PEDESTAL_DISP", txf, 0.0, tl * 0.5 - 0.17, 0.42, 0.23, 5, Vector2i(448, 256))
	_button_grid(B, txf, -0.2, -tl * 0.5 + 0.2, 6, 2, 0.08, 0.05, 0.06, 0.035, ["btn_light", "btn", "glow_dim"])
	B.add_sphere("chrome", txf * Vector3(0.19, -0.27, 0.02), 0.025)
	_fcyl(B, "trim_dark", txf, 0.19, -0.27, 0.035, 0.012, 16)
	_add_control("PARKING_BRAKE", "switch", txf, -0.2, -0.28, Vector3(0.03, 0.05, 0.05), "amber", 0.0, "DOCKING CLAMP")


# =====================================================================
# PILOT SEATS
# =====================================================================
func _build_seat(origin: Vector3, s: float) -> void:
	var o := origin
	# floor rails + base
	for x: float in [-0.22, 0.22]:
		B.add_box("seat_frame", o + Vector3(x, 0.02, 0.0), Vector3(0.05, 0.04, 0.8))
		B.add_box("trim_dark", o + Vector3(x, 0.045, 0.0), Vector3(0.02, 0.01, 0.78))
		for zz: float in [-0.4, 0.4]:
			B.add_box("trim", o + Vector3(x, 0.03, zz), Vector3(0.07, 0.05, 0.03))
	B.add_box("trim_dark", o + Vector3(0, 0.055, 0.0), Vector3(0.52, 0.03, 0.58))
	# pedestal column with hydraulic piston
	B.add_cyl_xf("seat_frame", Transform3D(Basis(), o + Vector3(0, 0.2, 0.0)), 0.095, 0.28, 18)
	B.add_cyl_xf("trim", Transform3D(Basis(), o + Vector3(0, 0.08, 0.0)), 0.13, 0.04, 18)
	B.add_cyl_xf("chrome", Transform3D(Basis(), o + Vector3(0, 0.37, 0.0)), 0.06, 0.08, 16)
	B.add_cyl_xf("trim_dark", Transform3D(Basis(), o + Vector3(0, 0.335, 0.0)), 0.1, 0.02, 16)
	# diagonal struts (mechanical supports)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			B.add_cyl_between("seat_frame", o + Vector3(sx * 0.2, 0.07, sz * 0.24), o + Vector3(sx * 0.13, 0.4, sz * 0.13), 0.016, 8)
			B.add_sphere("trim", o + Vector3(sx * 0.2, 0.075, sz * 0.24), 0.022, 8, 6)
	# seat pan frame + brackets
	B.add_box("seat_frame", o + Vector3(0, 0.425, 0.0), Vector3(0.56, 0.045, 0.56))
	for sx: float in [-1.0, 1.0]:
		B.add_box("seat_frame", o + Vector3(sx * 0.29, 0.47, 0.02), Vector3(0.03, 0.14, 0.5))
		B.add_box("trim_dark", o + Vector3(sx * 0.307, 0.47, 0.02), Vector3(0.006, 0.08, 0.36))
		# lever on the side
		B.add_cyl_between("chrome", o + Vector3(sx * 0.31, 0.45, -0.15), o + Vector3(sx * 0.33, 0.4, -0.27), 0.007, 6)
	# seat cushion: three stitched sections + waterfall front + bolsters
	for k in 3:
		var zz := -0.17 + k * 0.15
		B.add_superquad("seat", Transform3D(Basis(), o + Vector3(0, 0.505, zz)), Vector3(0.2, 0.055, 0.078), 0.32, 16, 10)
	B.add_superquad("seat", Transform3D(Basis(Vector3.RIGHT, -0.5), o + Vector3(0, 0.5, -0.27)), Vector3(0.2, 0.05, 0.045), 0.4, 16, 8)
	for sx: float in [-1.0, 1.0]:
		B.add_superquad("seat", Transform3D(Basis(Vector3.FORWARD, sx * 0.15), o + Vector3(sx * 0.245, 0.53, -0.02)), Vector3(0.05, 0.075, 0.25), 0.35, 12, 8)
		B.add_beam("seat_dark", o + Vector3(sx * 0.2, 0.505, -0.25), o + Vector3(sx * 0.2, 0.505, 0.2), 0.012, 0.11, Vector3.UP)
	# --- backrest (reclined) ---
	var bx := Transform3D(Basis(Vector3.RIGHT, 0.2), o + Vector3(0, 0.55, 0.26))
	B.add_superquad("trim_dark", bx * Transform3D(Basis(), Vector3(0, 0.38, 0.07)), Vector3(0.28, 0.42, 0.05), 0.25, 16, 10)
	B.add_superquad("seat_frame", bx * Transform3D(Basis(), Vector3(0, 0.36, 0.115)), Vector3(0.24, 0.36, 0.02), 0.2, 12, 8)
	for k in 4:
		B.add_superquad("seat", bx * Transform3D(Basis(), Vector3(0, 0.1 + k * 0.155, 0.0)), Vector3(0.19, 0.072, 0.065), 0.32, 16, 10)
	for sx: float in [-1.0, 1.0]:
		B.add_superquad("seat", bx * Transform3D(Basis(Vector3.UP, -sx * 0.25), Vector3(sx * 0.235, 0.36, -0.03)), Vector3(0.055, 0.33, 0.085), 0.35, 12, 12)
		B.add_beam("seat_dark", bx * Vector3(sx * 0.19, 0.04, -0.02), bx * Vector3(sx * 0.19, 0.66, -0.02), 0.012, 0.1, bx.basis.z)
		# headrest posts
		B.add_cyl_between("chrome", bx * Vector3(sx * 0.08, 0.72, 0.03), bx * Vector3(sx * 0.08, 0.84, 0.03), 0.009, 8)
		# shoulder harness
		B.add_beam("rubber", bx * Vector3(sx * 0.1, 0.74, -0.07), bx * Vector3(sx * 0.12, 0.08, -0.075), 0.045, 0.008, -bx.basis.z)
		B.add_box_xf("chrome", bx * Transform3D(Basis(), Vector3(sx * 0.115, 0.3, -0.08)), Vector3(0.05, 0.03, 0.012))
		# recline gas strut
		B.add_cyl_between("chrome", o + Vector3(sx * 0.29, 0.43, 0.12), bx * Vector3(sx * 0.27, 0.32, 0.08), 0.012, 8)
	B.add_superquad("seat", bx * Transform3D(Basis(), Vector3(0, 0.9, 0.0)), Vector3(0.15, 0.085, 0.07), 0.35, 16, 10)
	B.add_superquad("trim_dark", bx * Transform3D(Basis(), Vector3(0, 0.9, 0.06)), Vector3(0.16, 0.09, 0.03), 0.3, 12, 8)
	B.add_cyl_xf("chrome", Transform3D(Basis(Vector3.FORWARD, PI * 0.5), o + Vector3(0, 0.55, 0.26)), 0.035, 0.6, 14)
	# lap belt + buckle
	B.add_beam("rubber", o + Vector3(-0.2, 0.57, -0.05), o + Vector3(0.2, 0.57, -0.05), 0.04, 0.008, Vector3.UP)
	B.add_box("chrome", o + Vector3(0, 0.575, -0.05), Vector3(0.07, 0.012, 0.06))
	# --- armrests ---
	for sx: float in [-1.0, 1.0]:
		var ax := sx * 0.34
		B.add_box("seat_frame", o + Vector3(ax, 0.6, 0.12), Vector3(0.04, 0.22, 0.06))
		B.add_box("seat_frame", o + Vector3(ax, 0.715, -0.04), Vector3(0.075, 0.03, 0.44))
		B.add_superquad("seat", Transform3D(Basis(), o + Vector3(ax, 0.755, -0.02)), Vector3(0.042, 0.028, 0.19), 0.35, 12, 8)
		B.add_box("trim", o + Vector3(ax, 0.7, -0.26), Vector3(0.08, 0.04, 0.06))
		var grip_base := o + Vector3(ax, 0.73, -0.28)
		if sx * s > 0.0:
			# side-stick controller
			B.add_cyl_xf("trim_dark", Transform3D(Basis(), grip_base + Vector3(0, 0.025, 0)), 0.035, 0.03, 14)
			B.add_cyl_xf("rubber", Transform3D(Basis(), grip_base + Vector3(0, 0.05, 0)), 0.03, 0.02, 14, true, 0.015)
			B.add_cyl_between("chrome", grip_base + Vector3(0, 0.05, 0), grip_base + Vector3(0, 0.12, -0.01), 0.011, 8)
			B.add_superquad("rubber", Transform3D(Basis(Vector3.RIGHT, -0.25), grip_base + Vector3(0, 0.16, -0.015)), Vector3(0.024, 0.05, 0.03), 0.5, 10, 8)
			B.add_box("glow_red", grip_base + Vector3(0, 0.212, -0.02), Vector3(0.016, 0.008, 0.016))
			B.add_box("glow_amber", grip_base + Vector3(0.0, 0.18, -0.045), Vector3(0.01, 0.014, 0.008))
		else:
			# armrest keypad
			var kxf := _frame(grip_base + Vector3(0, 0.02, 0.02), Vector3.RIGHT, Vector3(0, 0, -1))
			_fbox(B, "trim_dark", kxf, 0.0, 0.0, 0.07, 0.1, 0.01)
			_button_grid(B, kxf, -0.018, 0.03, 2, 3, 0.036, 0.03, 0.026, 0.022, ["btn_light", "glow_dim"], 0.01)
	# footrest
	B.add_cyl_between("chrome", o + Vector3(-0.2, 0.14, -0.5), o + Vector3(0.2, 0.14, -0.5), 0.015, 8)
	for sx: float in [-1.0, 1.0]:
		B.add_cyl_between("seat_frame", o + Vector3(sx * 0.2, 0.14, -0.5), o + Vector3(sx * 0.2, 0.05, -0.36), 0.013, 8)
	var side := "L" if s < 0.0 else "R"
	var kp := _frame(o + Vector3(-s * 0.34, 0.77, -0.24), Vector3.RIGHT, Vector3(0, 0, -1))
	_add_control("SEAT_%s_COMMS" % side, "button", kp, 0.0, -0.06, Vector3(0.03, 0.02, 0.012), "cyan", 0.0, "PUSH-TO-TALK (%s SEAT)" % side)


# =====================================================================
# SIDE CONSOLES
# =====================================================================
func _build_side_consoles() -> void:
	var modes := {"L0": 2, "L1": 4, "R0": 3, "R1": 6}
	var titles := {"L0": "LIFE SUPPORT / ECLSS", "L1": "COMMUNICATIONS", "R0": "GUIDANCE / ORBIT", "R1": "SENSORS / TARGET"}
	var sw_names := {
		"L0": ["O2_FLOW", "CO2_SCRUB", "CABIN_FAN", "H2O_LOOP"], "L1": ["S_BAND", "UHF_LINK", "TDRS_LOCK", "RECORDER"],
		"R0": ["IMU_ALIGN", "STAR_TRKR", "GPS_RCVR", "ATT_HOLD"], "R1": ["LIDAR", "RADAR", "DOCK_CAM", "FLOODLIGHT"]}
	for s: float in [-1.0, 1.0]:
		var sid := "L" if s < 0.0 else "R"
		for k in 2:
			var key := "%s%d" % [sid, k]
			var z0: float = RIB_Z[k] + 0.1
			var z1: float = RIB_Z[k + 1] - 0.1
			var zm := (z0 + z1) * 0.5
			var length := z1 - z0
			# body
			B.add_box("console", Vector3(s * 2.6, 0.41, zm), Vector3(0.66, 0.82, length))
			B.add_box("hull_dark", Vector3(s * 2.29, 0.05, zm), Vector3(0.06, 0.1, length))
			var inward := Vector3(-s, 0, 0)
			var fxf := _frame_n(Vector3(s * 2.268, 0.45, zm), Vector3(0, 0, 1), Vector3.UP, inward)
			_fbox(B, "panel", fxf, 0.0, 0.05, length - 0.06, 0.62, 0.01)
			_vent(B, fxf, -length * 0.22, -0.12, length * 0.38, 0.24, 7, 0.01)
			_fbox(B, "hull_dark", fxf, length * 0.22, -0.12, length * 0.36, 0.28, 0.014, 0.01)
			_fbox(B, "trim", fxf, length * 0.22, -0.05, 0.12, 0.018, 0.02, 0.024)
			B.add_box("glow_blue", Vector3(s * 2.262, 0.8, zm), Vector3(0.008, 0.012, length - 0.08))
			# desk
			var desk := [Vector3(s * 2.2, 0.84, z0), Vector3(s * 2.2, 0.84, z1), Vector3(s * 2.92, 0.95, z1), Vector3(s * 2.92, 0.95, z0)]
			var dn := _quad_normal(desk[0], desk[1], desk[3])
			if dn.y < 0.0:
				dn = -dn
			B.add_slab("panel", desk, dn, 0.04)
			B.add_beam("trim", desk[0] + Vector3(0, 0.005, 0), desk[1] + Vector3(0, 0.005, 0), 0.03, 0.03, dn)
			var dxf := _frame_n((desk[0] + desk[2]) * 0.5, Vector3(0, 0, 1), desk[3] - desk[0], dn)
			_button_grid(B, dxf, -length * 0.38, 0.12, 4, 3, 0.045, 0.04, 0.034, 0.03, ["btn_light", "btn", "glow_dim", "btn_light"])
			_knob(B, dxf, length * 0.08, 0.13, 0.022)
			_knob(B, dxf, length * 0.17, 0.13, 0.022)
			_gauge(B, dxf, length * 0.33, 0.11, 0.05)
			var names: Array = sw_names[key]
			for q in 4:
				_add_control(names[q], "switch", dxf, -length * 0.36 + q * 0.07, -0.13, Vector3(0.03, 0.05, 0.05), ["green", "green", "cyan", "amber"][q], 0.0, names[q].replace("_", " "))
			_led_row(B, dxf, length * 0.05, -0.1, 6, 0.045, ["glow_green", "glow_amber", "led_off_green", "glow_cyan"])
			B.add_sphere("chrome", dxf * Vector3(length * 0.33, -0.14, 0.02), 0.026)
			# upright instrument panel
			var pa := Vector3(s * 2.88, 0.98, z0 + 0.03)
			var pb := Vector3(s * 2.88, 0.98, z1 - 0.03)
			var pc := Vector3(s * 2.70, 1.95, z1 - 0.03)
			var pd := Vector3(s * 2.70, 1.95, z0 + 0.03)
			var un := _orient_normal(_quad_normal(pa, pb, pd), inward)
			B.add_slab("console", [pa, pb, pc, pd], un, 0.05)
			var uxf := _frame_n((pa + pc) * 0.5, Vector3(0, 0, 1), pd - pa, un)
			var plen := (pd - pa).length()
			_fbox(B, "panel", uxf, 0.0, 0.0, length - 0.1, plen - 0.06, 0.008)
			_add_screen("SIDE_%s_%s" % [sid, "FWD" if k == 0 else "AFT"], uxf, 0.0, 0.14, minf(length - 0.28, 0.7), 0.4, modes[key], Vector2i(480, 288))
			_label(titles[key], uxf, 0.0, plen * 0.5 - 0.06, 24, Color(0.55, 0.8, 1.0), 0.01)
			_switch_row(B, uxf, -length * 0.3, -0.18, 8, length * 0.6 / 7.0, 0.008)
			_led_row(B, uxf, -length * 0.3, -0.3, 10, length * 0.6 / 9.0, ["glow_green", "glow_green", "glow_amber", "led_off_red", "glow_cyan"], 0.014, 0.008)
			for g in 2:
				_gauge(B, uxf, (-0.5 + g) * length * 0.42, -0.38, 0.045, 0.008)
			var warn_ids := {"L0": "O2_LOW", "L1": "COMM_LOSS", "R0": "NAV_FAULT", "R1": "PROXIMITY"}
			_add_control(warn_ids[key], "warning", uxf, 0.0, -0.38, Vector3(0.1, 0.045, 0.02), "amber" if k == 0 else "red", 0.008, str(warn_ids[key]).replace("_", " ") + " ANNUNCIATOR")
			# brackets to the wall
			for zz: float in [z0 + 0.08, z1 - 0.08]:
				B.add_beam("seat_frame", Vector3(s * 2.86, 1.6, zz), Vector3(s * 2.62, 1.75, zz), 0.03, 0.03, inward)


# =====================================================================
# OVERHEAD PANEL
# =====================================================================
func _build_overhead() -> void:
	var zf := -2.3
	var zr := 0.8
	var yb := 2.3
	var zm := (zf + zr) * 0.5
	var length := zr - zf
	var bottom := [Vector3(-0.36, yb, zf), Vector3(0.36, yb, zf), Vector3(0.36, yb, zr), Vector3(-0.36, yb, zr)]
	B.add_slab("panel", bottom, Vector3.DOWN, 0.03)
	for s: float in [-1.0, 1.0]:
		var q := [Vector3(s * 0.36, yb, zf), Vector3(s * 0.55, 2.52, zf), Vector3(s * 0.55, 2.52, zr), Vector3(s * 0.36, yb, zr)]
		var n := _orient_normal(_quad_normal(q[0], q[1], q[3]), Vector3(s, -1, 0))
		B.add_slab("console", q, n, 0.03)
		var sxf := _frame_n((q[0] + q[2]) * 0.5, Vector3(0, 0, 1), q[1] - q[0], n)
		# circuit-breaker rows
		for row in 2:
			for c in 26:
				_fcyl(B, "rubber" if (c + row) % 5 else "glow_white", sxf, -length * 0.45 + c * length * 0.9 / 25.0, -0.05 + row * 0.08, 0.009, 0.018, 8)
		_fbox(B, "glow_blue", sxf, 0.0, 0.11, length - 0.1, 0.008, 0.004)
	# end caps
	for zz: float in [zf, zr]:
		var nz := -1.0 if zz == zf else 1.0
		B.add_slab("console", [Vector3(-0.36, yb, zz), Vector3(0.36, yb, zz), Vector3(0.55, 2.52, zz), Vector3(-0.55, 2.52, zz)], Vector3(0, 0, nz), 0.03)
	B.add_box("hull_dark", Vector3(0, 2.56, zm), Vector3(1.1, 0.08, length))
	# bottom face, readable when looking up from the seats
	var bxf := _frame_n(Vector3(0, yb - 0.001, zm), Vector3.RIGHT, Vector3(0, 0, 1), Vector3.DOWN)
	var ann := ["FIRE_DETECT", "DEPRESS", "CO2_HIGH", "POWER_FAULT", "COOLANT_LEAK", "ENGINE_FAIL"]
	for i in ann.size():
		var u := -0.18 + (i % 3) * 0.18
		var v := -1.25 + (i / 3) * 0.08
		_add_control(ann[i], "warning", bxf, u, v, Vector3(0.15, 0.06, 0.015), "red" if i % 2 == 0 else "amber", 0.0, ann[i].replace("_", " ") + " ANNUNCIATOR")
	_label("ANNUNCIATORS", bxf, 0.0, -1.1, 22)
	var sw_ids := ["RED_ALERT", "CABIN_LIGHTS", "EXT_LIGHTS", "BEACON", "HEATERS", "BUS_TIE", "FUEL_XFEED", "APU_START"]
	for i in sw_ids.size():
		var u := -0.24 + (i % 4) * 0.16
		var v := -0.75 + (i / 4) * 0.2
		_add_control(sw_ids[i], "switch", bxf, u, v, Vector3(0.03, 0.05, 0.05), "red" if sw_ids[i] == "RED_ALERT" else "green", 0.0, sw_ids[i].replace("_", " "))
		_label(sw_ids[i].replace("_", " "), bxf, u, v - 0.06, 14)
	for g in 3:
		_gauge(B, bxf, -0.2 + g * 0.2, -0.25, 0.05)
	_button_grid(B, bxf, -0.28, 0.1, 8, 3, 0.08, 0.06, 0.06, 0.04, ["btn_light", "btn", "glow_dim", "btn_light", "glow_amber"])
	for r in 4:
		_switch_row(B, bxf, -0.3, 0.45 + r * 0.12, 9, 0.075)
	_led_row(B, bxf, -0.3, 0.95, 16, 0.04, ["glow_green", "glow_cyan", "led_off_green", "glow_amber"])
	_label("OVERHEAD SYSTEMS", bxf, 0.0, 1.35, 26)


# =====================================================================
# REAR CABIN: racks, jump seats, life-support panel, lockers
# =====================================================================
func _build_rear_section() -> void:
	for s: float in [-1.0, 1.0]:
		var sid := "L" if s < 0.0 else "R"
		var inward := Vector3(-s, 0, 0)
		# --- bay 2: equipment racks ---
		var z0: float = RIB_Z[2] + 0.1
		var z1: float = RIB_Z[3] - 0.1
		var zm := (z0 + z1) * 0.5
		var length := z1 - z0
		B.add_box("console", Vector3(s * 2.7, 1.0, zm), Vector3(0.5, 2.0, length))
		var rxf := _frame_n(Vector3(s * 2.449, 1.0, zm), Vector3(0, 0, 1), Vector3.UP, inward)
		_fbox(B, "trim_dark", rxf, 0.0, 0.0, length, 2.0, 0.01)
		for d in 5:
			var v := -0.78 + d * 0.32
			_fbox(B, "console_light" if d % 2 else "panel", rxf, 0.0, v, length - 0.08, 0.28, 0.02, 0.01)
			_fbox(B, "chrome", rxf, 0.0, v + 0.09, 0.25, 0.02, 0.02, 0.03)
			_led_row(B, rxf, -length * 0.4, v - 0.08, 8, 0.03, ["glow_green", "glow_green", "glow_amber", "led_off_green"], 0.01, 0.03)
			_vent(B, rxf, length * 0.25, v - 0.04, length * 0.3, 0.12, 4, 0.03)
		_fbox(B, "glow_cyan", rxf, 0.0, 0.88, length - 0.1, 0.01, 0.006, 0.01)
		_label("AVIONICS RACK %s" % sid, rxf, 0.0, 0.93, 22, Color(0.55, 0.8, 1.0), 0.012)
		_add_control("RACK_PWR_%s" % sid, "switch", rxf, -length * 0.3, 0.75, Vector3(0.03, 0.05, 0.05), "green", 0.03, "AVIONICS RACK %s POWER" % sid)

		# --- bay 3: jump seat + life support panel ---
		z0 = RIB_Z[3] + 0.1
		z1 = RIB_Z[4] - 0.1
		zm = (z0 + z1) * 0.5
		length = z1 - z0
		B.add_superquad("seat", Transform3D(Basis(), Vector3(s * 2.62, 0.5, zm)), Vector3(0.22, 0.055, 0.22), 0.32, 14, 8)
		B.add_superquad("seat", Transform3D(Basis(), Vector3(s * 2.86, 0.86, zm)), Vector3(0.055, 0.26, 0.2), 0.32, 10, 12)
		B.add_box("seat_frame", Vector3(s * 2.62, 0.43, zm), Vector3(0.46, 0.04, 0.46))
		for zz: float in [zm - 0.2, zm + 0.2]:
			B.add_beam("seat_frame", Vector3(s * 2.9, 0.42, zz), Vector3(s * 2.42, 0.42, zz), 0.03, 0.04, Vector3.UP)
			B.add_cyl_between("chrome", Vector3(s * 2.42, 0.42, zz), Vector3(s * 2.9, 0.75, zz), 0.01, 6)
		var j2a := Vector2(PROFILE[2])
		var j2b := Vector2(PROFILE[3])
		var n2 := _seg_normal(j2a, j2b, s)
		var pmid := Vector3(s * (j2a.x + j2b.x) * 0.5, (j2a.y + j2b.y) * 0.5, zm) + n2 * 0.03
		var pxf := _frame_n(pmid, Vector3(0, 0, 1), Vector3(s * (j2b.x - j2a.x), j2b.y - j2a.y, 0), n2)
		_fbox(B, "console", pxf, 0.0, 0.0, length - 0.1, 0.78, 0.03)
		_fbox(B, "panel", pxf, 0.0, 0.0, length - 0.16, 0.72, 0.008, 0.03)
		if s < 0.0:
			_label("LIFE SUPPORT", pxf, 0.0, 0.31, 26, Color(0.55, 0.8, 1.0), 0.04)
			for g in 3:
				_gauge(B, pxf, (-1 + g) * 0.25, 0.12, 0.07, 0.038)
			_add_control("LIFE_SUPPORT", "switch", pxf, -0.2, -0.15, Vector3(0.03, 0.05, 0.05), "green", 0.038, "LIFE SUPPORT BACKUP")
			_label("BACKUP", pxf, -0.2, -0.22, 18, Color(0.6, 0.85, 1.0), 0.04)
			_add_control("O2_PURGE", "button", pxf, 0.05, -0.15, Vector3(0.06, 0.04, 0.02), "amber", 0.038, "O2 PURGE")
			_add_control("CABIN_VENT", "button", pxf, 0.2, -0.15, Vector3(0.06, 0.04, 0.02), "cyan", 0.038, "CABIN VENT")
			_led_row(B, pxf, -0.27, -0.3, 12, 0.05, ["glow_green", "glow_green", "glow_cyan"], 0.012, 0.038)
		else:
			_label("POWER DISTRIBUTION", pxf, 0.0, 0.31, 26, Color(0.55, 0.8, 1.0), 0.04)
			_add_screen("POWER_DISP", _sub(pxf, 0, 0, 0.04), 0.0, 0.07, 0.5, 0.3, 1, Vector2i(400, 240))
			for q in 3:
				_add_control("BUS_%s" % ["A", "B", "C"][q], "switch", pxf, -0.15 + q * 0.15, -0.22, Vector3(0.03, 0.05, 0.05), "green", 0.038, "POWER BUS %s" % ["A", "B", "C"][q])

		# --- bay 4: lockers ---
		z0 = RIB_Z[4] + 0.1
		z1 = RIB_Z[5] - 0.12
		zm = (z0 + z1) * 0.5
		length = z1 - z0
		B.add_box("console", Vector3(s * 2.7, 1.04, zm), Vector3(0.5, 2.08, length))
		var lxf := _frame_n(Vector3(s * 2.449, 1.04, zm), Vector3(0, 0, 1), Vector3.UP, inward)
		for dd in 2:
			var u := (-0.5 + dd) * length * 0.5
			_fbox(B, "panel", lxf, u, 0.0, length * 0.5 - 0.03, 1.95, 0.02)
			_vent(B, lxf, u, 0.75, length * 0.35, 0.18, 5, 0.02)
			_fbox(B, "chrome", lxf, u + (0.18 if dd == 0 else -0.18) * length / 1.0, 0.0, 0.02, 0.22, 0.025, 0.02)
			_fbox(B, "glow_green", lxf, u, -0.82, 0.03, 0.01, 0.006, 0.02)
			_label("LOCKER %s%d" % [sid, dd + 1], lxf, u, 0.5, 18, Color(0.6, 0.8, 1.0), 0.024)
	# fire extinguisher + first aid on the rear bulkhead
	var ext := Vector3(1.3, 0.55, Z_REAR - 0.09)
	B.add_cyl_xf("red_paint", Transform3D(Basis(), ext), 0.07, 0.46, 16)
	B.add_sphere("red_paint", ext + Vector3(0, 0.23, 0), 0.07, 14, 8)
	B.add_cyl_xf("chrome", Transform3D(Basis(), ext + Vector3(0, 0.33, 0)), 0.025, 0.07, 10)
	B.add_cyl_between("rubber", ext + Vector3(0.0, 0.33, 0.0), ext + Vector3(0.11, 0.12, -0.02), 0.01, 6)
	B.add_box("seat_frame", ext + Vector3(0, 0.0, 0.06), Vector3(0.18, 0.05, 0.04))
	B.add_box("seat_frame", ext + Vector3(0, 0.15, 0.06), Vector3(0.18, 0.04, 0.04))
	var aid := Vector3(-1.35, 1.45, Z_REAR - 0.06)
	B.add_box("white_paint", aid, Vector3(0.36, 0.26, 0.12))
	B.add_box("red_paint", aid + Vector3(0, 0, -0.062), Vector3(0.12, 0.035, 0.004))
	B.add_box("red_paint", aid + Vector3(0, 0, -0.062), Vector3(0.035, 0.12, 0.004))


# ---------------------------------------------------------------- clipping
func _clip(poly: Array, axis: int, value: float, keep_greater: bool) -> Array:
	var out := []
	var cnt := poly.size()
	for i in cnt:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % cnt]
		var ain: bool = (a[axis] >= value) == keep_greater
		var bin: bool = (b[axis] >= value) == keep_greater
		if ain:
			out.append(a)
		if ain != bin:
			var t: float = (value - a[axis]) / (b[axis] - a[axis])
			out.append(a.lerp(b, t))
	return out


func _cross_section() -> Array:
	var pts := []
	for p in PROFILE:
		pts.append(p)
	for i in range(PROFILE.size() - 1, -1, -1):
		var p: Vector2 = PROFILE[i]
		pts.append(Vector2(-p.x, p.y))
	return pts


func _build_rear_wall_and_door() -> void:
	var cs := _cross_section()
	var dw := 0.75
	var dh := 2.2
	var pieces := [_clip(cs, 0, -dw, false), _clip(cs, 0, dw, true)]
	pieces.append(_clip(_clip(_clip(cs, 0, -dw, true), 0, dw, false), 1, dh, true))
	for pc in pieces:
		var p3 := []
		for p in pc:
			var v2: Vector2 = p
			p3.append(Vector3(v2.x, v2.y, Z_REAR))
		B.add_slab("hull", p3, Vector3(0, 0, -1), 0.1)
	var wxf := _frame_n(Vector3(0, 0, Z_REAR), Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1))
	# raised wall panels
	for s: float in [-1.0, 1.0]:
		var u := -s * 1.65
		_fbox(B, "panel", wxf, u, 1.0, 1.2, 1.4, 0.02)
		_fbox(B, "hull_dark", wxf, u, 1.95, 1.4, 0.3, 0.025)
		_fbox(B, "glow_white", wxf, u, 1.95, 1.0, 0.02, 0.008, 0.025)
		_vent(B, wxf, u, 0.18, 0.8, 0.22, 6, 0.0)
	# door frame
	B.add_beam("hull_dark", Vector3(-dw - 0.06, 0, Z_REAR - 0.07), Vector3(-dw - 0.06, dh + 0.06, Z_REAR - 0.07), 0.14, 0.16, Vector3(0, 0, -1))
	B.add_beam("hull_dark", Vector3(dw + 0.06, 0, Z_REAR - 0.07), Vector3(dw + 0.06, dh + 0.06, Z_REAR - 0.07), 0.14, 0.16, Vector3(0, 0, -1))
	B.add_beam("hull_dark", Vector3(-dw - 0.13, dh + 0.07, Z_REAR - 0.07), Vector3(dw + 0.13, dh + 0.07, Z_REAR - 0.07), 0.16, 0.14, Vector3(0, 0, -1))
	for s: float in [-1.0, 1.0]:
		B.add_beam("glow_cyan", Vector3(s * (dw - 0.005), 0.05, Z_REAR - 0.146), Vector3(s * (dw - 0.005), dh, Z_REAR - 0.146), 0.012, 0.006, Vector3(0, 0, -1))
		for k in 7:
			B.add_box("hazard" if k % 2 == 0 else "trim_dark", Vector3(s * (dw + 0.06), 0.1 + k * 0.08, Z_REAR - 0.152), Vector3(0.1, 0.08, 0.006))
	B.add_beam("glow_cyan", Vector3(-dw, dh - 0.005, Z_REAR - 0.146), Vector3(dw, dh - 0.005, Z_REAR - 0.146), 0.012, 0.006, Vector3(0, 0, -1))
	var sign_l := _label("BRIDGE 6", wxf, 0.0, dh + 0.25, 64, Color(0.4, 0.85, 1.0), 0.02, 0.0012)
	sign_l.modulate = Color(0.5, 0.9, 1.0)
	# door halves (separate meshes, animated)
	_door_l = _make_door_half(-1.0, dw, dh)
	_door_r = _make_door_half(1.0, dw, dh)
	# door control panel
	_fbox(B, "console", wxf, -1.05, 1.2, 0.18, 0.3, 0.03)
	_fbox(B, "trim_dark", wxf, -1.05, 1.2, 0.14, 0.26, 0.006, 0.03)
	_button_grid(B, wxf, -1.09, 1.25, 3, 2, 0.04, 0.04, 0.03, 0.03, ["btn_light"], 0.036)
	var dc := _add_control("DOOR_CONTROL", "door", wxf, -1.05, 1.1, Vector3(0.08, 0.05, 0.02), "green", 0.036, "BRIDGE DOOR")
	dc.target = self
	dc.indicator = MeshInstance3D.new()
	dc.indicator.mesh = _box_mesh(Vector3(0.08, 0.05, 0.02))
	dc.indicator.material_override = mats["led_on_green"]
	dc.add_child(dc.indicator)
	dc.mat_on = mats["led_on_green"]
	dc.mat_off = mats["led_on_amber"]
	dc.refresh()
	_label("ACCESS", wxf, -1.05, 1.39, 18, Color(0.6, 0.85, 1.0), 0.036)


func _make_door_half(s: float, dw: float, dh: float) -> Node3D:
	var db := MeshBatcher.new(mats)
	var w := dw
	db.add_box("hull", Vector3(0, dh * 0.5, 0), Vector3(w, dh, 0.06))
	db.add_box("panel", Vector3(-s * 0.04, dh * 0.5, -0.032), Vector3(w - 0.16, dh - 0.2, 0.01))
	db.add_box("dark_glass", Vector3(-s * 0.05, dh * 0.72, -0.034), Vector3(0.12, 0.5, 0.012))
	db.add_box("trim_dark", Vector3(-s * w * 0.5 + s * 0.015, dh * 0.5, -0.035), Vector3(0.03, dh, 0.012))
	db.add_box("glow_blue", Vector3(-s * w * 0.5 + s * 0.015, dh * 0.5, -0.042), Vector3(0.006, dh * 0.8, 0.004))
	for k in 6:
		db.add_box("hazard" if k % 2 == 0 else "trim_dark", Vector3(s * 0.05, 0.1 + k * 0.06, -0.034), Vector3(w - 0.2, 0.06, 0.008))
	db.add_box("trim", Vector3(-s * 0.2, dh * 0.45, -0.04), Vector3(0.03, 0.25, 0.02))
	var mi := db.build("DoorHalf_%s" % ("L" if s < 0.0 else "R"))
	var holder := AnimatableBody3D.new()
	holder.collision_layer = 1
	holder.collision_mask = 2
	holder.sync_to_physics = false
	holder.name = mi.name
	holder.position = Vector3(s * w * 0.5, 0.0, Z_REAR + 0.05)
	holder.add_child(mi)
	add_child(holder)
	return holder


func _build_corridor() -> void:
	var z0 := Z_REAR + 0.1
	var z1 := 7.0
	var zm := (z0 + z1) * 0.5
	var length := z1 - z0
	B.add_box("grate", Vector3(0, -0.025, zm), Vector3(1.9, 0.05, length))
	B.add_box("hull_dark", Vector3(0, 2.38, zm), Vector3(1.9, 0.06, length))
	for s: float in [-1.0, 1.0]:
		B.add_box("hull", Vector3(s * 0.97, 1.18, zm), Vector3(0.08, 2.36, length))
		B.add_box("glow_cyan", Vector3(s * 0.88, 0.003, zm), Vector3(0.025, 0.008, length - 0.1))
		B.add_box("glow_white", Vector3(s * 0.45, 2.34, zm), Vector3(0.12, 0.012, length - 0.3))
		B.add_cyl_between("trim", Vector3(s * 0.88, 1.0, z0 + 0.2), Vector3(s * 0.88, 1.0, z1 - 0.2), 0.02, 8)
	for k in 5:
		var z := z0 + 0.3 + k * (length - 0.6) / 4.0
		for s: float in [-1.0, 1.0]:
			B.add_beam("hull_dark", Vector3(s * 0.9, 0.0, z), Vector3(s * 0.9, 2.32, z), 0.12, 0.1, Vector3(-s, 0, 0))
			B.add_beam("trim", Vector3(s * 0.88, 1.0, z), Vector3(s * 0.93, 1.0, z), 0.04, 0.04, Vector3.UP)
		B.add_beam("hull_dark", Vector3(-0.92, 2.3, z), Vector3(0.92, 2.3, z), 0.12, 0.1, Vector3.DOWN)
	# Return-side switch is reachable from the corridor after leaving the bridge.
	var return_xf := _frame_n(Vector3(-0.92, 1.2, 5.05), Vector3(0, 0, -1), Vector3.UP, Vector3.RIGHT)
	_fbox(B, "console", return_xf, 0, 0, 0.22, 0.32, 0.025)
	var return_control := _add_control("DOOR_CONTROL_REAR", "door", return_xf, 0, 0, Vector3(0.14, 0.16, 0.04), "green", 0.03, "RETURN TO BRIDGE")
	return_control.target = self
	var return_lamp := MeshInstance3D.new()
	return_lamp.mesh = _box_mesh(Vector3(0.14, 0.16, 0.04))
	return_control.add_child(return_lamp)
	return_control.indicator = return_lamp
	return_control.mat_on = mats["led_on_green"]
	return_control.mat_off = mats["led_on_amber"]
	return_control.refresh()
	_label("BRIDGE ACCESS", return_xf, 0, 0.25, 24, Color(0.5, 0.9, 1.0), 0.02)
	# far end: closed hatch
	B.add_box("hull", Vector3(0, 1.18, z1 + 0.04), Vector3(2.0, 2.4, 0.08))
	B.add_box("panel", Vector3(0, 1.05, z1 - 0.01), Vector3(0.9, 2.0, 0.03))
	B.add_box("glow_amber", Vector3(0, 2.1, z1 - 0.03), Vector3(0.6, 0.02, 0.01))
	B.add_cyl_xf("trim", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.05, z1 - 0.04)), 0.12, 0.04, 20)
	var cxf := _frame_n(Vector3(0, 0, z1 - 0.03), Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1))
	_label("ENGINEERING  ▸  DECK 2", cxf, 0.0, 2.2, 28, Color(1.0, 0.75, 0.35), 0.02)


# =====================================================================
# EXTERIOR SHELL
# =====================================================================
func _outer_loop() -> Array:
	var pts := []
	for p in OUTER_HALF:
		pts.append(p)
	pts.append(Vector2(0, ROOF_Y))
	for i in range(OUTER_HALF.size() - 1, -1, -1):
		var p: Vector2 = OUTER_HALF[i]
		pts.append(Vector2(-p.x, p.y))
	return pts


func _ext_panel_details(xf: Transform3D, w: float, h: float) -> void:
	var roll := rng.randf()
	if roll < 0.25:
		_fbox(X, "hull_ext_dark", xf, rng.randf_range(-w, w) * 0.2, rng.randf_range(-h, h) * 0.2, w * 0.35, h * 0.3, 0.035)
	elif roll < 0.4:
		_vent(X, xf, 0.0, 0.0, w * 0.4, h * 0.3, 5)
	elif roll < 0.55:
		for k in 3:
			_fbox(X, "hull_ext", xf, -w * 0.25 + k * w * 0.25, 0.0, w * 0.12, h * 0.5, 0.025)
	elif roll < 0.62:
		_fbox(X, "hull_ext_accent", xf, 0.0, 0.0, w * 0.8, 0.06, 0.012)


func _build_exterior() -> void:
	var loop := _outer_loop()
	var hc := Vector2(0, 1.25)
	var bays := [Z_JOIN, -0.2, 0.9, 2.0, 3.1, Z_HULL_REAR]
	var cnt := loop.size()
	for i in cnt:
		var p0: Vector2 = loop[i]
		var p1: Vector2 = loop[(i + 1) % cnt]
		var d := p1 - p0
		var n2 := Vector2(d.y, -d.x).normalized()
		if n2.dot((p0 + p1) * 0.5 - hc) < 0.0:
			n2 = -n2
		var n := Vector3(n2.x, n2.y, 0)
		X.add_slab("hull_ext_dark", [Vector3(p0.x, p0.y, Z_JOIN), Vector3(p1.x, p1.y, Z_JOIN), Vector3(p1.x, p1.y, Z_HULL_REAR), Vector3(p0.x, p0.y, Z_HULL_REAR)], n, 0.05)
		var segs := maxi(1, ceili(d.length() / 1.6))
		for k in range(bays.size() - 1):
			var z0: float = bays[k]
			var z1: float = bays[k + 1]
			for m in segs:
				var a := p0.lerp(p1, float(m) / segs)
				var b := p0.lerp(p1, float(m + 1) / segs)
				var q := [Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z0), Vector3(b.x, b.y, z1), Vector3(a.x, a.y, z1)]
				var off := n * 0.03
				var qq := []
				for v in MeshBatcher.shrink(q, 0.025):
					qq.append(v + off)
				X.add_slab("hull_ext", qq, n, 0.03)
				var mid: Vector3 = (q[0] + q[2]) * 0.5 + n * 0.03
				var pxf := _frame_n(mid, Vector3(0, 0, 1), Vector3(b.x - a.x, b.y - a.y, 0), n)
				_ext_panel_details(pxf, z1 - z0, (b - a).length())
	# accent stripe (burgundy, echoing the seats) + hull number
	for s: float in [-1.0, 1.0]:
		X.add_box("hull_ext_accent", Vector3(s * 3.255, 0.95, 1.55), Vector3(0.03, 0.14, 5.6))
		X.add_box("hull_ext_accent", Vector3(s * 3.255, 0.75, 1.55), Vector3(0.03, 0.05, 5.6))
		var lb := Label3D.new()
		lb.text = "BRIDGE-6"
		lb.font_size = 96
		lb.pixel_size = 0.004
		lb.modulate = Color(0.85, 0.88, 0.92)
		lb.shaded = true
		lb.transform = Transform3D(Basis(Vector3.UP, s * PI * 0.5), Vector3(s * 3.27, 1.5, 2.3))
		_labels_root.add_child(lb)

	# --- nose below the canopy ---
	var sill := []
	var chin := []
	var keel := []
	var top := []
	for th in THETAS:
		sill.append(_ext_pt(th, 0.95, 3.27, 3.2))
		chin.append(_ext_pt(th, 0.35, 3.15, 3.35))
		keel.append(_ext_pt(th, -0.45, 2.72, 2.9))
		top.append(_ext_pt(th, 2.6, 2.22, 2.05))
	var nose_c := Vector3(0, 0.8, -1.0)
	for i in range(THETAS.size() - 1):
		var rows := [[sill, chin], [chin, keel]]
		for rw in rows:
			var ra: Array = rw[0]
			var rb: Array = rw[1]
			var a: Vector3 = ra[i]
			var b: Vector3 = ra[i + 1]
			var c: Vector3 = rb[i + 1]
			var dd: Vector3 = rb[i]
			var n := _orient_normal(_quad_normal(a, b, dd), (a + c) * 0.5 - nose_c)
			X.add_slab("hull_ext_dark", [a, b, c, dd], n, 0.05)
			var qq := []
			for v in MeshBatcher.shrink([a, b, c, dd], 0.03):
				qq.append(v + n * 0.025)
			X.add_slab("hull_ext", qq, n, 0.025)
		# sill ledge (canopy coaming)
		var ga := ring_point(THETAS[i], 1.0)
		var gb := ring_point(THETAS[i + 1], 1.0)
		var sa: Vector3 = sill[i]
		var sb: Vector3 = sill[i + 1]
		X.add_slab("hull_ext", [ga, gb, sb, sa], Vector3.UP, 0.05)
		# header coaming
		var ta := ring_point(THETAS[i], 2.5)
		var tb := ring_point(THETAS[i + 1], 2.5)
		var ua: Vector3 = top[i]
		var ub: Vector3 = top[i + 1]
		X.add_slab("hull_ext_dark", [ta, tb, ub, ua], Vector3.UP, 0.04)
	# underside
	var under := []
	for p in keel:
		under.append(p)
	X.add_slab("hull_ext_dark", under, Vector3.DOWN, 0.05)
	# roof front
	var roof := []
	for p in top:
		roof.append(p)
	roof.append(Vector3(2.05, 2.85, Z_JOIN))
	roof.append(Vector3(0, ROOF_Y, Z_JOIN))
	roof.append(Vector3(-2.05, 2.85, Z_JOIN))
	X.add_slab("hull_ext", roof, Vector3.UP, 0.06)
	# A-pillar bulkheads
	for s: float in [-1.0, 1.0]:
		var pts := [ring_point(s * 84.0, 1.0), Vector3(s * _profile_x(OUTER_HALF, 0.95), 0.95, Z_JOIN),
			Vector3(s * _profile_x(OUTER_HALF, 1.8), 1.8, Z_JOIN), Vector3(s * _profile_x(OUTER_HALF, 2.6), 2.6, Z_JOIN),
			ring_point(s * 84.0, 2.5), ring_point(s * 84.0, 1.8)]
		X.add_slab("hull_ext_dark", pts, Vector3(0, 0, -1), 0.06)
		X.add_beam("hull_ext", Vector3(s * 3.1, 0.95, Z_JOIN - 0.05), Vector3(s * 2.45, 2.62, Z_JOIN - 0.05), 0.3, 0.14, Vector3(0, 0, -1))
	# chin sensor pod
	X.add_superquad("hull_ext_dark", Transform3D(Basis(), Vector3(0, -0.4, -3.45)), Vector3(0.45, 0.13, 0.38), 0.4, 16, 8)
	for k in 3:
		var lp := Vector3(-0.22 + k * 0.22, -0.45, -3.78)
		X.add_cyl_xf("dark_glass", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), lp), 0.06, 0.06, 16)
		X.add_cyl_xf("glow_cyan", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), lp + Vector3(0, 0, -0.031)), 0.025, 0.004, 12)
	# underside heat tiles
	for ix in range(-5, 5):
		for iz in 12:
			if (ix + iz) % 3 == 0:
				continue
			X.add_box("hull_ext_dark" if (ix * 7 + iz) % 4 else "trim_dark", Vector3(ix * 0.5 + 0.25, -0.505, -1.0 + iz * 0.45), Vector3(0.47, 0.012, 0.42))

	# --- dorsal spine, sensor dome, antennas, beacon ---
	X.add_box("hull_ext_dark", Vector3(0, ROOF_Y + 0.08, 1.8), Vector3(0.8, 0.22, 4.6))
	X.add_box("hull_ext", Vector3(0, ROOF_Y + 0.2, 1.8), Vector3(0.6, 0.06, 4.4))
	for k in 8:
		X.add_box("trim_dark", Vector3(0, ROOF_Y + 0.235, 0.0 + k * 0.5), Vector3(0.5, 0.02, 0.06))
	X.add_cyl_xf("trim", Transform3D(Basis(), Vector3(0, ROOF_Y + 0.25, -0.4)), 0.36, 0.08, 24)
	X.add_superquad("dark_glass", Transform3D(Basis(), Vector3(0, ROOF_Y + 0.3, -0.4)), Vector3(0.32, 0.26, 0.32), 1.0, 24, 12)
	X.add_cyl_between("trim", Vector3(0.45, ROOF_Y, 3.6), Vector3(0.45, ROOF_Y + 1.1, 3.6), 0.025, 8)
	X.add_cyl_between("trim", Vector3(-0.45, ROOF_Y, 3.2), Vector3(-0.45, ROOF_Y + 0.7, 3.2), 0.02, 8)
	X.add_superquad("hull_ext", Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(-0.45, ROOF_Y + 0.75, 3.2)), Vector3(0.28, 0.03, 0.28), 1.0, 20, 6)
	X.add_sphere("strobe", Vector3(0.45, ROOF_Y + 1.13, 3.6), 0.05)
	for k in 4:
		X.add_beam("trim", Vector3(0.45, ROOF_Y + 0.3 + k * 0.2, 3.6), Vector3(0.45 + 0.25 - k * 0.05, ROOF_Y + 0.3 + k * 0.2, 3.6), 0.012, 0.012, Vector3.UP)

	# --- side sponsons, nav lights, RCS quads ---
	for s: float in [-1.0, 1.0]:
		X.add_superquad("hull_ext", Transform3D(Basis(), Vector3(s * 3.45, 0.55, 1.8)), Vector3(0.35, 0.3, 1.9), 0.45, 16, 10)
		X.add_box("hull_ext_accent", Vector3(s * 3.79, 0.6, 1.8), Vector3(0.02, 0.07, 2.6))
		X.add_superquad("hull_ext_dark", Transform3D(Basis(), Vector3(s * 3.45, 0.55, -0.12)), Vector3(0.25, 0.2, 0.12), 0.6, 12, 8)
		X.add_sphere("nav_red" if s < 0.0 else "nav_green", Vector3(s * 3.5, 0.6, -0.25), 0.06)
		X.add_sphere("strobe", Vector3(s * 3.8, 0.55, 3.6), 0.04)
		for zz: float in [0.3, 3.7]:
			var rc := Vector3(s * 3.3, 2.0, zz)
			X.add_box("hull_ext_dark", rc, Vector3(0.24, 0.28, 0.3))
			for dir in [Vector3(s, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, -1)]:
				var dv: Vector3 = dir
				var tip := rc + dv * 0.24 + Vector3(s * 0.02, 0, 0)
				var basep := rc + dv * 0.12
				X.add_cyl_between("trim_dark", basep, tip, 0.045, 10)
				X.add_cyl_between("glow_blue", tip - dv * 0.01, tip + dv * 0.003, 0.03, 10)
		# viewport strip along the neck
		for k in 5:
			X.add_box("port_window", Vector3(s * 1.66, 1.8, 5.7 + k * 0.45), Vector3(0.02, 0.12, 0.22))

	# --- neck and main body (behind the bridge module) ---
	var stations := [[Z_HULL_REAR, 1.0], [5.6, 0.62], [8.2, 0.62], [8.2, 1.15], [9.0, 1.28], [14.5, 1.28], [15.2, 1.1]]
	var axis := Vector3(0, hc.y, 0)
	for k in range(stations.size() - 1):
		var za: float = stations[k][0]
		var sa: float = stations[k][1]
		var zb: float = stations[k + 1][0]
		var sb: float = stations[k + 1][1]
		for i in cnt:
			var p0: Vector2 = loop[i]
			var p1: Vector2 = loop[(i + 1) % cnt]
			var a := Vector3(hc.x + (p0.x - hc.x) * sa, hc.y + (p0.y - hc.y) * sa, za)
			var b := Vector3(hc.x + (p1.x - hc.x) * sa, hc.y + (p1.y - hc.y) * sa, za)
			var c := Vector3(hc.x + (p1.x - hc.x) * sb, hc.y + (p1.y - hc.y) * sb, zb)
			var dd := Vector3(hc.x + (p0.x - hc.x) * sb, hc.y + (p0.y - hc.y) * sb, zb)
			var n: Vector3
			if absf(zb - za) < 1e-3:
				n = Vector3(0, 0, -1) if sb > sa else Vector3(0, 0, 1)
			else:
				n = _orient_normal(_quad_normal(a, b, dd), (a + c) * 0.5 - (axis + Vector3(0, 0, (za + zb) * 0.5)))
			X.add_slab("hull_ext" if k != 1 else "hull_ext_dark", [a, b, c, dd], n, 0.05)
			if k == 4:
				# body panels detail
				var steps := 4
				for m in steps:
					var f0 := float(m) / steps
					var f1 := float(m + 1) / steps
					var q := [a.lerp(dd, f0), b.lerp(c, f0), b.lerp(c, f1), a.lerp(dd, f1)]
					var qq := []
					for v in MeshBatcher.shrink(q, 0.04):
						qq.append(v + n * 0.02)
					X.add_slab("hull_ext", qq, n, 0.02)
					if rng.randf() < 0.35:
						var mid: Vector3 = (q[0] + q[2]) * 0.5 + n * 0.02
						var pxf := _frame_n(mid, Vector3(0, 0, 1), b - a, n)
						_ext_panel_details(pxf, (q[3] - q[0]).length(), (b - a).length())
	# rear cap + engines
	var last: Array = stations[stations.size() - 1]
	var zl: float = last[0]
	var sl: float = last[1]
	var cap := []
	for p in loop:
		var v2: Vector2 = p
		cap.append(Vector3(hc.x + (v2.x - hc.x) * sl, hc.y + (v2.y - hc.y) * sl, zl))
	X.add_slab("hull_ext_dark", cap, Vector3(0, 0, 1), 0.05)
	for s: float in [-1.0, 1.0]:
		var ec := Vector3(s * 1.45, 1.25, zl + 0.5)
		var exf := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), ec)
		X.add_cyl_xf("trim_dark", exf, 0.62, 1.0, 28, false, 0.8)
		X.add_cyl_xf("hull_ext_dark", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), ec + Vector3(0, 0, -0.55)), 0.66, 0.2, 28)
		X.add_cyl_xf("engine", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), ec + Vector3(0, 0, 0.3)), 0.62, 0.04, 28)
		X.add_cyl_xf("trim", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), ec + Vector3(0, 0, 0.45)), 0.25, 0.25, 16)
	X.add_cyl_xf("hull_ext", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 2.4, 12.0)), 0.5, 4.0, 20)
	for k in 6:
		for s: float in [-1.0, 1.0]:
			X.add_box("trim", Vector3(s * 2.3, 1.25, 9.6 + k * 0.8), Vector3(1.2, 0.04, 0.5))


# =====================================================================
# LIGHTING
# =====================================================================
func _build_lights() -> void:
	var specs := [
		[Vector3(0, 2.2, -0.6), Color(0.75, 0.85, 1.0), 1.0, 4.5],
		[Vector3(0, 2.2, 1.5), Color(0.75, 0.85, 1.0), 0.9, 4.5],
		[Vector3(0, 2.2, 3.4), Color(0.75, 0.85, 1.0), 0.8, 4.0],
		[Vector3(0, 1.25, -2.3), Color(0.3, 0.6, 1.0), 1.1, 2.8],
		[Vector3(-2.2, 1.5, -0.2), Color(0.35, 0.6, 1.0), 0.6, 2.4],
		[Vector3(2.2, 1.5, -0.2), Color(0.35, 0.6, 1.0), 0.6, 2.4],
		[Vector3(0, 2.0, 5.6), Color(0.6, 0.85, 1.0), 0.7, 3.0],
	]
	for sp in specs:
		var l := OmniLight3D.new()
		l.position = sp[0]
		l.light_color = sp[1]
		l.light_energy = sp[2]
		l.omni_range = sp[3]
		l.shadow_enabled = false
		add_child(l)
		interior_lights.append(l)
		_light_base.append([sp[1], sp[2]])
	var spot := SpotLight3D.new()
	spot.position = Vector3(0, 2.25, -1.4)
	spot.rotation = Vector3(-PI * 0.5, 0, 0)
	spot.spot_angle = 55.0
	spot.spot_range = 3.5
	spot.light_energy = 1.4
	spot.light_color = Color(0.85, 0.9, 1.0)
	spot.shadow_enabled = true
	add_child(spot)
	interior_lights.append(spot)
	_light_base.append([spot.light_color, spot.light_energy])
	# exterior floodlight on the hull number
	for s: float in [-1.0, 1.0]:
		var fl := SpotLight3D.new()
		fl.position = Vector3(s * 4.6, 2.4, 4.2)
		fl.spot_range = 4.0
		fl.spot_angle = 35.0
		fl.light_energy = 1.2
		add_child(fl)
		fl.look_at(Vector3(s * 3.25, 1.3, 2.0), Vector3.UP)


func _apply_light_mode() -> void:
	for i in interior_lights.size():
		var l: Light3D = interior_lights[i]
		var base: Array = _light_base[i]
		l.light_color = base[0]
		l.light_energy = float(base[1]) * (1.0 if _cabin_lights else 0.15)


# =====================================================================
# ANIMATION
# =====================================================================
func _process(delta: float) -> void:
	_time += delta
	# nav lights / strobes
	if mats.has("nav_red"):
		var blink := fmod(_time, 1.4) < 0.18
		mats["nav_red"].emission_energy_multiplier = 6.0 if blink else 0.8
		mats["nav_green"].emission_energy_multiplier = 6.0 if blink else 0.8
		mats["strobe"].emission_energy_multiplier = 14.0 if fmod(_time + 0.7, 2.0) < 0.08 else 0.3
	# red-alert lighting
	if _red_alert:
		var pulse := 0.55 + 0.45 * sin(_time * 5.0)
		for i in interior_lights.size():
			var l: Light3D = interior_lights[i]
			l.light_color = Color(1.0, 0.12, 0.08)
			l.light_energy = float(_light_base[i][1]) * pulse * (1.0 if _cabin_lights else 0.4)
	# slow planet rotation
	if _env.has("planet"):
		var p: Node3D = _env["planet"]
		p.rotate_y(delta * 0.004)


func _doorway_occupied() -> bool:
	for body in get_tree().get_nodes_in_group("player"):
		var local := to_local(body.global_position)
		if absf(local.x) < 1.0 and absf(local.z - (Z_REAR + 0.05)) < 0.65 and local.y < 2.3:
			return true
	return false


func _physics_process(delta: float) -> void:
	if not _door_open and _door_t > 0.0 and _doorway_occupied():
		set_door_open(true)
	# door
	var target := 1.0 if _door_open else 0.0
	_door_t = move_toward(_door_t, target, delta * 1.6)
	if _door_l != null:
		var e := _door_t * _door_t * (3.0 - 2.0 * _door_t)
		_door_l.position.x = -0.375 - e * 0.72
		_door_r.position.x = 0.375 + e * 0.72

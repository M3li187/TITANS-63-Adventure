extends Control
## Procedurally drawn cockpit display. Each instance lives inside its own
## SubViewport whose texture is shown on a 3D screen in the cockpit.
## Pages: navigation radar, telemetry graphs, ship systems, orbital map,
## communications log, propulsion gauges, sensor targeting.

enum Mode { NAV, TELEMETRY, SYSTEMS, ORBIT, COMMS, PROPULSION, SENSORS }
const MODE_NAMES := ["NAVIGATION", "TELEMETRY", "SHIP SYSTEMS", "ORBITAL MAP", "COMMS", "PROPULSION", "SENSORS"]

const C_BG := Color(0.015, 0.06, 0.15)
const C_PANEL := Color(0.04, 0.16, 0.34)
const C_GRID := Color(0.15, 0.4, 0.7, 0.45)
const C_LINE := Color(0.35, 0.85, 1.0)
const C_TEXT := Color(0.82, 0.95, 1.0)
const C_DIM := Color(0.42, 0.62, 0.85)
const C_AMBER := Color(1.0, 0.72, 0.2)
const C_RED := Color(1.0, 0.28, 0.22)
const C_GREEN := Color(0.35, 1.0, 0.55)

var mode: int = Mode.NAV
var screen_name: String = "DISPLAY"
var alert := false
var alert_text := "WARNING"
var seed_offset := 0.0
var t := 0.0
var _accum := 0.0
var font: Font
var data := {}   ## free-form values a mission script may set, e.g. data["ALT"] = 412.0


func _ready() -> void:
	font = ThemeDB.fallback_font


func cycle_mode() -> void:
	mode = (mode + 1) % MODE_NAMES.size()
	queue_redraw()


func set_alert(active: bool, text: String = "WARNING") -> void:
	alert = active
	alert_text = text
	queue_redraw()


func _process(delta: float) -> void:
	t += delta
	_accum += delta
	if _accum >= 1.0 / 15.0:
		_accum = 0.0
		queue_redraw()


func _txt(pos: Vector2, s: String, sz: int = 14, col: Color = C_TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	draw_string(font, pos, s, align, width, sz, col)


func _val(key: String, base: float, amp: float, speed: float) -> float:
	if data.has(key):
		return float(data[key])
	return base + amp * sin((t + seed_offset) * speed) + amp * 0.3 * sin((t + seed_offset) * speed * 3.7)


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), C_BG)
	for i in 10:
		draw_rect(Rect2(0, h * i / 10.0, w, h / 10.0), Color(0.06, 0.18, 0.38, 0.025 * i))
	# header
	draw_rect(Rect2(0, 0, w, 26), C_PANEL)
	draw_line(Vector2(0, 26), Vector2(w, 26), C_LINE, 1.5)
	_txt(Vector2(10, 19), MODE_NAMES[mode], 15, C_TEXT)
	var secs := int(t + seed_offset * 60.0)
	_txt(Vector2(w - 170, 19), "%s  T+%02d:%02d:%02d" % [screen_name, (secs / 3600) % 24, (secs / 60) % 60, secs % 60], 12, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 160)
	var r := Rect2(8, 32, w - 16, h - 52)
	match mode:
		Mode.NAV: _draw_nav(r)
		Mode.TELEMETRY: _draw_telemetry(r)
		Mode.SYSTEMS: _draw_systems(r)
		Mode.ORBIT: _draw_orbit(r)
		Mode.COMMS: _draw_comms(r)
		Mode.PROPULSION: _draw_propulsion(r)
		Mode.SENSORS: _draw_sensors(r)
	# footer soft-key labels
	var keys := ["MENU", "PAGE", "ZOOM", "MARK", "DATA", "SYS"]
	var kw := w / keys.size()
	for i in keys.size():
		draw_rect(Rect2(i * kw + 3, h - 17, kw - 6, 14), Color(0.05, 0.2, 0.4, 0.8))
		_txt(Vector2(i * kw + 3, h - 6), keys[i], 10, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, kw - 6)
	# frame + corner brackets
	draw_rect(Rect2(1, 1, w - 2, h - 2), Color(C_LINE, 0.55), false, 2.0)
	for c in [Vector2(4, 4), Vector2(w - 4, 4), Vector2(4, h - 4), Vector2(w - 4, h - 4)]:
		var sx := 1.0 if c.x < w * 0.5 else -1.0
		var sy := 1.0 if c.y < h * 0.5 else -1.0
		draw_line(c, c + Vector2(14 * sx, 0), C_LINE, 2.0)
		draw_line(c, c + Vector2(0, 14 * sy), C_LINE, 2.0)
	if alert and fmod(t, 1.0) < 0.65:
		draw_rect(Rect2(0, h * 0.38, w, h * 0.24), Color(0.45, 0.04, 0.02, 0.88))
		draw_rect(Rect2(0, h * 0.38, w, h * 0.24), C_RED, false, 3.0)
		_txt(Vector2(0, h * 0.5 + 9), alert_text, 26, C_AMBER, HORIZONTAL_ALIGNMENT_CENTER, w)


# ---------------------------------------------------------------- pages
func _draw_nav(r: Rect2) -> void:
	var rad := r.size.y * 0.46
	var c := r.position + Vector2(rad + 6, r.size.y * 0.5)
	for k in 4:
		draw_arc(c, rad * (k + 1) / 4.0, 0, TAU, 64, C_GRID, 1.5, true)
	draw_line(c - Vector2(rad, 0), c + Vector2(rad, 0), C_GRID, 1.0)
	draw_line(c - Vector2(0, rad), c + Vector2(0, rad), C_GRID, 1.0)
	for k in 36:
		var a := TAU * k / 36.0
		var l := 8.0 if k % 3 == 0 else 4.0
		draw_line(c + Vector2(cos(a), sin(a)) * rad, c + Vector2(cos(a), sin(a)) * (rad - l), C_DIM, 1.0)
	var sweep := (t + seed_offset) * 1.4
	for k in 18:
		var a := sweep - k * 0.03
		draw_line(c, c + Vector2(cos(a), sin(a)) * rad, Color(C_LINE, 0.5 * (1.0 - k / 18.0)), 2.0)
	for b in 7:
		var ang := float(b) * 2.1 + seed_offset
		var dist := rad * (0.25 + 0.7 * fposmod(sin(b * 12.9898) * 43758.5453, 1.0))
		var p := c + Vector2(cos(ang), sin(ang)) * dist
		var since := fposmod(sweep - ang, TAU)
		var a := clampf(1.0 - since / TAU, 0.15, 1.0)
		var col := C_AMBER if b == 2 else C_GREEN
		draw_circle(p, 4.0, Color(col, a))
		if b == 2:
			draw_rect(Rect2(p - Vector2(9, 9), Vector2(18, 18)), Color(C_AMBER, a), false, 1.5)
	draw_circle(c, 4.0, C_LINE)
	# heading tape
	var x0 := c.x + rad + 20
	var tw := r.end.x - x0
	var hdg := fposmod(_val("HDG", 274.0, 6.0, 0.2), 360.0)
	draw_rect(Rect2(x0, r.position.y, tw, 30), Color(0.03, 0.12, 0.25))
	for k in range(-6, 7):
		var deg := floori(hdg / 5.0) * 5 + k * 5
		var px := x0 + tw * 0.5 + (deg - hdg) * tw / 70.0
		if px < x0 or px > x0 + tw:
			continue
		var big := deg % 15 == 0
		draw_line(Vector2(px, r.position.y + 30), Vector2(px, r.position.y + (14 if big else 22)), C_DIM, 1.0)
		if big:
			_txt(Vector2(px - 15, r.position.y + 12), "%03d" % (posmod(deg, 360)), 11, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, 30)
	draw_colored_polygon(PackedVector2Array([Vector2(x0 + tw * 0.5, r.position.y + 30), Vector2(x0 + tw * 0.5 - 6, r.position.y + 38), Vector2(x0 + tw * 0.5 + 6, r.position.y + 38)]), C_AMBER)
	var y := r.position.y + 62
	var rows := [
		["HDG", "%05.1f°" % hdg], ["VEL", "%.3f km/s" % _val("VEL", 7.66, 0.01, 0.3)],
		["ALT", "%.1f km" % _val("ALT", 412.0, 1.5, 0.15)], ["RANGE", "%.2f km" % _val("RANGE", 18.4, 0.4, 0.1)],
		["TGT", "DOCK-A / ISS"], ["ETA", "00:%02d:%02d" % [int(t / 60.0 + 14) % 60, int(59 - fmod(t, 60.0))]],
	]
	for row in rows:
		_txt(Vector2(x0, y), row[0], 13, C_DIM)
		_txt(Vector2(x0 + 58, y), row[1], 15, C_TEXT)
		y += 22


func _draw_series(r: Rect2, phase: float, speed: float, col: Color, amp: float, offset: float) -> void:
	var pts := PackedVector2Array()
	var n := 90
	for i in n:
		var x := r.position.x + r.size.x * i / float(n - 1)
		var q := float(i) * 0.12 + (t + seed_offset) * speed + phase
		var v := sin(q) * 0.6 + sin(q * 2.7 + 1.3) * 0.25 + sin(q * 6.1) * 0.08
		pts.append(Vector2(x, r.position.y + r.size.y * (0.5 - offset) - v * r.size.y * amp))
	draw_polyline(pts, col, 2.0, true)


func _draw_telemetry(r: Rect2) -> void:
	var g := Rect2(r.position + Vector2(40, 4), r.size - Vector2(48, 30))
	draw_rect(g, Color(0.02, 0.09, 0.2))
	for i in 9:
		var x := g.position.x + g.size.x * i / 8.0
		draw_line(Vector2(x, g.position.y), Vector2(x, g.end.y), C_GRID, 1.0)
	for i in 6:
		var yy := g.position.y + g.size.y * i / 5.0
		draw_line(Vector2(g.position.x, yy), Vector2(g.end.x, yy), C_GRID, 1.0)
		_txt(Vector2(r.position.x, yy + 4), "%d" % (100 - i * 20), 11, C_DIM)
	_draw_series(g, 0.0, 1.2, C_LINE, 0.28, 0.12)
	_draw_series(g, 2.0, 0.8, C_GREEN, 0.18, -0.12)
	_draw_series(g, 4.0, 2.0, C_AMBER, 0.1, -0.3)
	var ly := r.end.y - 6
	_txt(Vector2(g.position.x, ly), "■ REACTOR OUT", 11, C_LINE)
	_txt(Vector2(g.position.x + g.size.x * 0.34, ly), "■ BUS VOLT", 11, C_GREEN)
	_txt(Vector2(g.position.x + g.size.x * 0.64, ly), "■ COOLANT ΔT", 11, C_AMBER)


func _draw_systems(r: Rect2) -> void:
	# ship schematic (top view)
	var s := r.size.y * 0.9
	var o := r.position + Vector2(10, r.size.y * 0.05)
	var outline := PackedVector2Array([
		Vector2(0.5, 0.0), Vector2(0.75, 0.12), Vector2(0.82, 0.35), Vector2(0.82, 0.62), Vector2(0.95, 0.7),
		Vector2(0.95, 0.88), Vector2(0.62, 0.92), Vector2(0.62, 1.0), Vector2(0.38, 1.0), Vector2(0.38, 0.92),
		Vector2(0.05, 0.88), Vector2(0.05, 0.7), Vector2(0.18, 0.62), Vector2(0.18, 0.35), Vector2(0.25, 0.12), Vector2(0.5, 0.0)])
	var pts := PackedVector2Array()
	for p in outline:
		pts.append(o + p * Vector2(s * 0.62, s))
	draw_polyline(pts, C_LINE, 2.0, true)
	var zones := [Vector2(0.5, 0.22), Vector2(0.5, 0.5), Vector2(0.3, 0.78), Vector2(0.7, 0.78)]
	for i in zones.size():
		var zp: Vector2 = o + zones[i] * Vector2(s * 0.62, s)
		var ok := not (alert and i == 1)
		draw_circle(zp, 7.0, C_GREEN if ok else C_RED)
	var x0 := o.x + s * 0.62 + 24
	var bw := r.end.x - x0 - 60
	var names := ["MAIN POWER", "O2 PRESSURE", "CO2 SCRUBBER", "COOLANT", "HULL INTEGRITY", "SHIELDS", "COMMS ARRAY"]
	var y := r.position.y + 6
	for i in names.size():
		var v := clampf(_val("SYS%d" % i, 0.78 - i * 0.04, 0.06, 0.3 + i * 0.1), 0.05, 1.0)
		if alert and i == 1:
			v = 0.28 + 0.05 * sin(t * 3.0)
		var col := C_GREEN if v > 0.6 else (C_AMBER if v > 0.35 else C_RED)
		_txt(Vector2(x0, y + 11), names[i], 11, C_DIM)
		draw_rect(Rect2(x0, y + 14, bw, 8), Color(0.05, 0.15, 0.3))
		draw_rect(Rect2(x0, y + 14, bw * v, 8), col)
		_txt(Vector2(x0 + bw + 6, y + 23), "%3d%%" % int(v * 100), 13, col)
		y += maxf(26.0, (r.size.y - 10) / names.size())


func _draw_orbit(r: Rect2) -> void:
	var c := r.position + Vector2(r.size.x * 0.36, r.size.y * 0.5)
	var pr := r.size.y * 0.2
	draw_circle(c, pr, Color(0.05, 0.2, 0.45))
	draw_arc(c, pr, 0, TAU, 64, C_LINE, 2.0, true)
	draw_arc(c, pr * 1.08, 0, TAU, 64, Color(C_LINE, 0.3), 3.0, true)
	var a := r.size.y * 0.44
	var b := r.size.y * 0.34
	var pts := PackedVector2Array()
	for i in 97:
		var th := TAU * i / 96.0
		pts.append(c + Vector2(cos(th) * a + a * 0.25, sin(th) * b).rotated(0.3))
	draw_polyline(pts, C_GREEN, 1.8, true)
	var th2 := (t + seed_offset) * 0.25
	var ship := c + Vector2(cos(th2) * a + a * 0.25, sin(th2) * b).rotated(0.3)
	draw_circle(ship, 5.0, C_AMBER)
	draw_arc(ship, 10.0, 0, TAU, 24, C_AMBER, 1.5, true)
	var ap := c + Vector2(a * 1.25, 0).rotated(0.3)
	var pe := c + Vector2(-a * 0.75, 0).rotated(0.3)
	_txt(ap + Vector2(6, -4), "AP", 12, C_TEXT)
	_txt(pe + Vector2(-26, -4), "PE", 12, C_TEXT)
	draw_circle(ap, 3.0, C_TEXT)
	draw_circle(pe, 3.0, C_TEXT)
	var x0 := r.position.x + r.size.x * 0.72
	var y := r.position.y + 18
	for row in [["APOAPSIS", "%.1f km" % _val("AP", 418.2, 0.2, 0.1)], ["PERIAPSIS", "%.1f km" % _val("PE", 406.7, 0.2, 0.1)],
			["INCL", "51.64°"], ["PERIOD", "92m 41s"], ["Δv REQ", "%.1f m/s" % _val("DV", 12.4, 0.3, 0.2)]]:
		_txt(Vector2(x0, y), row[0], 11, C_DIM)
		_txt(Vector2(x0, y + 17), row[1], 15, C_TEXT)
		y += 38


func _draw_comms(r: Rect2) -> void:
	var wv := Rect2(r.position, Vector2(r.size.x, r.size.y * 0.32))
	draw_rect(wv, Color(0.02, 0.09, 0.2))
	var pts := PackedVector2Array()
	for i in 120:
		var x := wv.position.x + wv.size.x * i / 119.0
		var q := i * 0.35 + t * 9.0
		var env := 0.5 + 0.5 * sin(t * 1.3 + i * 0.05)
		pts.append(Vector2(x, wv.position.y + wv.size.y * 0.5 + sin(q) * sin(q * 0.37) * wv.size.y * 0.42 * env))
	draw_polyline(pts, C_GREEN, 1.5, true)
	_txt(wv.position + Vector2(6, 14), "S-BAND 2287.5 MHz   SNR %.1f dB" % _val("SNR", 18.0, 2.0, 0.6), 11, C_DIM)
	var log_lines := [
		"CAPCOM> Bridge 6, you are GO for approach.", "BRIDGE6> Copy, initiating burn sequence.",
		"TDRS-12> Link established, 2.1 Mbps.", "FLIGHT> Confirm cabin pressure nominal.",
		"BRIDGE6> Cabin at 101.3 kPa, all green.", "CAPCOM> Stand by for state vector update.",
		"GNC> State vector uplink complete.", "CAPCOM> Next AOS in 12 minutes.",
		"EECOM> Fuel cell 2 trending warm.", "BRIDGE6> Acknowledged, monitoring.",
	]
	var first := int(t / 2.5 + seed_offset) % log_lines.size()
	var y := wv.end.y + 20
	var lines := int((r.end.y - y) / 18.0) + 1
	for i in lines:
		var ln: String = log_lines[(first + i) % log_lines.size()]
		_txt(Vector2(r.position.x + 4, y), ln, 13, C_TEXT if i == lines - 1 else C_DIM)
		y += 18


func _draw_gauge(c: Vector2, rad: float, v: float, title: String, unit: String) -> void:
	draw_arc(c, rad, PI * 0.75, PI * 2.25, 48, Color(0.1, 0.25, 0.45), 8.0, true)
	var col := C_GREEN if v < 0.75 else (C_AMBER if v < 0.9 else C_RED)
	draw_arc(c, rad, PI * 0.75, PI * 0.75 + PI * 1.5 * v, 48, col, 8.0, true)
	for k in 11:
		var a := PI * 0.75 + PI * 1.5 * k / 10.0
		draw_line(c + Vector2(cos(a), sin(a)) * (rad - 12), c + Vector2(cos(a), sin(a)) * (rad - 6), C_DIM, 1.0)
	_txt(c + Vector2(-rad, 6), "%d" % int(v * 100), 22, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, rad * 2)
	_txt(c + Vector2(-rad, 22), unit, 10, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, rad * 2)
	_txt(c + Vector2(-rad, rad + 14), title, 11, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, rad * 2)


func _draw_propulsion(r: Rect2) -> void:
	var rad := minf(r.size.y * 0.32, r.size.x * 0.13)
	var titles := ["MAIN ENG 1", "MAIN ENG 2", "RCS PRESS"]
	for i in 3:
		var c := r.position + Vector2(r.size.x * (0.16 + 0.27 * i), r.size.y * 0.42)
		_draw_gauge(c, rad, clampf(_val("ENG%d" % i, 0.62 + i * 0.08, 0.06, 0.5 + i * 0.2), 0.0, 1.0), titles[i], "% RATED")
	var x0 := r.position.x + r.size.x * 0.84
	var bh := r.size.y * 0.75
	for k in 2:
		var bx := x0 + k * 26
		var v := clampf(_val("FUEL%d" % k, 0.7 - k * 0.15, 0.01, 0.05), 0.0, 1.0)
		draw_rect(Rect2(bx, r.position.y + 6, 16, bh), Color(0.05, 0.15, 0.3))
		draw_rect(Rect2(bx, r.position.y + 6 + bh * (1.0 - v), 16, bh * v), C_LINE)
		_txt(Vector2(bx - 6, r.position.y + bh + 22), ["LOX", "LH2"][k], 10, C_DIM)


func _draw_sensors(r: Rect2) -> void:
	var c := r.position + r.size * 0.5
	# perspective grid
	for i in 11:
		var x := r.position.x + r.size.x * i / 10.0
		draw_line(Vector2(c.x, r.position.y + r.size.y * 0.35), Vector2(x, r.end.y), C_GRID, 1.0)
	for k in 7:
		var f := pow(k / 6.0, 1.8)
		var yy := r.position.y + r.size.y * (0.35 + 0.65 * f)
		draw_line(Vector2(r.position.x, yy), Vector2(r.end.x, yy), C_GRID, 1.0)
	var tp := c + Vector2(sin(t * 0.5 + seed_offset) * r.size.x * 0.25, cos(t * 0.37) * r.size.y * 0.18 - 10)
	var bs := 26.0 + 4.0 * sin(t * 2.0)
	draw_rect(Rect2(tp - Vector2(bs, bs), Vector2(bs * 2, bs * 2)), C_AMBER, false, 2.0)
	draw_line(tp - Vector2(bs + 10, 0), tp - Vector2(bs - 6, 0), C_AMBER, 2.0)
	draw_line(tp + Vector2(bs - 6, 0), tp + Vector2(bs + 10, 0), C_AMBER, 2.0)
	draw_circle(tp, 3.0, C_AMBER)
	draw_arc(c, 40, 0, TAU, 48, C_LINE, 1.5, true)
	draw_line(c - Vector2(60, 0), c - Vector2(44, 0), C_LINE, 2.0)
	draw_line(c + Vector2(44, 0), c + Vector2(60, 0), C_LINE, 2.0)
	draw_line(c - Vector2(0, 60), c - Vector2(0, 44), C_LINE, 2.0)
	draw_line(c + Vector2(0, 44), c + Vector2(0, 60), C_LINE, 2.0)
	_txt(tp + Vector2(bs + 6, -bs), "OBJ-07", 12, C_AMBER)
	_txt(tp + Vector2(bs + 6, -bs + 15), "%.2f km" % _val("TRANGE", 3.4, 0.3, 0.4), 12, C_TEXT)
	_txt(r.position + Vector2(4, 14), "LIDAR  ACTIVE   GAIN 0.82   FOV 24°", 11, C_DIM)

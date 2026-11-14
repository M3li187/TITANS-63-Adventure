extends RefCounted
## Shared material library + procedurally generated panel textures.
## Every surface in the cockpit uses one of these (shared) materials so the
## MeshBatcher can merge geometry per material.


static func _std(col: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	return m


static func _textured(col: Color, metal: float, rough: float, maps: Array, scale: float, normal_strength: float) -> StandardMaterial3D:
	var m := _std(col, metal, rough)
	m.albedo_texture = maps[0]
	m.normal_enabled = true
	m.normal_texture = maps[1]
	m.normal_scale = normal_strength
	m.uv1_scale = Vector3(scale, scale, scale)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


static func _glow(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col.darkened(0.4)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.roughness = 0.35
	return m


static func _led_off(col: Color) -> StandardMaterial3D:
	var m := _std(col.darkened(0.82), 0.0, 0.35)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.08
	return m


## Recursive rectangle split used for the panel-seam texture.
static func _split(r: Rect2i, depth: int, rng: RandomNumberGenerator, out: Array) -> void:
	if depth <= 0 or r.size.x < 48 or r.size.y < 48:
		out.append(r)
		return
	if r.size.x >= r.size.y:
		var cut := int(r.size.x * rng.randf_range(0.35, 0.65)) / 8 * 8
		_split(Rect2i(r.position, Vector2i(cut, r.size.y)), depth - 1, rng, out)
		_split(Rect2i(r.position + Vector2i(cut, 0), Vector2i(r.size.x - cut, r.size.y)), depth - 1, rng, out)
	else:
		var cut := int(r.size.y * rng.randf_range(0.35, 0.65)) / 8 * 8
		_split(Rect2i(r.position, Vector2i(r.size.x, cut)), depth - 1, rng, out)
		_split(Rect2i(r.position + Vector2i(0, cut), Vector2i(r.size.x, r.size.y - cut)), depth - 1, rng, out)


## Greyscale albedo + normal map with panel seams, bevels, rivets and vents.
static func make_panel_maps(size: int, seed_value: int, depth: int, seam: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var alb := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var hgt := Image.create(size, size, false, Image.FORMAT_RGBA8)
	alb.fill(Color(0.32, 0.32, 0.32))
	hgt.fill(Color(0.15, 0.15, 0.15))
	var rects := []
	_split(Rect2i(0, 0, size, size), depth, rng, rects)
	for rr in rects:
		var r: Rect2i = rr
		var tone := rng.randf_range(0.72, 0.92)
		var inner := r.grow(-seam)
		if inner.size.x <= 4 or inner.size.y <= 4:
			continue
		alb.fill_rect(inner, Color(tone, tone, tone))
		hgt.fill_rect(inner, Color(0.7, 0.7, 0.7))
		var core := inner.grow(-3)
		hgt.fill_rect(core, Color(0.62, 0.62, 0.62))
		# rivets in the corners
		if inner.size.x > 40 and inner.size.y > 40:
			for cx in [inner.position.x + 6, inner.end.x - 9]:
				for cy in [inner.position.y + 6, inner.end.y - 9]:
					alb.fill_rect(Rect2i(cx, cy, 3, 3), Color(tone + 0.06, tone + 0.06, tone + 0.06))
					hgt.fill_rect(Rect2i(cx, cy, 3, 3), Color(0.95, 0.95, 0.95))
		var roll := rng.randf()
		if roll < 0.18 and inner.size.x > 60 and inner.size.y > 40:
			# vent slots
			var slots := 5
			for k in slots:
				var y := inner.position.y + 10 + k * 7
				if y + 3 > inner.end.y - 6:
					break
				alb.fill_rect(Rect2i(inner.position.x + 12, y, inner.size.x - 24, 3), Color(0.15, 0.15, 0.15))
				hgt.fill_rect(Rect2i(inner.position.x + 12, y, inner.size.x - 24, 3), Color(0.25, 0.25, 0.25))
		elif roll < 0.32 and inner.size.x > 50 and inner.size.y > 50:
			# inset access hatch
			var h := inner.grow(-12)
			hgt.fill_rect(h, Color(0.5, 0.5, 0.5))
			alb.fill_rect(h.grow(-2), Color(tone - 0.05, tone - 0.05, tone - 0.05))
	alb.generate_mipmaps()
	hgt.bump_map_to_normal_map(4.0)
	hgt.generate_mipmaps()
	return [ImageTexture.create_from_image(alb), ImageTexture.create_from_image(hgt)]


## Tread-plate texture for the deck plates.
static func make_tread_maps(size: int) -> Array:
	var alb := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var hgt := Image.create(size, size, false, Image.FORMAT_RGBA8)
	alb.fill(Color(0.75, 0.75, 0.75))
	hgt.fill(Color(0.4, 0.4, 0.4))
	var step := 16
	for gy in size / step:
		for gx in size / step:
			var px := gx * step
			var py := gy * step
			if (gx + gy) % 2 == 0:
				hgt.fill_rect(Rect2i(px + 3, py + 6, 10, 4), Color(0.85, 0.85, 0.85))
				alb.fill_rect(Rect2i(px + 3, py + 6, 10, 4), Color(0.86, 0.86, 0.86))
			else:
				hgt.fill_rect(Rect2i(px + 6, py + 3, 4, 10), Color(0.85, 0.85, 0.85))
				alb.fill_rect(Rect2i(px + 6, py + 3, 4, 10), Color(0.86, 0.86, 0.86))
	alb.generate_mipmaps()
	hgt.bump_map_to_normal_map(3.0)
	hgt.generate_mipmaps()
	return [ImageTexture.create_from_image(alb), ImageTexture.create_from_image(hgt)]


static func build() -> Dictionary:
	var m := {}
	var hull_maps := make_panel_maps(512, 1977, 5, 2)
	var fine_maps := make_panel_maps(512, 2077, 6, 2)
	var tread := make_tread_maps(256)

	# --- interior structure: metallic dark blue-grey ---
	m["hull"] = _textured(Color(0.30, 0.36, 0.45), 0.65, 0.48, hull_maps, 0.55, 0.7)
	m["hull_dark"] = _textured(Color(0.16, 0.19, 0.25), 0.6, 0.5, hull_maps, 0.55, 0.7)
	m["panel"] = _textured(Color(0.38, 0.44, 0.54), 0.55, 0.42, fine_maps, 1.1, 0.5)
	m["console"] = _std(Color(0.17, 0.20, 0.26), 0.45, 0.45)
	m["console_light"] = _std(Color(0.42, 0.47, 0.55), 0.5, 0.4)
	m["trim"] = _std(Color(0.55, 0.60, 0.67), 0.9, 0.28)
	m["trim_dark"] = _std(Color(0.08, 0.09, 0.11), 0.7, 0.4)
	m["chrome"] = _std(Color(0.82, 0.84, 0.88), 1.0, 0.12)
	m["rubber"] = _std(Color(0.035, 0.035, 0.04), 0.0, 0.85)
	m["floor"] = _textured(Color(0.24, 0.27, 0.32), 0.75, 0.5, tread, 2.5, 0.6)
	m["grate"] = _std(Color(0.11, 0.13, 0.16), 0.8, 0.45)
	m["groove"] = _std(Color(0.02, 0.025, 0.03), 0.3, 0.8)
	m["hazard"] = _std(Color(0.85, 0.65, 0.08), 0.2, 0.5)
	m["red_paint"] = _std(Color(0.6, 0.05, 0.04), 0.3, 0.35)
	m["white_paint"] = _std(Color(0.85, 0.86, 0.88), 0.1, 0.4)
	m["btn"] = _std(Color(0.12, 0.13, 0.15), 0.1, 0.45)
	m["btn_light"] = _std(Color(0.55, 0.6, 0.66), 0.1, 0.4)

	# --- seats: burgundy upholstery ---
	var seat := _std(Color(0.38, 0.055, 0.085), 0.0, 0.62)
	seat.rim_enabled = true
	seat.rim = 0.25
	seat.rim_tint = 0.6
	m["seat"] = seat
	m["seat_dark"] = _std(Color(0.2, 0.03, 0.05), 0.0, 0.7)
	m["seat_frame"] = _std(Color(0.22, 0.24, 0.28), 0.85, 0.32)

	# --- emissive lighting / indicators ---
	m["glow_blue"] = _glow(Color(0.2, 0.5, 1.0), 3.0)
	m["glow_cyan"] = _glow(Color(0.3, 0.9, 1.0), 2.6)
	m["glow_amber"] = _glow(Color(1.0, 0.6, 0.15), 2.6)
	m["glow_red"] = _glow(Color(1.0, 0.12, 0.08), 2.6)
	m["glow_green"] = _glow(Color(0.2, 1.0, 0.35), 2.2)
	m["glow_white"] = _glow(Color(0.85, 0.92, 1.0), 3.2)
	m["glow_dim"] = _glow(Color(0.1, 0.3, 0.6), 1.0)
	m["engine"] = _glow(Color(0.35, 0.65, 1.0), 7.0)
	m["nav_red"] = _glow(Color(1.0, 0.1, 0.05), 4.0)
	m["nav_green"] = _glow(Color(0.1, 1.0, 0.3), 4.0)
	m["strobe"] = _glow(Color(1.0, 1.0, 1.0), 6.0)
	m["port_window"] = _glow(Color(1.0, 0.75, 0.45), 1.6)

	# interactive indicator pairs (on / off)
	var leds := {
		"amber": Color(1.0, 0.6, 0.12), "red": Color(1.0, 0.12, 0.08),
		"green": Color(0.2, 1.0, 0.35), "blue": Color(0.25, 0.55, 1.0),
		"cyan": Color(0.3, 0.9, 1.0), "white": Color(0.9, 0.95, 1.0),
	}
	for k in leds:
		m["led_on_" + k] = _glow(leds[k], 3.5)
		m["led_off_" + k] = _led_off(leds[k])

	# --- exterior ---
	m["hull_ext"] = _textured(Color(0.58, 0.61, 0.66), 0.55, 0.5, hull_maps, 0.3, 0.9)
	m["hull_ext_dark"] = _textured(Color(0.17, 0.19, 0.23), 0.6, 0.5, fine_maps, 0.5, 0.6)
	m["hull_ext_accent"] = _std(Color(0.42, 0.06, 0.09), 0.4, 0.45)
	var dg := _std(Color(0.02, 0.035, 0.07), 0.9, 0.06)
	m["dark_glass"] = dg

	# --- canopy glass ---
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.55, 0.75, 0.95, 0.07)
	glass.metallic = 0.3
	glass.roughness = 0.02
	glass.metallic_specular = 0.9
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.rim_enabled = true
	glass.rim = 0.4
	m["glass"] = glass
	return m

extends RefCounted
## Builds the space backdrop: starfield sky, sun, fill light, planet with
## atmosphere and a distant moon. Returns references the cockpit animates.

const SKY_SHADER := preload("res://shaders/starfield_sky.gdshader")
const ATMO_SHADER := preload("res://shaders/atmosphere.gdshader")


static func setup(root: Node3D) -> Dictionary:
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = SKY_SHADER
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.42, 0.55)
	env.ambient_light_energy = 0.45
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.65
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.0
	env.ssao_enabled = true
	env.ssao_radius = 0.5
	env.ssao_intensity = 1.4
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08
	we.environment = env
	root.add_child(we)

	# Sun: light enters through the canopy from front-left-above.
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	sun.shadow_bias = 0.03
	var travel := Vector3(0.45, -0.42, 0.79).normalized()
	sun.transform = Transform3D(Basis.looking_at(travel, Vector3.UP), Vector3.ZERO)
	root.add_child(sun)

	# Bluish planet-shine from below.
	var fill := DirectionalLight3D.new()
	fill.name = "PlanetShine"
	fill.light_color = Color(0.35, 0.55, 1.0)
	fill.light_energy = 0.18
	fill.shadow_enabled = false
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	fill.transform = Transform3D(Basis.looking_at(Vector3(-0.3, 0.8, -0.2).normalized(), Vector3.FORWARD), Vector3.ZERO)
	root.add_child(fill)

	# Planet
	var planet := MeshInstance3D.new()
	planet.name = "Planet"
	var sphere := SphereMesh.new()
	sphere.radius = 380.0
	sphere.height = 760.0
	sphere.radial_segments = 96
	sphere.rings = 48
	planet.mesh = sphere
	var noise := FastNoiseLite.new()
	noise.seed = 66
	noise.frequency = 0.006
	noise.fractal_octaves = 6
	var ntex := NoiseTexture2D.new()
	ntex.width = 1024
	ntex.height = 512
	ntex.seamless = true
	ntex.noise = noise
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.48, 0.52, 0.6, 0.72, 0.85, 1.0])
	grad.colors = PackedColorArray([Color(0.02, 0.08, 0.22), Color(0.05, 0.18, 0.4), Color(0.6, 0.55, 0.4),
		Color(0.22, 0.35, 0.15), Color(0.35, 0.3, 0.2), Color(0.85, 0.87, 0.9), Color(1, 1, 1)])
	ntex.color_ramp = grad
	var pm := StandardMaterial3D.new()
	pm.albedo_texture = ntex
	pm.roughness = 0.85
	pm.metallic_specular = 0.3
	planet.material_override = pm
	planet.position = Vector3(-560.0, -320.0, -1500.0)
	planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(planet)

	var atmo := MeshInstance3D.new()
	atmo.name = "Atmosphere"
	var asph := SphereMesh.new()
	asph.radius = 398.0
	asph.height = 796.0
	asph.radial_segments = 96
	asph.rings = 48
	atmo.mesh = asph
	var am := ShaderMaterial.new()
	am.shader = ATMO_SHADER
	atmo.material_override = am
	atmo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet.add_child(atmo)

	var moon := MeshInstance3D.new()
	moon.name = "Moon"
	var ms := SphereMesh.new()
	ms.radius = 38.0
	ms.height = 76.0
	moon.mesh = ms
	var mm := StandardMaterial3D.new()
	var mnoise := FastNoiseLite.new()
	mnoise.frequency = 0.03
	var mtex := NoiseTexture2D.new()
	mtex.noise = mnoise
	mtex.seamless = true
	mm.albedo_texture = mtex
	mm.albedo_color = Color(0.7, 0.68, 0.66)
	moon.material_override = mm
	moon.position = Vector3(1100.0, 380.0, -2600.0)
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(moon)

	return {"environment": env, "sun": sun, "planet": planet, "moon": moon}

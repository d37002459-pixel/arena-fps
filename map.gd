extends RefCounted
## Строит арену из коробок. Одинаково на всех машинах (сервер и клиенты).

static var _grid_tex: ImageTexture
static var _mats := {}


static func build(root: Node3D) -> Array:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.22, 0.38, 0.68)
	sm.sky_horizon_color = Color(0.72, 0.78, 0.88)
	sm.ground_horizon_color = Color(0.6, 0.62, 0.66)
	sm.ground_bottom_color = Color(0.2, 0.2, 0.22)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.6, 0.66, 0.75)
	env.fog_density = 0.004
	env.fog_sky_affect = 0.0
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	root.add_child(sun)

	var floor_c := Color(0.3, 0.32, 0.34)
	var wall_c := Color(0.55, 0.57, 0.6)
	var red := Color(0.75, 0.32, 0.28)
	var blue := Color(0.28, 0.45, 0.78)
	var crate := Color(0.62, 0.48, 0.3)
	var stone := Color(0.5, 0.48, 0.44)

	# пол и стены
	_box(root, Vector3(0, -0.5, 0), Vector3(66, 1, 66), floor_c)
	_box(root, Vector3(0, 3.5, -33.5), Vector3(68, 7, 1), wall_c)
	_box(root, Vector3(0, 3.5, 33.5), Vector3(68, 7, 1), wall_c)
	_box(root, Vector3(-33.5, 3.5, 0), Vector3(1, 7, 68), wall_c)
	_box(root, Vector3(33.5, 3.5, 0), Vector3(1, 7, 68), wall_c)

	# центральная башня с двумя пандусами
	_box(root, Vector3(0, 1.5, 0), Vector3(8, 3, 8), stone)
	_box(root, Vector3(-3.6, 3.6, 0), Vector3(0.6, 1.2, 8), stone)
	_box(root, Vector3(3.6, 3.6, 0), Vector3(0.6, 1.2, 8), stone)
	_ramp(root, Vector3(0, 0, 14), Vector3(0, 3, 4), 3.5, blue)
	_ramp(root, Vector3(0, 0, -14), Vector3(0, 3, -4), 3.5, red)

	# боковые галереи вдоль стен
	_box(root, Vector3(30, 2.25, 0), Vector3(5, 0.5, 22), stone)
	_ramp(root, Vector3(30, 0, -21), Vector3(30, 2.5, -11), 3.0, red)
	_box(root, Vector3(-30, 2.25, 0), Vector3(5, 0.5, 22), stone)
	_ramp(root, Vector3(-30, 0, 21), Vector3(-30, 2.5, 11), 3.0, blue)
	_box(root, Vector3(27.7, 3.0, 0), Vector3(0.4, 1.0, 22), stone)
	_box(root, Vector3(-27.7, 3.0, 0), Vector3(0.4, 1.0, 22), stone)

	# ящики (симметрично)
	for s in [1, -1]:
		var c: Color = blue if s > 0 else red
		_box(root, Vector3(10 * s, 0.75, 10 * s), Vector3(1.5, 1.5, 1.5), crate)
		_box(root, Vector3(11.5 * s, 0.75, 10 * s), Vector3(1.5, 1.5, 1.5), crate)
		_box(root, Vector3(10.7 * s, 2.25, 10 * s), Vector3(1.5, 1.5, 1.5), crate)
		_box(root, Vector3(-10 * s, 0.75, 10 * s), Vector3(1.5, 1.5, 1.5), crate)
		_box(root, Vector3(-10 * s, 0.75, 11.5 * s), Vector3(1.5, 1.5, 1.5), crate)
		_box(root, Vector3(18 * s, 0.65, -4 * s), Vector3(1.3, 1.3, 1.3), crate)
		_box(root, Vector3(-6 * s, 0.65, 22 * s), Vector3(1.3, 1.3, 1.3), crate)
		_box(root, Vector3(6 * s, 0.65, 24 * s), Vector3(1.3, 1.3, 1.3), crate)
		# низкие укрытия
		_box(root, Vector3(15 * s, 0.65, 0), Vector3(0.6, 1.3, 8), c)
		_box(root, Vector3(0, 0.65, 20 * s), Vector3(8, 1.3, 0.6), c)
		# колонны
		_box(root, Vector3(21 * s, 3, 21 * s), Vector3(1.6, 6, 1.6), wall_c)
		_box(root, Vector3(-21 * s, 3, 21 * s), Vector3(1.6, 6, 1.6), wall_c)
		# Г-образные стенки
		_box(root, Vector3(22 * s, 1.5, -12 * s), Vector3(6, 3, 0.6), c)
		_box(root, Vector3(19.3 * s, 1.5, -14.5 * s), Vector3(0.6, 3, 5), c)

	# точки появления
	return [
		Vector3(-26, 0.2, -26), Vector3(26, 0.2, -26), Vector3(-26, 0.2, 26), Vector3(26, 0.2, 26),
		Vector3(0, 0.2, -28), Vector3(0, 0.2, 28), Vector3(-22, 0.2, 0), Vector3(22, 0.2, 0),
		Vector3(-12, 0.2, -22), Vector3(12, 0.2, 22),
	]


static func _box(root: Node3D, pos: Vector3, size: Vector3, color: Color, basis := Basis()) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.transform = Transform3D(basis, pos)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _material(color)
	body.add_child(mi)
	root.add_child(body)


static func _ramp(root: Node3D, bottom: Vector3, top: Vector3, width: float, color: Color) -> void:
	var d := top - bottom
	var basis := Basis.looking_at(d.normalized(), Vector3.UP)
	var thickness := 0.4
	var center := (bottom + top) * 0.5 - basis.y * (thickness * 0.5)
	_box(root, center, Vector3(width, thickness, d.length() + 0.6), color, basis)


static func _material(color: Color) -> StandardMaterial3D:
	if _mats.has(color):
		return _mats[color]
	if _grid_tex == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
		img.fill(Color(1, 1, 1))
		for i in 64:
			for w in 2:
				img.set_pixel(i, w, Color(0.78, 0.78, 0.78))
				img.set_pixel(w, i, Color(0.78, 0.78, 0.78))
		img.generate_mipmaps()
		_grid_tex = ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = _grid_tex
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	m.roughness = 0.85
	_mats[color] = m
	return m

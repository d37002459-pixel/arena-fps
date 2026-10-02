extends RefCounted
## Визуальные эффекты стрельбы: трассеры, вспышки, гильзы, искры, дырки от пуль.

const MAX_DECALS := 80

static var _mats := {}
static var _decals: Array = []
static var _hole_tex: ImageTexture
static var _flash_tex: ImageTexture


static func unshaded(c: Color, additive := false, tex: Texture2D = null) -> StandardMaterial3D:
	var key := "%s%s%s" % [c.to_html(), additive, tex != null]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if tex:
		m.albedo_texture = tex
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.no_depth_test = false
	elif c.a < 1.0 or tex:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


static func _radial(size: int, inner: Color, outer: Color, power: float) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) / 2.0
	for y in size:
		for x in size:
			var d := clampf(Vector2(x - c, y - c).length() / c, 0.0, 1.0)
			var k := pow(1.0 - d, power)
			img.set_pixel(x, y, outer.lerp(inner, k))
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- трассер

static func tracer(world: Node3D, from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 1.0:
		return
	var d := (to - from) / length
	# рисуем не всю линию, а «пулю» длиной до 6 м, пролетающую путь
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var seg := minf(6.0, length)
	bm.size = Vector3(0.014, 0.014, seg)
	m.mesh = bm
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.86, 0.45, 0.9)
	m.material_override = mat
	world.add_child(m)
	var up := Vector3.UP if absf(d.y) < 0.98 else Vector3.RIGHT
	var basis := Basis.looking_at(d, up)
	var travel := maxf(length - seg, 0.0)
	var dur := clampf(length / 350.0, 0.03, 0.25)
	m.global_transform = Transform3D(basis, from + d * seg * 0.5)
	var tw := m.create_tween()
	tw.tween_property(m, "global_position", from + d * (seg * 0.5 + travel), dur)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, dur + 0.04)
	tw.tween_callback(m.queue_free)


# ---------------------------------------------------------------- вспышка

static func muzzle_flash(muzzle: Node3D) -> void:
	if _flash_tex == null:
		_flash_tex = _radial(32, Color(1.0, 0.95, 0.75, 1.0), Color(1.0, 0.45, 0.05, 0.0), 1.6)
	var root := Node3D.new()
	muzzle.add_child(root)
	root.rotation.z = randf() * TAU
	var s := randf_range(0.8, 1.2)
	for i in 3:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.22, 0.22) * s if i == 0 else Vector2(0.09, 0.32) * s
		q.mesh = qm
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.material_override = unshaded(Color(1, 0.8, 0.45), true, _flash_tex)
		root.add_child(q)
		if i == 1:
			q.rotation = Vector3(0, PI / 2, 0)
			q.position.z = -0.1
		elif i == 2:
			q.rotation = Vector3(PI / 2, 0, 0)
			q.position.z = -0.1
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.35)
	light.light_energy = 1.8
	light.omni_range = 5.0
	root.add_child(light)
	root.get_tree().create_timer(0.045).timeout.connect(root.queue_free)


# ---------------------------------------------------------------- гильза

static func shell(world: Node3D, pos: Vector3, basis: Basis) -> void:
	var s := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.006
	cm.bottom_radius = 0.006
	cm.height = 0.032
	s.mesh = cm
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.62, 0.25)
	m.metallic = 0.8
	m.roughness = 0.35
	s.material_override = m
	world.add_child(s)
	s.global_position = pos
	var v := basis.x * randf_range(1.6, 2.4) + basis.y * randf_range(1.0, 1.6) + basis.z * randf_range(0.0, 0.5)
	var spin := Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
	var tw := s.create_tween()
	tw.tween_method(func(t: float):
		s.global_position = pos + v * t + Vector3(0, -7.0, 0) * t * t
		s.rotation = spin * t, 0.0, 0.7, 0.7)
	tw.tween_callback(s.queue_free)


# ---------------------------------------------------------------- попадание

static func impact(world: Node3D, pos: Vector3, normal: Vector3, hit_player: bool) -> void:
	if normal.length() < 0.5:
		normal = Vector3.UP
	_burst(world, pos, normal, Color(0.75, 0.05, 0.05) if hit_player else Color(1.0, 0.8, 0.4), 12 if hit_player else 9, 0.035)
	if not hit_player:
		_burst(world, pos, normal, Color(0.55, 0.53, 0.5, 0.8), 6, 0.07)
		decal(world, pos, normal)


static func _burst(world: Node3D, pos: Vector3, normal: Vector3, color: Color, amount: int, size: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.direction = normal
	p.spread = 40.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -12, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * size
	p.mesh = bm
	p.material_override = unshaded(color)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(p)
	p.global_position = pos + normal * 0.03
	p.emitting = true
	p.get_tree().create_timer(1.0).timeout.connect(p.queue_free)


static func decal(world: Node3D, pos: Vector3, normal: Vector3) -> void:
	if _hole_tex == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			for x in 32:
				var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
				var a := 0.0
				var c := Color(0.05, 0.05, 0.05)
				if d < 0.45:
					a = 1.0
				elif d < 1.0:
					a = (1.0 - d) / 0.55 * 0.55
					c = Color(0.18, 0.17, 0.16)
				img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
		_hole_tex = ImageTexture.create_from_image(img)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	var s := randf_range(0.07, 0.1)
	qm.size = Vector2(s, s)
	q.mesh = qm
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.albedo_texture = _hole_tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	q.material_override = m
	world.add_child(q)
	var up := Vector3.UP if absf(normal.y) < 0.98 else Vector3.RIGHT
	q.global_transform = Transform3D(Basis.looking_at(-normal, up), pos + normal * 0.004)
	q.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	_decals.append(q)
	while _decals.size() > MAX_DECALS:
		var old = _decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()

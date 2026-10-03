extends RefCounted
## Карта «Песчаный квартал» — пустынный городок.
## Коллизии строятся одинаково на сервере и у игроков; внешний вид — только у игроков.

const Kit := preload("res://meshkit.gd")

const SPAWNS := [
	Vector3(-26, 0.2, -26), Vector3(26, 0.2, -26), Vector3(-26, 0.2, 26), Vector3(26, 0.2, 26),
	Vector3(0, 0.2, -28), Vector3(0, 0.2, 28), Vector3(-22, 0.2, 0), Vector3(22, 0.2, 0),
	Vector3(-12, 0.2, -22), Vector3(12, 0.2, 22),
]

const PLASTER_TINTS := [
	Color(1.0, 1.0, 1.0), Color(1.0, 0.93, 0.82), Color(0.98, 0.86, 0.74),
	Color(0.92, 0.95, 0.98), Color(1.0, 0.9, 0.86), Color(0.95, 0.92, 0.84),
]
const CLOTH := [
	Color(0.85, 0.28, 0.22), Color(0.25, 0.45, 0.80), Color(0.30, 0.62, 0.38),
	Color(0.95, 0.62, 0.18), Color(0.90, 0.85, 0.75), Color(0.62, 0.30, 0.65),
]
const SHUTTERS := [Color(0.55, 0.8, 0.62), Color(0.5, 0.66, 0.92), Color(1, 1, 1), Color(0.95, 0.7, 0.55)]

var root: Node3D
var visuals := true
var kit: Kit
var far: Kit
var body: StaticBody3D
var rng := RandomNumberGenerator.new()
var M := {}
var sun: DirectionalLight3D
var env: Environment


func build(parent: Node3D, with_visuals := true) -> Array:
	root = parent
	visuals = with_visuals
	rng.seed = 2026
	body = StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	if visuals:
		kit = Kit.new()
		far = Kit.new()
		_materials()
		_environment()
	_ground()
	_perimeter()
	_tower()
	_galleries()
	_props()
	if visuals:
		_skyline()
		kit.build(root, true)
		far.build(root, false)
	return SPAWNS


# ================================================================ материалы и свет

func _materials() -> void:
	M["sand"] = Kit.mat("sand", 0.95, 0.0, 1.0, 0.3)
	M["paving"] = Kit.mat("paving", 0.8, 0.0, 1.2, 0.3)
	M["stone"] = Kit.mat("sandstone", 0.9, 0.0, 1.3)
	M["plaster"] = Kit.mat("plaster", 0.92, 0.0, 0.8)
	M["wood"] = Kit.mat("wood", 0.8, 0.0, 1.0, 0.15)
	M["crate"] = Kit.mat("crate", 0.8, 0.0, 1.2, 0.12)
	M["metal"] = Kit.mat("metal", 0.5, 0.4, 1.0, 0.15)
	M["concrete"] = Kit.mat("concrete", 0.9, 0.0, 1.0)
	M["bags"] = Kit.mat("sandbags", 0.95, 0.0, 1.3, 0.15)
	M["fabric"] = Kit.mat("fabric", 0.95, 0.0, 0.6, 0.1, 0.0)
	M["bark"] = Kit.mat("wood", 0.95, 0.0, 1.5, 0.1, 0.2)
	M["dark"] = Kit.flat_mat(Color(0.07, 0.075, 0.08), 0.25, 0.2)
	M["wire"] = Kit.flat_mat(Color(0.1, 0.1, 0.1), 0.6)
	var leaf := StandardMaterial3D.new()
	leaf.albedo_texture = load("res://textures/palm_leaf.png")
	leaf.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	leaf.alpha_scissor_threshold = 0.5
	leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaf.vertex_color_use_as_albedo = true
	leaf.roughness = 0.75
	leaf.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	M["leaf"] = leaf


func _environment() -> void:
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	env = Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.2, 0.42, 0.76)
	sm.sky_horizon_color = Color(0.74, 0.8, 0.86)
	sm.sky_curve = 0.12
	sm.ground_horizon_color = Color(0.78, 0.72, 0.62)
	sm.ground_bottom_color = Color(0.5, 0.42, 0.32)
	sm.sun_angle_max = 25.0
	sm.sun_curve = 0.1
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.78, 0.72, 0.64)
	env.ambient_light_sky_contribution = 0.45
	env.ambient_light_energy = 0.82
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.92
	env.tonemap_white = 5.0
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 1.08
	env.fog_enabled = true
	env.fog_light_color = Color(0.84, 0.78, 0.68)
	env.fog_density = 0.0035
	env.fog_sun_scatter = 0.12
	env.fog_sky_affect = 0.12
	we.environment = env
	root.add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-47, -38, 0)
	sun.light_color = Color(1.0, 0.88, 0.72)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.4
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_split_1 = 0.22
	root.add_child(sun)

	# отражённый от песка тёплый свет снизу — подсвечивает навесы и балконы
	var bounce := DirectionalLight3D.new()
	bounce.name = "Bounce"
	bounce.rotation_degrees = Vector3(60, 140, 0)
	bounce.light_color = Color(1.0, 0.8, 0.6)
	bounce.light_energy = 0.22
	bounce.light_specular = 0.0
	root.add_child(bounce)


# ================================================================ помощники

func _col_box(xf: Transform3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.transform = xf
	body.add_child(cs)


func _col_cyl(pos: Vector3, r: float, h: float) -> void:
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	cs.position = pos
	body.add_child(cs)


## Твёрдая коробка: коллизия + вид
func solid(mat: String, pos: Vector3, size: Vector3, tile := 2.0, color := Color.WHITE, rot := Vector3.ZERO, faces := Kit.F_ALL) -> void:
	var xf := Transform3D(Basis.from_euler(rot), pos)
	_col_box(xf, size)
	if visuals:
		kit.box(M[mat], xf, size, tile, color, faces)


## Только вид
func deco(mat: String, pos: Vector3, size: Vector3, tile := 2.0, color := Color.WHITE, rot := Vector3.ZERO, faces := Kit.F_ALL) -> void:
	if visuals:
		kit.box(M[mat], Transform3D(Basis.from_euler(rot), pos), size, tile, color, faces)


func decox(mat: String, xf: Transform3D, size: Vector3, tile := 2.0, color := Color.WHITE, faces := Kit.F_ALL) -> void:
	if visuals:
		kit.box(M[mat], xf, size, tile, color, faces)


func ao(center: Vector3, sx: float, sz: float, margin := 0.6, yaw := 0.0, strength := 0.35) -> void:
	if visuals:
		kit.ao_rect(center, sx, sz, margin, yaw, strength)


func _ramp(bottom: Vector3, top: Vector3, width: float) -> void:
	var d := top - bottom
	var b := Basis.looking_at(d.normalized(), Vector3.UP)
	var thickness := 0.4
	var center := (bottom + top) * 0.5 - b.y * (thickness * 0.5)
	_col_box(Transform3D(b, center), Vector3(width, thickness, d.length() + 0.6))


func _stair_frame(bottom: Vector3, top: Vector3) -> Array:
	var d := top - bottom
	var horiz := Vector3(d.x, 0, d.z)
	var run_len := horiz.length()
	var dir := horiz / run_len
	var n := int(round(d.y / 0.2))
	return [dir, run_len, n, Basis(Vector3.UP, atan2(dir.x, dir.z))]


## Каменная лестница: под ней невидимый пандус (по нему удобно бегать)
func stairs_stone(bottom: Vector3, top: Vector3, width: float, mat := "stone") -> void:
	_ramp(bottom, top, width)
	if not visuals:
		return
	var f := _stair_frame(bottom, top)
	var dir: Vector3 = f[0]
	var run_len: float = f[1]
	var n: int = f[2]
	var b: Basis = f[3]
	var rise := top.y - bottom.y
	var step_run := run_len / n
	for k in range(1, n + 1):
		var top_y := bottom.y + (k - 0.5) * rise / n
		var hgt := top_y - bottom.y
		var c := bottom + dir * ((k - 0.5) * step_run)
		c.y = bottom.y + hgt * 0.5
		kit.box(M[mat], Transform3D(b, c), Vector3(width, hgt, step_run), 2.0, Color.WHITE, Kit.F_ALL & ~Kit.F_NY)
	var mid := bottom + dir * run_len * 0.5
	ao(Vector3(mid.x, bottom.y, mid.z), width, run_len, 0.5, atan2(dir.x, dir.z))


## Деревянная лестница с перилами
func stairs_wood(bottom: Vector3, top: Vector3, width: float) -> void:
	_ramp(bottom, top, width)
	if not visuals:
		return
	var f := _stair_frame(bottom, top)
	var dir: Vector3 = f[0]
	var run_len: float = f[1]
	var n: int = f[2]
	var b: Basis = f[3]
	var rise := top.y - bottom.y
	var step_run := run_len / n
	for k in range(1, n + 1):
		var c := bottom + dir * ((k - 0.5) * step_run)
		c.y = bottom.y + (k - 0.5) * rise / n - 0.03
		kit.box(M["wood"], Transform3D(b, c), Vector3(width - 0.12, 0.06, step_run * 1.15), 1.0)
	var d := top - bottom
	var sb := Basis.looking_at(d.normalized(), Vector3.UP)
	var side := b.x
	for sgn in [-1.0, 1.0]:
		var off: Vector3 = side * sgn * (width * 0.5 - 0.05)
		kit.box(M["wood"], Transform3D(sb, (bottom + top) * 0.5 + off - Vector3(0, 0.12, 0)), Vector3(0.08, 0.28, d.length()), 1.0, Color(0.8, 0.75, 0.7))
		var posts := int(d.length() / 1.3) + 1
		for i in posts + 1:
			var t := float(i) / posts
			var p := bottom.lerp(top, t) + off + Vector3(0, 0.45, 0)
			kit.box(M["wood"], Transform3D(b, p), Vector3(0.06, 0.9, 0.06), 1.0, Color(0.8, 0.75, 0.7))
		kit.box(M["wood"], Transform3D(sb, (bottom + top) * 0.5 + off + Vector3(0, 0.92, 0)), Vector3(0.07, 0.07, d.length()), 1.0, Color(0.85, 0.8, 0.75))


# ================================================================ земля

func _ground() -> void:
	_col_box(Transform3D(Basis(), Vector3(0, -0.5, 0)), Vector3(70, 1, 70))
	if not visuals:
		return
	kit.box(M["sand"], Transform3D(Basis(), Vector3(0, -0.5, 0)), Vector3(70, 1, 70), 4.0, Color.WHITE, Kit.F_PY)
	_slab(Vector2(0, 0), Vector2(24, 24))
	for sgn in [1.0, -1.0]:
		_slab(Vector2(sgn * 22.5, 0), Vector2(21, 6))
		_slab(Vector2(0, sgn * 22.5), Vector2(6, 21))


func _slab(c: Vector2, sz: Vector2) -> void:
	kit.box(M["paving"], Transform3D(Basis(), Vector3(c.x, -0.035, c.y)), Vector3(sz.x, 0.1, sz.y), 4.0, Color.WHITE, Kit.F_ALL & ~Kit.F_NY)


# ================================================================ стены-дома по периметру

func _perimeter() -> void:
	var yaws := [PI, 0.0, -PI / 2, PI / 2]
	var origins := [Vector3(0, 0, 33), Vector3(0, 0, -33), Vector3(33, 0, 0), Vector3(-33, 0, 0)]
	for side in 4:
		var F := Transform3D(Basis(Vector3.UP, yaws[side]), origins[side])
		_col_box(F * Transform3D(Basis(), Vector3(0, 5, -0.5)), Vector3(70, 10, 1))
		if visuals:
			_facade(F)
			ao(F * Vector3(0, 0, 0), 66, 0.01, 1.0, yaws[side], 0.4)


func _L(F: Transform3D, mat: String, pos: Vector3, size: Vector3, tile := 2.0, color := Color.WHITE, faces := Kit.F_ALL, rot := Vector3.ZERO) -> void:
	kit.box(M[mat], F * Transform3D(Basis.from_euler(rot), pos), size, tile, color, faces)


func _facade(F: Transform3D) -> void:
	var widths := [9.0, 11.0, 8.0, 12.0, 10.0, 8.0, 8.0]
	for i in widths.size():
		var j := rng.randi_range(0, widths.size() - 1)
		var tmp = widths[i]
		widths[i] = widths[j]
		widths[j] = tmp
	var x := -33.0
	var prev_h := 0.0
	for w in widths:
		var h := _house(F, x + w * 0.5, w)
		# пилястра на стыке домов
		_L(F, "stone", Vector3(x, minf(h, prev_h if prev_h > 0 else h) * 0.5, -0.4), Vector3(0.5, minf(h, prev_h if prev_h > 0 else h), 1.0), 2.0, Color.WHITE, Kit.F_PZ | Kit.F_PX | Kit.F_NX)
		prev_h = h
		x += w


func _house(F: Transform3D, cx: float, w: float) -> float:
	var style := rng.randi_range(0, 2)
	var tint: Color = PLASTER_TINTS[rng.randi_range(0, PLASTER_TINTS.size() - 1)]
	var h := snappedf(rng.randf_range(7.2, 9.8), 0.4)
	var sides := Kit.F_PZ | Kit.F_PY | Kit.F_PX | Kit.F_NX
	var ground_h := 1.0
	if style == 1:
		_L(F, "stone", Vector3(cx, h * 0.5, -0.5), Vector3(w, h, 1.0), 2.0, Color.WHITE, sides)
	else:
		if style == 2:
			ground_h = 3.0
		_L(F, "stone", Vector3(cx, ground_h * 0.5, -0.44), Vector3(w, ground_h, 1.12), 2.0, Color.WHITE, sides)
		_L(F, "plaster", Vector3(cx, (ground_h + h) * 0.5, -0.5), Vector3(w, h - ground_h, 1.0), 3.0, tint, sides)
		_L(F, "stone", Vector3(cx, ground_h + 0.05, -0.42), Vector3(w, 0.1, 1.16), 2.0, Color(0.95, 0.9, 0.85), Kit.F_PZ | Kit.F_PY | Kit.F_NY)
	# карниз
	_L(F, "stone", Vector3(cx, h - 0.18, -0.38), Vector3(w + 0.1, 0.36, 1.24), 2.0, Color(0.95, 0.92, 0.88), Kit.F_PZ | Kit.F_PY | Kit.F_NY | Kit.F_PX | Kit.F_NX)
	if style != 1 and rng.randf() < 0.6:
		_L(F, "stone", Vector3(cx, 3.1, -0.45), Vector3(w, 0.16, 1.12), 2.0, Color.WHITE, Kit.F_PZ | Kit.F_PY | Kit.F_NY)
	# окна второго этажа
	var count := maxi(1, int(w / 3.3))
	for j in count:
		var wx := cx - w * 0.5 + (j + 0.5) * w / count
		_window(F, Vector3(wx, 4.7, 0.0), 1.0, 1.4, rng.randf() < 0.65)
		if h > 8.4 and rng.randf() < 0.7:
			_window(F, Vector3(wx, 7.0, 0.0), 0.9, 1.0, false)
	# первый этаж: дверь или зарешеченные окна
	var door_x := cx + rng.randf_range(-w * 0.25, w * 0.25)
	if rng.randf() < 0.7:
		_door(F, door_x)
	else:
		for j in 2:
			var wx := cx - w * 0.25 + j * w * 0.5
			_window(F, Vector3(wx, 1.9, 0.0), 0.8, 0.9, false, true)
	# кондиционер, трубы
	if rng.randf() < 0.55:
		var ax := cx + rng.randf_range(-w * 0.4, w * 0.4)
		var ay := 3.6 if rng.randf() < 0.5 else 6.0
		_L(F, "concrete", Vector3(ax, ay, 0.22), Vector3(0.85, 0.55, 0.44), 1.0, Color(0.95, 0.95, 0.95))
		_L(F, "dark", Vector3(ax + 0.12, ay, 0.45), Vector3(0.45, 0.42, 0.02), 1.0)
	if rng.randf() < 0.5:
		var px := cx + w * 0.5 - 0.5
		kit.cylinder(M["metal"], F * Transform3D(Basis(), Vector3(px, h * 0.5, 0.12)), 0.06, 0.06, h, 8, 1.0, Color(0.85, 0.85, 0.85), false)
	# бак на крыше (виден с вышки)
	if rng.randf() < 0.5:
		var tx := cx + rng.randf_range(-w * 0.3, w * 0.3)
		kit.cylinder(M["metal"], F * Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(tx, h + 0.6, -1.4)), 0.55, 0.55, 1.6, 12, 1.0, Color(1.1, 1.1, 1.1))
		_L(F, "metal", Vector3(tx, h + 0.1, -1.4), Vector3(1.4, 0.2, 0.9), 1.0, Color(0.6, 0.6, 0.6))
	return h


func _window(F: Transform3D, c: Vector3, ww: float, wh: float, shutters: bool, bars := false) -> void:
	var x := c.x
	var y := c.y
	_L(F, "dark", Vector3(x, y, 0.01), Vector3(ww, wh, 0.04), 1.0)
	var fc := Color(0.75, 0.7, 0.65)
	_L(F, "wood", Vector3(x, y + wh * 0.5 + 0.05, 0.05), Vector3(ww + 0.2, 0.1, 0.1), 1.0, fc)
	_L(F, "wood", Vector3(x, y - wh * 0.5 - 0.05, 0.05), Vector3(ww + 0.2, 0.1, 0.1), 1.0, fc)
	_L(F, "wood", Vector3(x - ww * 0.5 - 0.05, y, 0.05), Vector3(0.1, wh, 0.1), 1.0, fc)
	_L(F, "wood", Vector3(x + ww * 0.5 + 0.05, y, 0.05), Vector3(0.1, wh, 0.1), 1.0, fc)
	if bars:
		for i in 5:
			_L(F, "metal", Vector3(x - ww * 0.4 + i * ww * 0.2, y, 0.08), Vector3(0.03, wh, 0.03), 1.0, Color(0.4, 0.4, 0.4))
	else:
		_L(F, "wood", Vector3(x, y, 0.04), Vector3(0.05, wh, 0.05), 1.0, fc)
		_L(F, "wood", Vector3(x, y + wh * 0.15, 0.04), Vector3(ww, 0.05, 0.05), 1.0, fc)
	# подоконник
	_L(F, "stone", Vector3(x, y - wh * 0.5 - 0.16, 0.1), Vector3(ww + 0.4, 0.12, 0.26), 2.0, Color(0.95, 0.92, 0.88))
	if shutters:
		var sc: Color = SHUTTERS[rng.randi_range(0, SHUTTERS.size() - 1)]
		for sgn in [-1.0, 1.0]:
			var ang := deg_to_rad(rng.randf_range(95.0, 170.0))
			var hinge := Vector3(x + sgn * (ww * 0.5 + 0.1), y, 0.06)
			var d := Vector3(-sgn * cos(ang), 0, sin(ang))
			var phi := atan2(-d.z, d.x)
			var pc := hinge + d * (ww * 0.25 + 0.02)
			kit.box(M["wood"], F * Transform3D(Basis(Vector3.UP, phi), pc), Vector3(ww * 0.5, wh, 0.04), 1.0, sc)


func _door(F: Transform3D, x: float) -> void:
	var dw := 1.3
	var dh := 2.4
	var dc: Color = [Color(0.8, 0.6, 0.45), Color(0.55, 0.75, 0.9), Color(0.6, 0.85, 0.65), Color(1, 1, 1)][rng.randi_range(0, 3)]
	_L(F, "wood", Vector3(x, dh * 0.5, 0.03), Vector3(dw, dh, 0.06), 1.3, dc)
	_L(F, "metal", Vector3(x + dw * 0.35, 1.05, 0.08), Vector3(0.05, 0.18, 0.05), 1.0, Color(0.5, 0.5, 0.5))
	_L(F, "stone", Vector3(x - dw * 0.5 - 0.15, (dh + 0.1) * 0.5, 0.07), Vector3(0.3, dh + 0.1, 0.16), 2.0, Color(0.95, 0.92, 0.88))
	_L(F, "stone", Vector3(x + dw * 0.5 + 0.15, (dh + 0.1) * 0.5, 0.07), Vector3(0.3, dh + 0.1, 0.16), 2.0, Color(0.95, 0.92, 0.88))
	_L(F, "stone", Vector3(x, dh + 0.2, 0.08), Vector3(dw + 0.7, 0.32, 0.18), 2.0, Color(0.95, 0.92, 0.88))
	_L(F, "stone", Vector3(x, 0.06, 0.25), Vector3(dw + 0.6, 0.12, 0.5), 2.0, Color(0.9, 0.88, 0.84))
	if rng.randf() < 0.65:
		var cc: Color = CLOTH[rng.randi_range(0, CLOTH.size() - 1)]
		_L(F, "fabric", Vector3(x, 2.95, 0.75), Vector3(dw + 1.4, 0.03, 1.6), 1.0, cc, Kit.F_ALL, Vector3(-0.32, 0, 0))
		_L(F, "fabric", Vector3(x, 2.6, 1.52), Vector3(dw + 1.4, 0.25, 0.02), 1.0, cc)


# ================================================================ центральная башня

func _tower() -> void:
	# основание
	_col_box(Transform3D(Basis(), Vector3(0, 1.5, 0)), Vector3(8, 3, 8))
	if visuals:
		kit.box(M["stone"], Transform3D(Basis(), Vector3(0, 1.5, 0)), Vector3(8, 3, 8), 2.0, Color.WHITE, Kit.F_PX | Kit.F_NX | Kit.F_PZ | Kit.F_NZ)
		kit.box(M["paving"], Transform3D(Basis(), Vector3(0, 1.5, 0)), Vector3(8, 3, 8), 3.0, Color(0.95, 0.92, 0.88), Kit.F_PY)
		deco("stone", Vector3(0, 0.25, 0), Vector3(8.4, 0.5, 8.4), 2.0, Color(0.9, 0.86, 0.8), Vector3.ZERO, Kit.F_ALL & ~Kit.F_NY)
		deco("stone", Vector3(0, 2.92, 0), Vector3(8.3, 0.16, 8.3), 2.0, Color(0.95, 0.92, 0.88), Vector3.ZERO, Kit.F_ALL & ~Kit.F_PY)
		ao(Vector3(0, 0, 0), 8.4, 8.4, 1.0)
		# двери в башню (декор)
		for sgn in [-1.0, 1.0]:
			var F := Transform3D(Basis(Vector3.UP, sgn * PI / 2), Vector3(sgn * 4.0, 0, 0))
			_door(F, 0.0)
	# парапеты
	for sgn in [-1.0, 1.0]:
		solid("stone", Vector3(sgn * 3.6, 3.6, 0), Vector3(0.6, 1.2, 8), 2.0)
		deco("stone", Vector3(sgn * 3.6, 4.26, 0), Vector3(0.78, 0.12, 8.1), 2.0, Color(0.95, 0.92, 0.88))
	# лестницы на башню (север и юг)
	stairs_stone(Vector3(0, 0, 14), Vector3(0, 3, 4), 3.5)
	stairs_stone(Vector3(0, 0, -14), Vector3(0, 3, -4), 3.5)
	if visuals:
		for z in [1.0, -1.0]:
			for sgn in [-1.0, 1.0]:
				deco("stone", Vector3(sgn * 1.9, 0.35, z * 14.2), Vector3(0.35, 0.7, 0.35), 2.0)

	# вышка: деревянная лестница, настил, мешки с песком, крыша
	stairs_wood(Vector3(-2.6, 3, 3.2), Vector3(-2.6, 6, -2.0), 1.6)
	_col_box(Transform3D(Basis(), Vector3(-1.4, 5.8, -3.2)), Vector3(3.8, 0.4, 2.6))
	if visuals:
		deco("wood", Vector3(-1.4, 5.96, -3.2), Vector3(3.8, 0.08, 2.6), 2.0)
		deco("wood", Vector3(-1.4, 5.75, -3.2), Vector3(3.9, 0.3, 2.7), 1.0, Color(0.7, 0.62, 0.55), Vector3.ZERO, Kit.F_ALL & ~Kit.F_PY)
	_col_box(Transform3D(Basis(), Vector3(-1.4, 6.45, -4.4)), Vector3(3.8, 0.9, 0.2))
	deco("bags", Vector3(-1.4, 6.45, -4.4), Vector3(3.8, 0.9, 0.42), 1.5)
	_col_box(Transform3D(Basis(), Vector3(0.4, 6.45, -3.1)), Vector3(0.2, 0.9, 2.4))
	deco("bags", Vector3(0.4, 6.45, -3.15), Vector3(0.42, 0.9, 2.2), 1.5)
	solid("wood", Vector3(-3.0, 4.4, -4.2), Vector3(0.3, 2.6, 0.3), 1.0, Color(0.75, 0.68, 0.6))
	solid("wood", Vector3(0.3, 4.4, -2.0), Vector3(0.25, 2.6, 0.25), 1.0, Color(0.75, 0.68, 0.6))
	solid("wood", Vector3(0.3, 4.4, -4.3), Vector3(0.25, 2.6, 0.25), 1.0, Color(0.75, 0.68, 0.6))
	if visuals:
		for p in [Vector3(-3.25, 0, -4.35), Vector3(0.35, 0, -4.35), Vector3(0.35, 0, -2.05), Vector3(-3.35, 0, -2.05)]:
			deco("wood", Vector3(p.x, 7.25, p.z), Vector3(0.1, 2.5, 0.1), 1.0, Color(0.75, 0.68, 0.6))
		deco("metal", Vector3(-1.45, 8.55, -3.2), Vector3(4.6, 0.06, 3.4), 2.0, Color(0.9, 0.85, 0.8), Vector3(0.12, 0, 0))


# ================================================================ галереи вдоль боковых стен

func _galleries() -> void:
	for sgn in [1.0, -1.0]:
		var gx: float = 30.0 * sgn
		_col_box(Transform3D(Basis(), Vector3(gx, 2.25, 0)), Vector3(5, 0.5, 22))
		if visuals:
			deco("wood", Vector3(gx, 2.46, 0), Vector3(5, 0.08, 22), 2.0)
			deco("wood", Vector3(gx, 2.2, 0), Vector3(5.05, 0.44, 22.05), 1.0, Color(0.7, 0.62, 0.55), Vector3.ZERO, Kit.F_ALL & ~Kit.F_PY)
			for i in 9:
				deco("wood", Vector3(gx, 1.88, -11 + i * 2.75), Vector3(5, 0.2, 0.18), 1.0, Color(0.65, 0.58, 0.5))
		# перила: доски
		_col_box(Transform3D(Basis(), Vector3(27.7 * sgn, 3.0, 0)), Vector3(0.4, 1.0, 22))
		if visuals:
			deco("wood", Vector3(27.7 * sgn, 2.95, 0), Vector3(0.12, 0.9, 22), 1.5, Color(0.9, 0.85, 0.8))
			deco("wood", Vector3(27.7 * sgn, 3.45, 0), Vector3(0.22, 0.1, 22.1), 1.0, Color(0.8, 0.72, 0.64))
			# ковры на перилах
			for z in [-6.0, 4.5]:
				var cc: Color = CLOTH[rng.randi_range(0, CLOTH.size() - 1)]
				deco("fabric", Vector3(27.7 * sgn - 0.08 * sgn, 2.55, z), Vector3(0.03, 1.6, 2.4), 1.2, cc)
		# опоры
		for z in [-10.8, -5.5, 0.0, 5.5, 10.8]:
			solid("wood", Vector3(27.7 * sgn, 1.0, z), Vector3(0.25, 2.0, 0.25), 1.0, Color(0.75, 0.68, 0.6))
		stairs_stone(Vector3(gx, 0, -21 * sgn), Vector3(gx, 2.5, -11 * sgn), 3.0)


# ================================================================ укрытия и предметы

func _crate(pos: Vector3, s: float, yaw := 0.0) -> void:
	var tint := Color(1, 1, 1) * rng.randf_range(0.82, 1.05)
	solid("crate", pos, Vector3(s, s, s), 0.0, tint, Vector3(0, yaw, 0))
	if pos.y - s * 0.5 < 0.1:
		ao(Vector3(pos.x, 0, pos.z), s, s, 0.5, yaw, 0.4)


func _barrel(pos: Vector3, tint: Color) -> void:
	_col_cyl(pos + Vector3(0, 0.45, 0), 0.32, 0.9)
	if not visuals:
		return
	kit.cylinder(M["metal"], Transform3D(Basis(Vector3.UP, rng.randf() * TAU), pos + Vector3(0, 0.45, 0)), 0.31, 0.31, 0.9, 14, 0.6, tint)
	for y in [0.22, 0.68]:
		kit.cylinder(M["metal"], Transform3D(Basis(), pos + Vector3(0, y, 0)), 0.325, 0.325, 0.04, 14, 1.0, tint * 0.8, false)
	ao(pos, 0.5, 0.5, 0.35, 0.0, 0.4)


func _palm(base: Vector3, height: float, lean: Vector3, collide: bool, target: Kit) -> void:
	if collide:
		_col_cyl(base + Vector3(0, 3, 0), 0.25, 6.0)
	if not visuals:
		return
	var segs := 8
	var p := base
	for i in segs:
		var t := float(i) / segs
		var dir := (Vector3.UP + lean * t * t * 1.4).normalized()
		var seg_len := height / segs
		var r0 := lerpf(0.26, 0.16, t)
		var r1 := lerpf(0.26, 0.16, t + 1.0 / segs)
		var q := Quaternion(Vector3.UP, dir)
		target.cylinder(M["bark"], Transform3D(Basis(q), p + dir * seg_len * 0.5), r1, r0 * 1.12, seg_len * 1.02, 8, 0.7, Color(0.6, 0.53, 0.46))
		p += dir * seg_len
	var leaves := 10
	for j in leaves:
		var a := TAU * j / leaves + rng.randf_range(-0.2, 0.2)
		var out := Vector3(cos(a), 0, sin(a))
		var l1 := rng.randf_range(1.5, 1.9)
		var l2 := rng.randf_range(1.6, 2.1)
		var p1 := p + out * l1 + Vector3(0, rng.randf_range(0.2, 0.6), 0)
		var p2 := p1 + out * l2 + Vector3(0, rng.randf_range(-1.4, -0.8), 0)
		var tint := Color(1, 1, 1) * rng.randf_range(0.8, 1.1)
		_leaf(target, p, p1, out, 1.0, Vector2(0, 0.5), Vector2(1, 1.0), tint)
		_leaf(target, p1, p2, out, 0.9, Vector2(0, 0.0), Vector2(1, 0.5), tint)
	ao(base, 0.4, 0.4, 0.5, 0.0, 0.4)


func _leaf(target: Kit, a: Vector3, b: Vector3, out: Vector3, width: float, uv0: Vector2, uv1: Vector2, tint: Color) -> void:
	var along := (b - a).normalized()
	var side := out.cross(Vector3.UP).normalized()
	var nrm := side.cross(along).normalized()
	var basis := Basis(side, along, nrm)
	target.quad(M["leaf"], Transform3D(basis, (a + b) * 0.5), width, a.distance_to(b) * 1.05, tint, uv0, uv1)


func _stall(pos: Vector3, yaw: float) -> void:
	var B := Basis(Vector3.UP, yaw)
	var F := Transform3D(B, pos)
	_col_box(F * Transform3D(Basis(), Vector3(0, 0.5, 0)), Vector3(2.6, 1.0, 1.1))
	if not visuals:
		return
	var cc: Color = CLOTH[rng.randi_range(0, CLOTH.size() - 1)]
	_L(F, "wood", Vector3(0, 0.96, 0), Vector3(2.7, 0.08, 1.2), 1.0)
	_L(F, "wood", Vector3(0, 0.46, 0.56), Vector3(2.6, 0.9, 0.05), 1.0, Color(0.85, 0.8, 0.75))
	_L(F, "wood", Vector3(0, 0.46, -0.56), Vector3(2.6, 0.9, 0.05), 1.0, Color(0.85, 0.8, 0.75))
	_L(F, "wood", Vector3(1.28, 0.46, 0), Vector3(0.05, 0.9, 1.1), 1.0, Color(0.85, 0.8, 0.75))
	_L(F, "wood", Vector3(-1.28, 0.46, 0), Vector3(0.05, 0.9, 1.1), 1.0, Color(0.85, 0.8, 0.75))
	for sx in [-1.25, 1.25]:
		for sz in [-0.9, 0.9]:
			_L(F, "wood", Vector3(sx, 1.2, sz), Vector3(0.07, 2.4, 0.07), 1.0, Color(0.7, 0.62, 0.55))
	_L(F, "fabric", Vector3(0, 2.45, 0), Vector3(3.0, 0.03, 2.2), 1.0, cc, Kit.F_ALL, Vector3(0.18, 0, 0))
	# товар: ящички с фруктами
	var goods := [Color(0.95, 0.5, 0.12), Color(0.85, 0.15, 0.1), Color(0.45, 0.7, 0.2), Color(0.95, 0.85, 0.3)]
	for i in 4:
		var gx := -0.95 + i * 0.63
		_L(F, "crate", Vector3(gx, 1.1, 0.1), Vector3(0.55, 0.2, 0.7), 0.0, Color(0.95, 0.9, 0.85))
		_L(F, "fabric", Vector3(gx, 1.2, 0.1), Vector3(0.5, 0.04, 0.64), 1.0, goods[i])
	ao(pos, 2.6, 1.2, 0.5, yaw, 0.45)


func _bunting(a: Vector3, b: Vector3, sag: float) -> void:
	if not visuals:
		return
	var n := int(a.distance_to(b) / 0.55)
	var prev := a
	var dir := (b - a)
	var yaw := atan2(dir.x, dir.z)
	for i in range(1, n + 1):
		var t := float(i) / n
		var p := a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1 - t), 0)
		var seg := p - prev
		kit.box(M["wire"], Transform3D(Basis.looking_at(seg.normalized(), Vector3.UP), (p + prev) * 0.5), Vector3(0.02, 0.02, seg.length()), 1.0)
		if i < n:
			var cc: Color = CLOTH[i % CLOTH.size()]
			kit.box(M["fabric"], Transform3D(Basis(Vector3.UP, yaw + PI / 2), p - Vector3(0, 0.17, 0)), Vector3(0.26, 0.32, 0.01), 1.0, cc)
		prev = p


func _props() -> void:
	for s in [1.0, -1.0]:
		# ящики
		_crate(Vector3(10 * s, 0.75, 10 * s), 1.5)
		_crate(Vector3(11.5 * s, 0.75, 10 * s), 1.5)
		_crate(Vector3(10.7 * s, 2.25, 10 * s), 1.5, 0.12)
		_crate(Vector3(-10 * s, 0.75, 10 * s), 1.5)
		_crate(Vector3(-10 * s, 0.75, 11.5 * s), 1.5)
		_crate(Vector3(18 * s, 0.65, -4 * s), 1.3)
		_crate(Vector3(-6 * s, 0.65, 22 * s), 1.3)
		_crate(Vector3(6 * s, 0.65, 24 * s), 1.3)
		# мешки с песком
		_col_box(Transform3D(Basis(), Vector3(15 * s, 0.65, 0)), Vector3(0.6, 1.3, 8))
		deco("bags", Vector3(15 * s, 0.575, 0), Vector3(0.62, 1.15, 8), 1.5)
		deco("bags", Vector3(15 * s, 1.22, 0), Vector3(0.5, 0.16, 7.9), 1.5, Color(0.95, 0.92, 0.88))
		ao(Vector3(15 * s, 0, 0), 0.62, 8, 0.6, 0.0, 0.4)
		# бетонные блоки
		_col_box(Transform3D(Basis(), Vector3(0, 0.65, 20 * s)), Vector3(8, 1.3, 0.6))
		for i in 4:
			var bx := -3.0 + i * 2.0
			var tint := Color(1, 1, 1) if i % 2 == 0 else Color(1.0, 0.95, 0.86)
			deco("concrete", Vector3(bx, 0.16, 20 * s), Vector3(1.94, 0.32, 0.62), 2.0, tint)
			deco("concrete", Vector3(bx, 0.44, 20 * s), Vector3(1.94, 0.26, 0.46), 2.0, tint)
			deco("concrete", Vector3(bx, 0.95, 20 * s), Vector3(1.94, 0.76, 0.3), 2.0, tint)
			deco("fabric", Vector3(bx, 1.2, 20 * s), Vector3(1.95, 0.12, 0.31), 0.5, Color(0.95, 0.72, 0.12))
		ao(Vector3(0, 0, 20 * s), 8, 0.62, 0.6, 0.0, 0.4)
		# колонны
		for p in [Vector3(21 * s, 0, 21 * s), Vector3(-21 * s, 0, 21 * s)]:
			solid("stone", p + Vector3(0, 3, 0), Vector3(1.6, 6, 1.6), 2.0)
			deco("stone", p + Vector3(0, 0.3, 0), Vector3(2.0, 0.6, 2.0), 2.0, Color(0.92, 0.88, 0.82), Vector3.ZERO, Kit.F_ALL & ~Kit.F_NY)
			deco("stone", p + Vector3(0, 5.8, 0), Vector3(2.0, 0.4, 2.0), 2.0, Color(0.95, 0.92, 0.88))
			deco("stone", p + Vector3(0, 6.1, 0), Vector3(1.7, 0.2, 1.7), 2.0, Color(0.95, 0.92, 0.88), Vector3.ZERO, Kit.F_ALL & ~Kit.F_NY)
			ao(p, 2.0, 2.0, 0.7)
		# разрушенные дома (Г-стенки)
		var tint2: Color = PLASTER_TINTS[1 if s > 0 else 2]
		solid("plaster", Vector3(22 * s, 1.5, -12 * s), Vector3(6, 3, 0.6), 3.0, tint2)
		solid("plaster", Vector3(19.3 * s, 1.5, -14.5 * s), Vector3(0.6, 3, 5), 3.0, tint2)
		deco("stone", Vector3(22 * s, 3.05, -12 * s), Vector3(6.1, 0.14, 0.72), 2.0, Color(0.95, 0.92, 0.88))
		deco("stone", Vector3(19.3 * s, 3.05, -14.5 * s), Vector3(0.72, 0.14, 5.1), 2.0, Color(0.95, 0.92, 0.88))
		deco("stone", Vector3(22 * s, 0.35, -12 * s), Vector3(6.05, 0.7, 0.7), 2.0, Color.WHITE, Vector3.ZERO, Kit.F_ALL & ~Kit.F_NY)
		deco("stone", Vector3(19.3 * s, 0.35, -14.5 * s), Vector3(0.7, 0.7, 5.05), 2.0, Color.WHITE, Vector3.ZERO, Kit.F_ALL & ~Kit.F_NY)
		deco("stone", Vector3(19.3 * s, 1.6, -12 * s), Vector3(0.8, 3.2, 0.8), 2.0)
		deco("stone", Vector3(24.9 * s, 1.0, -12 * s), Vector3(0.75, 2.0, 0.75), 2.0)
		ao(Vector3(22 * s, 0, -12 * s), 6, 0.7, 0.7, 0.0, 0.4)
		ao(Vector3(19.3 * s, 0, -14.5 * s), 0.7, 5, 0.7, 0.0, 0.4)
		# бочки
		_barrel(Vector3(-24.5 * s, 0, 8 * s), Color(0.95, 0.55, 0.45))
		_barrel(Vector3(-24.0 * s, 0, 8.75 * s), Color(0.55, 0.75, 1.0))
		_barrel(Vector3(8 * s, 0, -27 * s), Color(1, 1, 1))
		_barrel(Vector3(8.7 * s, 0, -26.5 * s), Color(0.95, 0.55, 0.45))
		_barrel(Vector3(8.2 * s, 0, -26.2 * s), Color(0.75, 0.95, 0.6))
	# пальмы у башни
	for p in [Vector3(7.5, 0, 7.5), Vector3(-7.5, 0, -7.5), Vector3(7.5, 0, -7.5), Vector3(-7.5, 0, 7.5)]:
		var lean := Vector3(p.x, 0, p.z).normalized() * 0.25
		_palm(p, rng.randf_range(5.0, 6.0), lean, true, kit)
	# рыночные прилавки
	_stall(Vector3(-14, 0, 31.2), PI)
	_stall(Vector3(14, 0, -31.2), 0.0)
	# гирлянды флажков
	_bunting(Vector3(21, 6.1, 21), Vector3(21, 6.8, 33), 0.7)
	_bunting(Vector3(-21, 6.1, -21), Vector3(-21, 6.8, -33), 0.7)
	_bunting(Vector3(-21, 6.1, 21), Vector3(-33, 6.8, 21), 0.7)
	_bunting(Vector3(21, 6.1, -21), Vector3(33, 6.8, -21), 0.7)
	_bunting(Vector3(-21, 6.1, 21), Vector3(21, 6.1, 21), 1.6)
	_bunting(Vector3(-21, 6.1, -21), Vector3(21, 6.1, -21), 1.6)


# ================================================================ город за стенами (только вид)

func _skyline() -> void:
	var yaws := [PI, 0.0, -PI / 2, PI / 2]
	var origins := [Vector3(0, 0, 33), Vector3(0, 0, -33), Vector3(33, 0, 0), Vector3(-33, 0, 0)]
	var plaster: Material = M["plaster"]
	var stone: Material = M["stone"]
	for side in 4:
		var F := Transform3D(Basis(Vector3.UP, yaws[side]), origins[side])
		var x := -46.0
		while x < 46.0:
			var w := rng.randf_range(7.0, 13.0)
			var h := rng.randf_range(9.5, 17.0)
			var depth := rng.randf_range(6.0, 10.0)
			var z := -1.6 - rng.randf_range(0.5, 6.0) - depth * 0.5
			var tint: Color = PLASTER_TINTS[rng.randi_range(0, PLASTER_TINTS.size() - 1)] * 0.95
			var m: Material = stone if rng.randf() < 0.3 else plaster
			far.box(m, F * Transform3D(Basis(), Vector3(x + w * 0.5, h * 0.5, z)), Vector3(w, h, depth), 3.0, tint, Kit.F_PZ | Kit.F_PY | Kit.F_PX | Kit.F_NX)
			far.box(M["stone"], F * Transform3D(Basis(), Vector3(x + w * 0.5, h + 0.2, z)), Vector3(w + 0.2, 0.4, depth + 0.2), 2.0, Color(0.9, 0.88, 0.84), Kit.F_PZ | Kit.F_PY | Kit.F_PX | Kit.F_NX)
			var cols := int(w / 2.2)
			var row_y := 8.0
			while row_y < h - 1.0:
				for c in cols:
					var wx := x + (c + 0.5) * w / cols
					far.box(M["dark"], F * Transform3D(Basis(), Vector3(wx, row_y, z + depth * 0.5 + 0.02)), Vector3(0.9, 1.2, 0.04), 1.0)
				row_y += 3.0
			if rng.randf() < 0.5:
				far.cylinder(M["metal"], F * Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(x + w * 0.5, h + 1.0, z)), 0.6, 0.6, 1.8, 10, 1.0, Color(1.1, 1.1, 1.1))
			x += w + rng.randf_range(0.0, 1.5)
		# пальмы за стеной
		for i in 3:
			var px := rng.randf_range(-28.0, 28.0)
			_palm(F * Vector3(px, 0, -rng.randf_range(2.5, 4.5)), rng.randf_range(9.0, 11.0), Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3)), false, far)
	# минарет — ориентир на горизонте
	var mp := Vector3(-30, 0, 52)
	far.cylinder(stone, Transform3D(Basis(), mp + Vector3(0, 12, 0)), 1.5, 1.8, 24.0, 16, 2.0, Color.WHITE, false)
	far.cylinder(stone, Transform3D(Basis(), mp + Vector3(0, 20.3, 0)), 2.3, 2.0, 0.6, 16, 2.0, Color(0.95, 0.92, 0.88))
	far.cylinder(plaster, Transform3D(Basis(), mp + Vector3(0, 23.5, 0)), 1.15, 1.2, 5.8, 16, 2.0, Color(0.98, 0.95, 0.9), false)
	far.cylinder(M["metal"], Transform3D(Basis(), mp + Vector3(0, 27.6, 0)), 0.05, 1.35, 2.6, 16, 1.0, Color(0.6, 1.3, 1.2))
	# купол
	var dp := Vector3(18, 0, -52)
	far.box(stone, Transform3D(Basis(), dp + Vector3(0, 6, 0)), Vector3(14, 12, 14), 2.0, Color.WHITE, Kit.F_ALL & ~Kit.F_NY)
	for i in 6:
		var t0 := float(i) / 6.0
		var t1 := float(i + 1) / 6.0
		var r0 := 6.0 * cos(t0 * PI / 2)
		var r1 := 6.0 * cos(t1 * PI / 2)
		var y0 := 12.0 + 6.0 * sin(t0 * PI / 2)
		var y1 := 12.0 + 6.0 * sin(t1 * PI / 2)
		far.cylinder(M["metal"], Transform3D(Basis(), dp + Vector3(0, (y0 + y1) * 0.5, 0)), maxf(r1, 0.05), r0, y1 - y0, 24, 2.0, Color(0.7, 1.35, 1.25), false)

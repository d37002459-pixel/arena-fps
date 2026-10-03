extends RefCounted
## Сборщик геометрии. Много коробок/цилиндров одного материала складываются
## в один меш — так сцена рисуется за десяток вызовов, а не за сотни (важно для браузера).

const WorldShader := preload("res://shaders/world.gdshader")
const AoShader := preload("res://shaders/ao_blob.gdshader")

# Для каждого материала: массивы вершин
var surfaces := {}

# Кэш материалов по имени текстуры (общий для всех)
static var _mats := {}
static var _grime: Texture2D


## Материал окружения по имени текстуры из res://textures
static func mat(tex_name: String, roughness := 0.85, metallic := 0.0, normal_strength := 1.0, grime := 0.22, ground_ao := 0.42) -> ShaderMaterial:
	var key := "%s/%s/%s/%s/%s/%s" % [tex_name, roughness, metallic, normal_strength, grime, ground_ao]
	if _mats.has(key):
		return _mats[key]
	if _grime == null:
		_grime = load("res://textures/grime.png")
	var m := ShaderMaterial.new()
	m.shader = WorldShader
	m.set_shader_parameter("albedo_tex", load("res://textures/%s.png" % tex_name))
	m.set_shader_parameter("normal_tex", load("res://textures/%s_n.png" % tex_name))
	m.set_shader_parameter("grime_tex", _grime)
	m.set_shader_parameter("roughness", roughness)
	m.set_shader_parameter("metallic", metallic)
	m.set_shader_parameter("normal_strength", normal_strength)
	m.set_shader_parameter("grime_amount", grime)
	m.set_shader_parameter("ground_ao", ground_ao)
	_mats[key] = m
	return m


static func ao_material(strength := 0.35) -> ShaderMaterial:
	var key := "ao/%s" % strength
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = AoShader
	m.set_shader_parameter("strength", strength)
	m.render_priority = -1
	_mats[key] = m
	return m


static func flat_mat(c: Color, roughness := 0.7, metallic := 0.0, emission := Color.BLACK) -> StandardMaterial3D:
	var key := "flat/%s/%s/%s/%s" % [c.to_html(), roughness, metallic, emission.to_html()]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = roughness
	m.metallic = metallic
	m.vertex_color_use_as_albedo = true
	if emission != Color.BLACK:
		m.emission_enabled = true
		m.emission = emission
	_mats[key] = m
	return m


func _surf(m: Material) -> Dictionary:
	if not surfaces.has(m):
		surfaces[m] = {
			"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(),
			"c": PackedColorArray(), "i": PackedInt32Array(),
		}
	return surfaces[m]


# грани коробки: нормаль, ось U, ось V (V смотрит вниз на боковых гранях)
const FACES := [
	[Vector3.RIGHT, Vector3.FORWARD, Vector3.DOWN],
	[Vector3.LEFT, Vector3.BACK, Vector3.DOWN],
	[Vector3.UP, Vector3.RIGHT, Vector3.BACK],
	[Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
	[Vector3.BACK, Vector3.RIGHT, Vector3.DOWN],
	[Vector3.FORWARD, Vector3.LEFT, Vector3.DOWN],
]
const F_PX := 1
const F_NX := 2
const F_PY := 4
const F_NY := 8
const F_PZ := 16
const F_NZ := 32
const F_ALL := 63


## Коробка. tile — сколько метров на один повтор текстуры (UV по миру, швы совпадают);
## tile <= 0 — каждая грань целиком 0..1 (для ящиков). faces — какие грани рисовать.
func box(m: Material, xf: Transform3D, size: Vector3, tile := 2.0, color := Color.WHITE, faces := F_ALL, uv_off := Vector2.ZERO) -> void:
	var s := _surf(m)
	var h := size * 0.5
	for fi in 6:
		if not (faces & (1 << fi)):
			continue
		var f: Array = FACES[fi]
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var hn := absf(n.dot(h))
		var hu := absf(u.dot(h))
		var hv := absf(v.dot(h))
		var nw := (xf.basis * n).normalized()
		var uw := (xf.basis * u).normalized()
		var vw := (xf.basis * v).normalized()
		var base: int = s["v"].size()
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var lp: Vector3 = n * hn + u * hu * corner.x + v * hv * corner.y
			var wp := xf * lp
			s["v"].append(wp)
			s["n"].append(nw)
			s["c"].append(color)
			if tile > 0.0:
				s["uv"].append(Vector2(wp.dot(uw), wp.dot(vw)) / tile + uv_off)
			else:
				s["uv"].append(Vector2(corner.x * 0.5 + 0.5, corner.y * 0.5 + 0.5))
		s["i"].append_array([base, base + 1, base + 2, base, base + 2, base + 3])


## Цилиндр вдоль локальной оси Y (центр в xf.origin).
func cylinder(m: Material, xf: Transform3D, r_top: float, r_bottom: float, height: float, seg := 12, tile := 1.0, color := Color.WHITE, caps := true) -> void:
	var s := _surf(m)
	var hh := height * 0.5
	var circ := TAU * maxf(r_top, r_bottom)
	var base: int = s["v"].size()
	var slope := (r_bottom - r_top) / height
	for i in seg + 1:
		var a := TAU * i / seg
		var d := Vector3(cos(a), 0, sin(a))
		var nl := (d + Vector3(0, slope, 0)).normalized()
		for k in 2:
			var y := hh if k == 0 else -hh
			var r := r_top if k == 0 else r_bottom
			s["v"].append(xf * (d * r + Vector3(0, y, 0)))
			s["n"].append((xf.basis * nl).normalized())
			s["c"].append(color)
			var uu := (circ * i / seg) / tile if tile > 0 else float(i) / seg
			var vv := (hh - y) / tile if tile > 0 else (0.0 if k == 0 else 1.0)
			s["uv"].append(Vector2(uu, vv))
	for i in seg:
		var a: int = base + i * 2
		s["i"].append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	if caps:
		for k in 2:
			var y := hh if k == 0 else -hh
			var r := r_top if k == 0 else r_bottom
			var nl := Vector3.UP if k == 0 else Vector3.DOWN
			var c0: int = s["v"].size()
			s["v"].append(xf * Vector3(0, y, 0))
			s["n"].append((xf.basis * nl).normalized())
			s["c"].append(color)
			s["uv"].append(Vector2(0.5, 0.5))
			for i in seg + 1:
				var a := TAU * i / seg
				s["v"].append(xf * Vector3(cos(a) * r, y, sin(a) * r))
				s["n"].append((xf.basis * nl).normalized())
				s["c"].append(color)
				s["uv"].append(Vector2(cos(a), sin(a)) * (r / tile if tile > 0 else 0.5) + Vector2(0.5, 0.5))
			for i in seg:
				if k == 0:
					s["i"].append_array([c0, c0 + 1 + i, c0 + 2 + i])
				else:
					s["i"].append_array([c0, c0 + 2 + i, c0 + 1 + i])


## Прямоугольник (лист, навес). Лежит в плоскости XY локально, нормаль +Z.
func quad(m: Material, xf: Transform3D, w: float, h: float, color := Color.WHITE, uv0 := Vector2.ZERO, uv1 := Vector2.ONE) -> void:
	var s := _surf(m)
	var base: int = s["v"].size()
	var nw := (xf.basis * Vector3.BACK).normalized()
	var pts := [Vector3(-w / 2, h / 2, 0), Vector3(w / 2, h / 2, 0), Vector3(w / 2, -h / 2, 0), Vector3(-w / 2, -h / 2, 0)]
	var uvs := [uv0, Vector2(uv1.x, uv0.y), uv1, Vector2(uv0.x, uv1.y)]
	for i in 4:
		s["v"].append(xf * pts[i])
		s["n"].append(nw)
		s["c"].append(color)
		s["uv"].append(uvs[i])
	s["i"].append_array([base, base + 1, base + 2, base, base + 2, base + 3])


## Мягкая тень на полу вокруг прямоугольного основания (9 частей, края не растягиваются).
func ao_rect(center: Vector3, size_x: float, size_z: float, margin := 0.7, yaw := 0.0, strength := 0.35) -> void:
	var m := ao_material(strength)
	var s := _surf(m)
	var hx := size_x * 0.5
	var hz := size_z * 0.5
	var xs := [-hx - margin, -hx, hx, hx + margin]
	var zs := [-hz - margin, -hz, hz, hz + margin]
	var uvk := [0.0, 0.5, 0.5, 1.0]
	var b := Basis(Vector3.UP, yaw)
	var base: int = s["v"].size()
	for zi in 4:
		for xi in 4:
			s["v"].append(center + b * Vector3(xs[xi], 0.012, zs[zi]))
			s["n"].append(Vector3.UP)
			s["c"].append(Color.WHITE)
			s["uv"].append(Vector2(uvk[xi], uvk[zi]))
	for zi in 3:
		for xi in 3:
			var a: int = base + zi * 4 + xi
			s["i"].append_array([a, a + 1, a + 5, a, a + 5, a + 4])


## Собирает всё в узлы MeshInstance3D (один на материал).
func build(parent: Node3D, cast_shadows := true) -> void:
	for m in surfaces:
		var s: Dictionary = surfaces[m]
		if s["i"].is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = s["v"]
		arr[Mesh.ARRAY_NORMAL] = s["n"]
		arr[Mesh.ARRAY_TEX_UV] = s["uv"]
		arr[Mesh.ARRAY_COLOR] = s["c"]
		arr[Mesh.ARRAY_INDEX] = s["i"]
		var st := SurfaceTool.new()
		st.create_from_arrays(arr)
		var is_ao: bool = m is ShaderMaterial and m.shader == AoShader
		if not is_ao:
			st.generate_tangents()
		var mesh := st.commit()
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = m
		if is_ao or not cast_shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
	surfaces.clear()


## Отдельный меш (для частей персонажа/оружия): то же, но возвращает ArrayMesh.
func build_mesh() -> ArrayMesh:
	var out := ArrayMesh.new()
	for m in surfaces:
		var s: Dictionary = surfaces[m]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = s["v"]
		arr[Mesh.ARRAY_NORMAL] = s["n"]
		arr[Mesh.ARRAY_TEX_UV] = s["uv"]
		arr[Mesh.ARRAY_COLOR] = s["c"]
		arr[Mesh.ARRAY_INDEX] = s["i"]
		var st := SurfaceTool.new()
		st.create_from_arrays(arr)
		st.generate_tangents()
		st.set_material(m)
		st.commit(out)
	surfaces.clear()
	return out

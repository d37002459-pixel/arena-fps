extends RefCounted
## Модели персонажа и оружия (собираются кодом, меши кэшируются и общие для всех игроков).

const Kit := preload("res://meshkit.gd")

const OLIVE := Color(0.62, 0.66, 0.5)
const TAN := Color(0.95, 0.88, 0.74)
const DARK := Color(0.2, 0.19, 0.17)
const SKIN := Color(0.78, 0.6, 0.48)
const GUNMETAL_C := Color(0.16, 0.16, 0.17)
const WOOD_C := Color(0.5, 0.24, 0.12)

static var _cache := {}
static var _m := {}


static func mats() -> Dictionary:
	if _m.is_empty():
		_m["camo"] = Kit.mat("camo", 0.9, 0.0, 0.9, 0.0, 0.0)
		_m["gunmetal"] = Kit.mat("gunmetal", 0.5, 0.3, 1.0, 0.0, 0.0)
		_m["gunwood"] = Kit.mat("gunwood", 0.45, 0.0, 0.8, 0.0, 0.0)
		_m["flat"] = Kit.flat_mat(Color.WHITE, 0.7)
		_m["dark"] = Kit.flat_mat(Color(0.13, 0.12, 0.11), 0.85)
	return _m


## Коробка, вытянутая от точки a до точки b (руки, ремни)
static func seg(k: Kit, m: Material, a: Vector3, b: Vector3, t: float, tile := 0.3, color := Color.WHITE, t2 := -1.0) -> void:
	var d := b - a
	var up := Vector3.UP if absf(d.normalized().y) < 0.9 else Vector3.FORWARD
	k.box(m, Transform3D(Basis.looking_at(d.normalized(), up), (a + b) * 0.5), Vector3(t, t if t2 < 0 else t2, d.length()), tile, color)


static func _bx(k: Kit, m: Material, pos: Vector3, size: Vector3, tile := 0.3, color := Color.WHITE, rot := Vector3.ZERO) -> void:
	k.box(m, Transform3D(Basis.from_euler(rot), pos), size, tile, color)


static func _cyl_z(k: Kit, m: Material, pos: Vector3, r: float, length: float, tile := 0.2, color := Color.WHITE, r2 := -1.0) -> void:
	# цилиндр вдоль оси Z (ствол)
	k.cylinder(m, Transform3D(Basis(Vector3.RIGHT, PI / 2), pos), r, r if r2 < 0 else r2, length, 10, tile, color)


# ================================================================ солдат

## Части солдата. Всё рисуется двумя материалами (камуфляж + однотонный), чтобы было мало вызовов отрисовки.
static func part(name: String, color := Color.WHITE) -> ArrayMesh:
	var key := "%s/%s" % [name, color.to_html()]
	if _cache.has(key):
		return _cache[key]
	var M := mats()
	var k := Kit.new()
	var camo: Material = M["camo"]
	var flat: Material = M["flat"]
	match name:
		"thigh":
			_bx(k, camo, Vector3(0, -0.21, 0), Vector3(0.155, 0.46, 0.17))
			_bx(k, camo, Vector3(0, -0.40, -0.09), Vector3(0.12, 0.11, 0.04), 0.3, DARK)        # наколенник
			_bx(k, camo, Vector3(0.085, -0.2, 0), Vector3(0.03, 0.14, 0.12), 0.3, OLIVE)       # карман
		"shin":
			_bx(k, camo, Vector3(0, -0.19, 0), Vector3(0.13, 0.40, 0.15))
			_bx(k, camo, Vector3(0, -0.40, -0.035), Vector3(0.15, 0.13, 0.29), 0.3, DARK)       # ботинок
			_bx(k, camo, Vector3(0, -0.32, 0), Vector3(0.14, 0.06, 0.16), 0.3, DARK)
		"pelvis":
			_bx(k, camo, Vector3(0, 0, 0), Vector3(0.36, 0.2, 0.22))
			_bx(k, camo, Vector3(0, 0.08, 0), Vector3(0.38, 0.05, 0.24), 0.3, DARK)             # ремень
			_bx(k, camo, Vector3(0.2, -0.02, 0.02), Vector3(0.06, 0.16, 0.14), 0.3, OLIVE)     # подсумок
		"torso":
			_bx(k, camo, Vector3(0, 0.24, 0), Vector3(0.40, 0.48, 0.23))
			_bx(k, camo, Vector3(0, 0.26, 0), Vector3(0.44, 0.36, 0.29), 0.3, OLIVE)           # бронежилет
			for x in [-0.13, 0.0, 0.13]:
				_bx(k, camo, Vector3(x, 0.15, -0.165), Vector3(0.11, 0.13, 0.06), 0.3, OLIVE * 0.85)
			_bx(k, camo, Vector3(0, 0.27, 0.18), Vector3(0.3, 0.32, 0.08), 0.3, OLIVE * 0.9)   # рюкзак
			_bx(k, camo, Vector3(0, 0.47, 0), Vector3(0.3, 0.07, 0.25), 0.3, TAN)              # шемаг
			var ra := Vector3(0.25, 0.42, 0.0)
			var re := Vector3(0.28, 0.21, -0.07)
			var rh := Vector3(0.11, 0.27, -0.2)
			var la := Vector3(-0.25, 0.42, 0.0)
			var le := Vector3(-0.24, 0.2, -0.24)
			var lh := Vector3(0.06, 0.31, -0.5)
			seg(k, camo, ra, re, 0.115)
			seg(k, camo, re, rh, 0.095)
			seg(k, camo, la, le, 0.115)
			seg(k, camo, le, lh, 0.095)
			_bx(k, camo, rh, Vector3(0.085, 0.09, 0.1), 0.3, DARK)                              # перчатки
			_bx(k, camo, lh, Vector3(0.085, 0.08, 0.11), 0.3, DARK)
			for p in [ra, la]:
				_bx(k, camo, p + Vector3(0, -0.02, 0), Vector3(0.14, 0.14, 0.15), 0.3, OLIVE)
			# повязка цвета игрока на левом плече
			var bp := la.lerp(le, 0.55)
			var bd := (le - la).normalized()
			seg(k, flat, bp - bd * 0.03, bp + bd * 0.03, 0.125, 0.3, color)
			tp_rifle(k, Vector3(0.1, 0.36, 0.0), flat, flat, GUNMETAL_C, WOOD_C)
		"head":
			k.cylinder(flat, Transform3D(Basis(), Vector3(0, 0.03, 0)), 0.055, 0.06, 0.1, 8, 0.3, SKIN)
			_bx(k, flat, Vector3(0, 0.15, 0), Vector3(0.18, 0.22, 0.2), 0.3, SKIN)
			_bx(k, flat, Vector3(0.045, 0.18, -0.101), Vector3(0.032, 0.014, 0.01), 0.3, Color(0.08, 0.07, 0.06))
			_bx(k, flat, Vector3(-0.045, 0.18, -0.101), Vector3(0.032, 0.014, 0.01), 0.3, Color(0.08, 0.07, 0.06))
			_bx(k, camo, Vector3(0, 0.075, -0.005), Vector3(0.195, 0.1, 0.21), 0.3, TAN)       # шемаг на лице
			k.cylinder(camo, Transform3D(Basis(), Vector3(0, 0.27, 0.005)), 0.118, 0.138, 0.13, 14, 0.3, OLIVE)
			k.cylinder(camo, Transform3D(Basis(), Vector3(0, 0.355, 0.005)), 0.06, 0.118, 0.05, 14, 0.3, OLIVE)
			k.cylinder(flat, Transform3D(Basis(), Vector3(0, 0.235, 0.005)), 0.141, 0.141, 0.032, 14, 0.3, color, false)
			_bx(k, flat, Vector3(0, 0.3, -0.122), Vector3(0.15, 0.045, 0.035), 0.3, Color(0.05, 0.06, 0.07))  # очки
			_bx(k, flat, Vector3(0, 0.3, -0.105), Vector3(0.2, 0.025, 0.02), 0.3, Color(0.12, 0.11, 0.1))
	var mesh := k.build_mesh()
	_cache[key] = mesh
	return mesh


## Автомат в руках солдата (вид со стороны). o — затыльник приклада, ствол в -Z.
static func tp_rifle(k: Kit, o: Vector3, gm: Material, gw: Material, cm: Color, cw: Color) -> void:
	_bx(k, gw, o + Vector3(0, -0.025, -0.08), Vector3(0.045, 0.1, 0.22), 0.2, cw, Vector3(0.12, 0, 0))            # приклад
	_bx(k, gm, o + Vector3(0, 0.0, -0.33), Vector3(0.05, 0.09, 0.32), 0.15, cm)                                   # ствольная коробка
	_bx(k, gw, o + Vector3(0, -0.07, -0.25), Vector3(0.04, 0.1, 0.05), 0.2, cw * 0.7, Vector3(-0.3, 0, 0))        # рукоять
	_bx(k, gw, o + Vector3(0, -0.12, -0.38), Vector3(0.04, 0.15, 0.07), 0.2, cw * 1.3, Vector3(0.3, 0, 0))        # магазин
	_bx(k, gw, o + Vector3(0, 0.0, -0.6), Vector3(0.06, 0.07, 0.22), 0.2, cw)                                     # цевьё
	_bx(k, gw, o + Vector3(0, 0.045, -0.6), Vector3(0.045, 0.035, 0.2), 0.2, cw)
	_cyl_z(k, gm, o + Vector3(0, 0.01, -0.86), 0.012, 0.32, 0.15, cm)
	_cyl_z(k, gm, o + Vector3(0, 0.01, -1.03), 0.018, 0.06, 0.15, cm)
	_bx(k, gm, o + Vector3(0, 0.07, -0.33), Vector3(0.035, 0.035, 0.08), 0.15, cm)                                # прицел


# ================================================================ автомат от первого лица

## Координаты: центр ствольной коробки, ствол по -Z, ось ствола y=0.012, дуло z=-0.71
static func fp_gun() -> ArrayMesh:
	if _cache.has("fp_gun"):
		return _cache["fp_gun"]
	var M := mats()
	var k := Kit.new()
	var gm: Material = M["gunmetal"]
	var gw: Material = M["gunwood"]
	var bake := Color(0.72, 0.5, 0.42)
	# ствольная коробка и крышка
	_bx(k, gm, Vector3(0, -0.005, 0.0), Vector3(0.058, 0.095, 0.36), 0.12)
	_cyl_z(k, gm, Vector3(0, 0.043, 0.01), 0.028, 0.33, 0.12)
	_bx(k, gm, Vector3(0, 0.05, -0.165), Vector3(0.044, 0.03, 0.05), 0.12)            # колодка прицела
	_bx(k, M["dark"], Vector3(0.0295, 0.015, -0.005), Vector3(0.003, 0.03, 0.08))      # окно экстракции
	_bx(k, gm, Vector3(0.035, 0.02, 0.07), Vector3(0.03, 0.016, 0.03), 0.12)           # рукоятка затвора
	_bx(k, gm, Vector3(0.0305, 0.012, -0.02), Vector3(0.004, 0.018, 0.13), 0.12)       # предохранитель
	# планка и коллиматор
	_bx(k, gm, Vector3(0, 0.072, 0.02), Vector3(0.03, 0.02, 0.13), 0.12)
	_bx(k, gm, Vector3(0, 0.08, 0.02), Vector3(0.036, 0.012, 0.05), 0.12)
	_bx(k, gm, Vector3(0, 0.0805, 0.0225), Vector3(0.05, 0.01, 0.06), 0.12)
	_bx(k, gm, Vector3(0.027, 0.1, 0.0225), Vector3(0.006, 0.04, 0.045), 0.12)
	_bx(k, gm, Vector3(-0.027, 0.1, 0.0225), Vector3(0.006, 0.04, 0.045), 0.12)
	# цевьё (дерево) и газовая трубка
	_bx(k, gw, Vector3(0, -0.012, -0.31), Vector3(0.07, 0.072, 0.24), 0.25)
	_bx(k, gw, Vector3(0, 0.046, -0.30), Vector3(0.05, 0.04, 0.21), 0.25)
	_bx(k, gm, Vector3(0, -0.012, -0.19), Vector3(0.074, 0.076, 0.02), 0.12)
	_bx(k, gm, Vector3(0, -0.012, -0.43), Vector3(0.074, 0.076, 0.02), 0.12)
	_bx(k, gm, Vector3(0, 0.04, -0.46), Vector3(0.04, 0.05, 0.05), 0.12)
	_cyl_z(k, gm, Vector3(0, 0.046, -0.5), 0.011, 0.08, 0.12)
	# ствол, мушка, ДТК
	_cyl_z(k, gm, Vector3(0, 0.012, -0.55), 0.0125, 0.26, 0.12)
	_bx(k, gm, Vector3(0, 0.03, -0.6), Vector3(0.03, 0.04, 0.035), 0.12)
	_bx(k, gm, Vector3(0, 0.06, -0.6), Vector3(0.005, 0.03, 0.006), 0.12)
	_cyl_z(k, gm, Vector3(0, 0.012, -0.67), 0.018, 0.08, 0.12, Color(0.85, 0.85, 0.85))
	# рукоять и спусковая скоба
	_bx(k, gw, Vector3(0, -0.1, 0.1), Vector3(0.042, 0.12, 0.056), 0.25, bake, Vector3(-0.32, 0, 0))
	_bx(k, gm, Vector3(0, -0.065, 0.035), Vector3(0.012, 0.012, 0.08), 0.12)
	_bx(k, gm, Vector3(0, -0.075, 0.07), Vector3(0.012, 0.03, 0.012), 0.12)
	# руки
	var camo: Material = M["camo"]
	_bx(k, M["dark"], Vector3(-0.012, -0.06, -0.32), Vector3(0.08, 0.065, 0.11))                     # левая кисть
	_bx(k, M["dark"], Vector3(0.03, -0.025, -0.33), Vector3(0.035, 0.03, 0.09))                     # пальцы
	seg(k, camo, Vector3(-0.03, -0.085, -0.29), Vector3(-0.15, -0.34, 0.02), 0.085, 0.25)            # левое предплечье
	_bx(k, M["dark"], Vector3(0.002, -0.1, 0.105), Vector3(0.075, 0.085, 0.09), 0.3, Color.WHITE, Vector3(-0.32, 0, 0))  # правая кисть
	seg(k, camo, Vector3(0.02, -0.13, 0.15), Vector3(0.12, -0.3, 0.45), 0.095, 0.25)                # правое предплечье
	var mesh := k.build_mesh()
	_cache["fp_gun"] = mesh
	return mesh


## Изогнутый магазин (отдельно — он двигается при перезарядке)
static func fp_mag() -> ArrayMesh:
	if _cache.has("fp_mag"):
		return _cache["fp_mag"]
	var M := mats()
	var k := Kit.new()
	var gw: Material = M["gunwood"]
	var tint := Color(1.0, 0.72, 0.5)
	var y := 0.0
	var z := 0.0
	var a := 0.0
	for i in 4:
		_bx(k, gw, Vector3(0, y, z), Vector3(0.04, 0.06, 0.075), 0.2, tint, Vector3(a, 0, 0))
		y -= 0.052
		z -= 0.012 * (i + 1)
		a += 0.14
	_bx(k, M["gunmetal"], Vector3(0, y + 0.02, z + 0.01), Vector3(0.044, 0.016, 0.08), 0.12, Color.WHITE, Vector3(a, 0, 0))
	var mesh := k.build_mesh()
	_cache["fp_mag"] = mesh
	return mesh

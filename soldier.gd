extends Node3D
## Солдат, которого видят другие игроки: ходьба, наклон по прицелу, падение при смерти.

const Models := preload("res://models.gd")

var color := Color.WHITE
var shadow_only := false

var model: Node3D
var pelvis: Node3D
var spine: Node3D
var neck: Node3D
var hips: Array[Node3D] = []
var knees: Array[Node3D] = []
var muzzle: Node3D

var phase := 0.0
var amp := 0.0
var dead := false
var fall := 0.0


func _ready() -> void:
	model = Node3D.new()
	add_child(model)
	pelvis = _pivot(model, Vector3(0, 0.94, 0))
	_mesh(pelvis, Models.part("pelvis"))
	for sx in [-0.1, 0.1]:
		var hip := _pivot(pelvis, Vector3(sx, -0.04, 0))
		_mesh(hip, Models.part("thigh"))
		var knee := _pivot(hip, Vector3(0, -0.44, 0))
		_mesh(knee, Models.part("shin"))
		hips.append(hip)
		knees.append(knee)
	spine = _pivot(pelvis, Vector3(0, 0.06, 0))
	_mesh(spine, Models.part("torso", color))
	neck = _pivot(spine, Vector3(0, 0.5, 0))
	_mesh(neck, Models.part("head", color))
	muzzle = _pivot(spine, Vector3(0.1, 0.37, -1.08))


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _mesh(parent: Node3D, mesh: Mesh) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if shadow_only:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	parent.add_child(mi)


## local_vel — скорость в координатах игрока (x вбок, z вперёд/назад)
func animate(delta: float, local_vel: Vector3, on_floor: bool, aim_pitch: float) -> void:
	if dead:
		fall = minf(fall + delta * 3.2, 1.0)
		var e := fall * fall
		model.rotation.x = e * PI * 0.5
		model.position.y = e * 0.14
		spine.rotation.x = lerpf(spine.rotation.x, 0.3, delta * 6.0)
		return
	var horiz := Vector2(local_vel.x, local_vel.z).length()
	amp = lerpf(amp, clampf(horiz / 6.0, 0.0, 1.0), clampf(delta * 10.0, 0.0, 1.0))
	phase += delta * (4.0 + horiz * 1.1)
	var back := 1.0 if local_vel.z > 0.5 else 0.0  # пятимся
	var s := sin(phase) * (1.0 - back * 2.0)
	if on_floor:
		hips[0].rotation.x = s * 0.65 * amp
		hips[1].rotation.x = -s * 0.65 * amp
		knees[0].rotation.x = -maxf(0.0, sin(phase - 1.3)) * 1.1 * amp
		knees[1].rotation.x = -maxf(0.0, sin(phase + PI - 1.3)) * 1.1 * amp
		pelvis.position.y = 0.94 - absf(cos(phase)) * 0.045 * amp
	else:
		for i in 2:
			hips[i].rotation.x = lerpf(hips[i].rotation.x, 0.55 if i == 0 else 0.25, delta * 8.0)
			knees[i].rotation.x = lerpf(knees[i].rotation.x, -0.9 if i == 0 else -0.5, delta * 8.0)
	# стрейф — лёгкий разворот ног
	pelvis.rotation.y = lerpf(pelvis.rotation.y, clampf(-local_vel.x * 0.06, -0.4, 0.4), delta * 6.0)
	spine.rotation.y = -pelvis.rotation.y
	spine.rotation.x = clampf(aim_pitch, -1.2, 1.2) * 0.75 - amp * 0.08
	neck.rotation.x = clampf(aim_pitch, -1.2, 1.2) * 0.25


func die() -> void:
	dead = true
	fall = 0.0


func revive() -> void:
	dead = false
	fall = 0.0
	model.rotation = Vector3.ZERO
	model.position = Vector3.ZERO

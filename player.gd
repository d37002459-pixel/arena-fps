extends CharacterBody3D
## Игрок. Движением управляет владелец (клиент), попадания и урон считает сервер.

const WALK_SPEED := 6.0
const SPRINT_SPEED := 9.0
const JUMP_VELOCITY := 5.6
const GRAVITY := 16.0
const MOUSE_SENS := 0.0022
const MAX_HP := 100
const FIRE_DELAY := 0.11
const MAG_SIZE := 30
const RELOAD_TIME := 1.6
const BODY_DAMAGE := 20
const HEAD_DAMAGE := 55
const RESPAWN_DELAY := 3.0
const HEAD_HEIGHT := 1.6
const GUN_REST := Vector3(0.24, -0.24, -0.48)

static var _mat_cache := {}

var peer_id := 1
var player_name := "Игрок"
var hp := MAX_HP
var alive := true
var pitch := 0.0

# синхронизируются от владельца ко всем
var sync_pos := Vector3.ZERO
var sync_yaw := 0.0
var sync_pitch := 0.0

var main: Node
var head: Node3D
var camera: Camera3D
var gun: Node3D
var muzzle: Node3D
var body_visuals: Node3D
var name_label: Label3D

# только у владельца
var ammo := MAG_SIZE
var reload_left := 0.0
var fire_cd := 0.0
var fell_pending := false
var is_bot := false
var bot_timer := 0.0
var bot_move := Vector2.ZERO
var bot_fire := false

# только на сервере
var srv_shot_credit := 3.0
var srv_invuln := 0.0
var srv_shots: Array = []


func _init() -> void:
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	var cfg := SceneReplicationConfig.new()
	for prop in [":sync_pos", ":sync_yaw", ":sync_pitch"]:
		var path := NodePath("." + prop)
		cfg.add_property(path)
		cfg.property_set_spawn(path, false)
		cfg.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = cfg
	sync.replication_interval = 1.0 / 30.0
	add_child(sync)


func _enter_tree() -> void:
	set_multiplayer_authority(peer_id)


func _ready() -> void:
	main = get_node("/root/Main")
	sync_pos = position
	sync_yaw = rotation.y
	collision_layer = 2
	collision_mask = 1 | 2
	floor_max_angle = deg_to_rad(50)

	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	shape.shape = cap
	shape.position.y = 0.9
	add_child(shape)

	_build_visuals()

	if is_multiplayer_authority():
		is_bot = main.bot_mode
		camera.current = true
		body_visuals.visible = false
		name_label.visible = false
		if not is_bot and DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if main.hud:
			main.hud.set_in_game(true)
			main.hud.hide_center()
			main.hud.set_hp(hp, false)
		_hud_ammo()


func _build_visuals() -> void:
	var color := Color.from_hsv(fmod(peer_id * 0.618034, 1.0), 0.6, 0.95)

	body_visuals = Node3D.new()
	add_child(body_visuals)
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.4
	cm.height = 1.8
	body.mesh = cm
	body.position.y = 0.9
	body.material_override = _mat(color)
	body_visuals.add_child(body)

	head = Node3D.new()
	head.position.y = HEAD_HEIGHT
	add_child(head)

	# «визор», чтобы было видно, куда смотрит противник
	var visor := MeshInstance3D.new()
	var vm := BoxMesh.new()
	vm.size = Vector3(0.5, 0.14, 0.14)
	visor.mesh = vm
	visor.position = Vector3(0, 0.02, -0.34)
	visor.material_override = _mat(Color(0.08, 0.09, 0.12))
	head.add_child(visor)

	camera = Camera3D.new()
	camera.fov = 80
	camera.near = 0.05
	head.add_child(camera)

	gun = Node3D.new()
	gun.position = GUN_REST
	head.add_child(gun)
	var gm := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(0.07, 0.1, 0.55)
	gm.mesh = gb
	gm.material_override = _mat(Color(0.15, 0.16, 0.18))
	gun.add_child(gm)
	var sight := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.03, 0.04, 0.12)
	sight.mesh = sb
	sight.position = Vector3(0, 0.07, 0.05)
	sight.material_override = _mat(color)
	gun.add_child(sight)
	var mag := MeshInstance3D.new()
	var mb := BoxMesh.new()
	mb.size = Vector3(0.05, 0.16, 0.08)
	mag.mesh = mb
	mag.position = Vector3(0, -0.11, -0.05)
	mag.material_override = _mat(Color(0.25, 0.25, 0.27))
	gun.add_child(mag)
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, 0.01, -0.3)
	gun.add_child(muzzle)

	name_label = Label3D.new()
	name_label.text = player_name
	name_label.font = preload("res://fonts/Inter-SemiBold.otf")
	name_label.position.y = 2.2
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.pixel_size = 0.004
	name_label.font_size = 56
	name_label.outline_size = 12
	name_label.modulate = color.lightened(0.3)
	add_child(name_label)

	if is_multiplayer_authority():
		visor.visible = false


static func _mat(c: Color) -> StandardMaterial3D:
	if _mat_cache.has(c):
		return _mat_cache[c]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	_mat_cache[c] = m
	return m


# ---------------------------------------------------------------- ввод

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or is_bot:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		pitch = clamp(pitch - event.relative.y * MOUSE_SENS, -1.45, 1.45)
		head.rotation.x = pitch
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		fire_cd = 0.25  # чтобы клик «вернуть мышь» не стрелял
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.physical_keycode == KEY_R:
			_start_reload()


# ---------------------------------------------------------------- кадр

func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if is_multiplayer_authority():
		_local_process(delta)
	else:
		_remote_process(delta)
	if multiplayer.is_server():
		_server_process(delta)


func _remote_process(delta: float) -> void:
	var k: float = clamp(delta * 18.0, 0.0, 1.0)
	if global_position.distance_to(sync_pos) > 4.0:
		global_position = sync_pos
	else:
		global_position = global_position.lerp(sync_pos, k)
	rotation.y = lerp_angle(rotation.y, sync_yaw, k)
	head.rotation.x = lerp(head.rotation.x, sync_pitch, k)


func _local_process(delta: float) -> void:
	fire_cd -= delta
	if reload_left > 0.0:
		reload_left -= delta
		if reload_left <= 0.0:
			ammo = MAG_SIZE
			_hud_ammo()
	gun.position = gun.position.lerp(GUN_REST, clamp(delta * 12.0, 0.0, 1.0))

	if not alive:
		velocity = Vector3.ZERO
		_publish()
		return

	var input_dir := Vector2.ZERO
	var want_jump := false
	var sprint := false
	var want_fire := false
	if is_bot:
		input_dir = _bot_think(delta)
		want_fire = bot_fire
		want_jump = randf() < 0.006
	elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Input.is_physical_key_pressed(KEY_W): input_dir.y -= 1
		if Input.is_physical_key_pressed(KEY_S): input_dir.y += 1
		if Input.is_physical_key_pressed(KEY_A): input_dir.x -= 1
		if Input.is_physical_key_pressed(KEY_D): input_dir.x += 1
		want_jump = Input.is_physical_key_pressed(KEY_SPACE)
		sprint = Input.is_physical_key_pressed(KEY_SHIFT)
		want_fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

	var dir := transform.basis * Vector3(input_dir.x, 0, input_dir.y)
	dir.y = 0
	if dir.length() > 0.01:
		dir = dir.normalized()
	var speed := SPRINT_SPEED if sprint else WALK_SPEED
	var accel := 12.0 if is_on_floor() else 3.0
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * speed * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * speed * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif want_jump:
		velocity.y = JUMP_VELOCITY
	move_and_slide()

	if want_fire:
		_try_fire()

	if global_position.y < -25.0 and not fell_pending:
		fell_pending = true
		srv_fell.rpc_id(1)

	_publish()


func _publish() -> void:
	sync_pos = global_position
	sync_yaw = rotation.y
	sync_pitch = pitch


# ---------------------------------------------------------------- стрельба (владелец)

func _try_fire() -> void:
	if fire_cd > 0.0 or reload_left > 0.0 or not alive:
		return
	if ammo <= 0:
		_start_reload()
		return
	ammo -= 1
	fire_cd = FIRE_DELAY
	_hud_ammo()

	var origin := camera.global_position
	var dir := -camera.global_transform.basis.z
	var horiz := Vector2(velocity.x, velocity.z).length()
	var spread := 0.004
	if horiz > 7.0:
		spread += 0.012
	if not is_on_floor():
		spread += 0.03
	if is_bot:
		spread += 0.035
	dir = (dir + Vector3(randf_range(-spread, spread), randf_range(-spread, spread), randf_range(-spread, spread))).normalized()

	# мгновенный трассер у стрелка, сервер потом подтвердит попадание
	var end := origin + dir * 200.0
	var q := PhysicsRayQueryParameters3D.create(origin, end, 1 | 2, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		end = hit["position"]
	_tracer(muzzle.global_position, end)

	# отдача
	if not is_bot:
		pitch = clamp(pitch + 0.012, -1.45, 1.45)
		head.rotation.x = pitch
		rotate_y(randf_range(-0.004, 0.004))
	gun.position.z += 0.06

	srv_shoot.rpc_id(1, origin, dir)
	if ammo == 0:
		_start_reload()


func _start_reload() -> void:
	if reload_left > 0.0 or ammo == MAG_SIZE or not alive:
		return
	reload_left = RELOAD_TIME
	_hud_ammo()


func _hud_ammo() -> void:
	if main.hud and is_multiplayer_authority():
		main.hud.set_ammo(ammo, MAG_SIZE, reload_left > 0.0)


func _tracer(from: Vector3, to: Vector3) -> void:
	if main.is_dedicated or main.world == null:
		return
	var length := from.distance_to(to)
	if length < 0.2:
		return
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.02, 0.02, length)
	m.mesh = bm
	m.material_override = _fx_mat(Color(1.0, 0.85, 0.35))
	main.world.add_child(m)
	var d := (to - from).normalized()
	var up := Vector3.UP if absf(d.y) < 0.98 else Vector3.RIGHT
	m.global_transform = Transform3D(Basis.looking_at(d, up), (from + to) * 0.5)
	get_tree().create_timer(0.05).timeout.connect(m.queue_free)

	var spark := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.12, 0.12, 0.12)
	spark.mesh = sm
	spark.material_override = _fx_mat(Color(1.0, 0.95, 0.7))
	main.world.add_child(spark)
	spark.global_position = to
	get_tree().create_timer(0.12).timeout.connect(spark.queue_free)

	var flash := MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.07
	fm.height = 0.14
	flash.mesh = fm
	flash.material_override = _fx_mat(Color(1.0, 0.7, 0.2))
	muzzle.add_child(flash)
	get_tree().create_timer(0.04).timeout.connect(flash.queue_free)


static func _fx_mat(c: Color) -> StandardMaterial3D:
	var key := "fx" + c.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	_mat_cache[key] = m
	return m


# ---------------------------------------------------------------- бот (для тестов: --bot)

func _bot_think(delta: float) -> Vector2:
	bot_fire = false
	var target: Node3D = null
	var best := 1e9
	for p in get_parent().get_children():
		if p == self or not p.alive:
			continue
		var d := global_position.distance_to(p.global_position)
		if d < best:
			best = d
			target = p
	if target:
		var to := (target.global_position + Vector3(0, 1.2, 0)) - (global_position + Vector3(0, HEAD_HEIGHT, 0))
		var yaw := atan2(-to.x, -to.z)
		rotation.y = lerp_angle(rotation.y, yaw, clamp(delta * 4.0, 0.0, 1.0))
		pitch = atan2(to.y, Vector2(to.x, to.z).length())
		head.rotation.x = pitch
		bot_fire = absf(angle_difference(rotation.y, yaw)) < 0.12 and best < 45.0
	bot_timer -= delta
	if bot_timer <= 0.0:
		bot_timer = randf_range(0.6, 1.6)
		bot_move = Vector2(randf_range(-1, 1), randf_range(-1, 0.4))
	return bot_move


# ---------------------------------------------------------------- сервер

@rpc("any_peer", "call_local", "reliable")
func srv_shoot(origin: Vector3, dir: Vector3) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != peer_id:
		return
	srv_shots.append([origin, dir])


@rpc("any_peer", "call_local", "reliable")
func srv_fell() -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != peer_id or not alive:
		return
	hp = 0
	cl_set_hp.rpc(0)
	_srv_kill(0, false)


func _server_process(delta: float) -> void:
	srv_invuln -= delta
	srv_shot_credit = minf(srv_shot_credit + delta / FIRE_DELAY, 3.0)
	if srv_shots.is_empty():
		return
	var shots := srv_shots
	srv_shots = []
	for s in shots:
		_srv_handle_shot(s[0], s[1])


func _srv_handle_shot(origin: Vector3, dir: Vector3) -> void:
	if not alive or srv_shot_credit < 1.0:
		return
	srv_shot_credit -= 1.0
	dir = dir.normalized()
	var head_pos := global_position + Vector3(0, HEAD_HEIGHT, 0)
	if origin.distance_to(head_pos) > 3.0:
		origin = head_pos
	var end := origin + dir * 200.0
	var q := PhysicsRayQueryParameters3D.create(origin, end, 1 | 2, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		end = hit["position"]
		var target = hit["collider"]
		if target != self and target.has_method("srv_take_damage"):
			var headshot: bool = (end.y - target.global_position.y) > HEAD_HEIGHT - 0.2
			if target.srv_take_damage(HEAD_DAMAGE if headshot else BODY_DAMAGE, peer_id, headshot):
				cl_hitmarker.rpc_id(peer_id, headshot)
	cl_fx_shot.rpc(end)


func srv_take_damage(amount: int, attacker: int, headshot: bool) -> bool:
	if not alive or srv_invuln > 0.0:
		return false
	hp = max(hp - amount, 0)
	cl_set_hp.rpc(hp)
	if hp <= 0:
		_srv_kill(attacker, headshot)
	return true


func _srv_kill(attacker: int, headshot: bool) -> void:
	alive = false
	cl_die.rpc(attacker)
	main.server_on_kill(attacker, peer_id, headshot)
	get_tree().create_timer(RESPAWN_DELAY).timeout.connect(_srv_respawn)


func _srv_respawn() -> void:
	if not is_inside_tree():
		return
	hp = MAX_HP
	alive = true
	srv_invuln = 1.5
	cl_respawn.rpc(main.random_spawn())


# ---------------------------------------------------------------- клиенты (вызывает сервер)

@rpc("any_peer", "call_local", "reliable")
func cl_set_hp(value: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	var old := hp
	hp = value
	if is_multiplayer_authority() and main.hud:
		main.hud.set_hp(hp, hp < old)


@rpc("any_peer", "call_local", "reliable")
func cl_die(attacker: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	alive = false
	visible = false
	collision_layer = 0
	if is_multiplayer_authority():
		velocity = Vector3.ZERO
		if main.hud:
			main.hud.show_death(main.get_player_name(attacker) if attacker != peer_id else "", RESPAWN_DELAY)


@rpc("any_peer", "call_local", "reliable")
func cl_respawn(pos: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	alive = true
	hp = MAX_HP
	visible = true
	collision_layer = 2
	fell_pending = false
	global_position = pos
	sync_pos = pos
	if is_multiplayer_authority():
		velocity = Vector3.ZERO
		ammo = MAG_SIZE
		reload_left = 0.0
		_publish()
		_hud_ammo()
		if main.hud:
			main.hud.hide_death()
			main.hud.set_hp(hp, false)


@rpc("any_peer", "call_local", "unreliable")
func cl_fx_shot(end: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1 or is_multiplayer_authority():
		return
	_tracer(muzzle.global_position, end)


@rpc("any_peer", "call_local", "reliable")
func cl_hitmarker(headshot: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	if main.hud:
		main.hud.hitmarker(headshot)

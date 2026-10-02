extends CharacterBody3D
## Игрок. Движением управляет владелец (клиент), попадания и урон считает сервер.

const Sfx := preload("res://sfx.gd")
const Fx := preload("res://fx.gd")

# движение
const WALK_SPEED := 6.0
const SPRINT_SPEED := 9.0
const ADS_SPEED := 3.6
const JUMP_VELOCITY := 5.6
const GRAVITY := 16.0
const MOUSE_SENS := 0.0022
# здоровье
const MAX_HP := 100
const RESPAWN_DELAY := 3.0
const HEAD_HEIGHT := 1.6
const FALL_SAFE_SPEED := 9.0     # приземление медленнее этого — без урона (~2.5 м высоты)
const FALL_DAMAGE_MULT := 7.0    # урон за каждый м/с сверх безопасной скорости
# оружие
const FIRE_DELAY := 0.1          # 600 выстрелов в минуту
const MAG_SIZE := 30
const RELOAD_TIME := 1.9
const BODY_DAMAGE := 22
const HEAD_DAMAGE := 60
const FALLOFF_START := 25.0      # с этой дистанции урон начинает падать
const FALLOFF_END := 70.0        # здесь урон — 60%
# вид от первого лица
const HIP_POS := Vector3(0.15, -0.17, -0.5)
const ADS_POS := Vector3(0.0, -0.103, -0.4)
const HIP_FOV := 80.0
const ADS_FOV := 52.0
const MAG_POS := Vector3(0, -0.13, -0.08)

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
var eject_port: Node3D
var mag_node: Node3D
var red_dot: Node3D
var body_visuals: Node3D
var name_label: Label3D
var sounds := {}

# только у владельца
var ammo := MAG_SIZE
var reload_left := 0.0
var reload_stage := 0
var fire_cd := 0.0
var fell_pending := false
var ads := false
var ads_t := 0.0
var bob_phase := 0.0
var sway := Vector2.ZERO
var mouse_delta := Vector2.ZERO
var kick := 0.0
var view_punch := 0.0
var bloom := 0.0
var land_dip := 0.0
var step_dist := 0.0
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
		position.y += main.drop_height
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


# ---------------------------------------------------------------- модель

func _build_visuals() -> void:
	var color := Color.from_hsv(fmod(peer_id * 0.618034, 1.0), 0.6, 0.95)
	var metal := _mat(Color(0.13, 0.14, 0.15), 0.7, 0.4)
	var polymer := _mat(Color(0.2, 0.21, 0.2), 0.0, 0.85)
	var glove := _mat(Color(0.1, 0.1, 0.1), 0.0, 0.9)
	var sleeve := _mat(Color(0.16, 0.17, 0.15), 0.0, 0.95)
	var accent := _mat(color, 0.2, 0.5)

	# тело (видят другие игроки)
	body_visuals = Node3D.new()
	add_child(body_visuals)
	_part(body_visuals, _capsule(0.4, 1.8), Vector3(0, 0.9, 0), _mat(color, 0.0, 0.6))
	_part(body_visuals, _box(0.82, 0.22, 0.5), Vector3(0, 1.25, 0), _mat(color.darkened(0.35), 0.0, 0.8))

	head = Node3D.new()
	head.position.y = HEAD_HEIGHT
	add_child(head)
	var visor := _part(head, _box(0.5, 0.14, 0.14), Vector3(0, 0.02, -0.34), _mat(Color(0.08, 0.09, 0.12), 0.5, 0.2))

	camera = Camera3D.new()
	camera.fov = HIP_FOV
	camera.near = 0.03
	head.add_child(camera)

	# ---- автомат (координаты от центра ствольной коробки, ствол смотрит в -Z)
	gun = Node3D.new()
	gun.position = HIP_POS
	head.add_child(gun)
	_part(gun, _box(0.06, 0.11, 0.34), Vector3(0, 0, 0), metal)                      # ствольная коробка
	_part(gun, _box(0.036, 0.02, 0.32), Vector3(0, 0.065, -0.02), metal)            # планка
	for i in 6:                                                                      # насечки планки
		_part(gun, _box(0.038, 0.005, 0.01), Vector3(0, 0.077, 0.11 - i * 0.045), metal)
	_part(gun, _box(0.07, 0.085, 0.26), Vector3(0, -0.005, -0.29), polymer)         # цевьё
	_part(gun, _box(0.072, 0.02, 0.22), Vector3(0, 0.012, -0.29), accent)           # цветная полоса
	for i in 4:                                                                      # вентиляция цевья
		_part(gun, _box(0.074, 0.012, 0.03), Vector3(0, -0.025, -0.2 - i * 0.055), metal)
	_part(gun, _cylinder(0.014, 0.24), Vector3(0, 0.012, -0.52), metal, Vector3(PI / 2, 0, 0))  # ствол
	_part(gun, _cylinder(0.022, 0.08), Vector3(0, 0.012, -0.66), metal, Vector3(PI / 2, 0, 0))  # ДТК
	_part(gun, _box(0.008, 0.03, 0.05), Vector3(0, 0.04, -0.62), metal)             # мушка
	_part(gun, _box(0.004, 0.03, 0.07), Vector3(0.031, 0.022, -0.01), _mat(Color(0.03, 0.03, 0.03)))  # окно экстракции
	_part(gun, _box(0.03, 0.018, 0.035), Vector3(-0.04, 0.03, 0.06), metal)         # рукоятка затвора
	_part(gun, _box(0.045, 0.11, 0.055), Vector3(0, -0.1, 0.1), polymer, Vector3(-0.35, 0, 0))   # пистолетная рукоять
	_part(gun, _box(0.012, 0.035, 0.07), Vector3(0, -0.07, 0.035), metal)           # спуск. скоба
	var stock := _part(gun, _box(0.05, 0.09, 0.2), Vector3(0, -0.02, 0.27), polymer)             # приклад
	var butt := _part(gun, _box(0.056, 0.13, 0.03), Vector3(0, -0.035, 0.38), _mat(Color(0.08, 0.08, 0.08), 0.0, 1.0))  # затыльник
	mag_node = Node3D.new()
	mag_node.position = MAG_POS
	mag_node.rotation.x = 0.22
	gun.add_child(mag_node)
	_part(mag_node, _box(0.042, 0.18, 0.075), Vector3(0, 0, 0), polymer)            # магазин
	_part(mag_node, _box(0.046, 0.02, 0.08), Vector3(0, -0.09, 0), metal)
	# коллиматор: кольцо на стойке + красная точка
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.019
	tm.outer_radius = 0.026
	tm.rings = 24
	ring.mesh = tm
	ring.material_override = metal
	ring.rotation.x = PI / 2
	ring.position = Vector3(0, 0.103, 0.02)
	gun.add_child(ring)
	_part(gun, _box(0.03, 0.014, 0.04), Vector3(0, 0.08, 0.02), metal)
	red_dot = _part(gun, _sphere(0.0022), Vector3(0, 0.103, 0.02), Fx.unshaded(Color(1, 0.1, 0.1)))
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, 0.012, -0.71)
	gun.add_child(muzzle)
	eject_port = Node3D.new()
	eject_port.position = Vector3(0.04, 0.025, -0.01)
	gun.add_child(eject_port)
	# руки
	_part(gun, _box(0.075, 0.06, 0.1), Vector3(-0.01, -0.06, -0.32), glove)                         # левая кисть
	var l_arm := _part(gun, _box(0.095, 0.095, 0.34), Vector3(-0.1, -0.13, -0.15), sleeve, Vector3(0.25, 0.45, 0))  # левое предплечье
	_part(l_arm, _box(0.1, 0.1, 0.03), Vector3(0, 0, -0.15), accent)                                 # манжета цвета игрока
	_part(gun, _box(0.07, 0.07, 0.09), Vector3(0.0, -0.09, 0.1), glove, Vector3(-0.35, 0, 0))        # правая кисть
	var r_arm := _part(gun, _box(0.085, 0.085, 0.36), Vector3(0.06, -0.15, 0.3), sleeve, Vector3(0.45, -0.25, 0)) # правое предплечье

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
		# эти части у камеры только загораживают обзор
		stock.visible = false
		butt.visible = false
		r_arm.visible = false
		# своё оружие не отбрасывает тень на мир и не «залазит» в стены визуально
		for n in gun.find_children("*", "GeometryInstance3D", true, false):
			n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _box(x: float, y: float, z: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(x, y, z)
	return m


static func _cylinder(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 12
	return m


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	return m


static func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2
	m.radial_segments = 8
	m.rings = 4
	return m


static func _mat(c: Color, metallic := 0.0, roughness := 0.6) -> StandardMaterial3D:
	var key := "%s/%s/%s" % [c.to_html(), metallic, roughness]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = roughness
	_mat_cache[key] = m
	return m


# ---------------------------------------------------------------- звук

func _snd(sound_name: String, volume_db := 0.0, pitch_var := 0.04) -> void:
	if main.is_dedicated:
		return
	var p = sounds.get(sound_name)
	if p == null:
		if is_multiplayer_authority():
			p = AudioStreamPlayer.new()
		else:
			p = AudioStreamPlayer3D.new()
			p.unit_size = 8.0
			p.max_distance = 140.0
		p.stream = Sfx.get_sound(sound_name)
		p.max_polyphony = 6
		head.add_child(p)
		sounds[sound_name] = p
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


# ---------------------------------------------------------------- ввод

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or is_bot:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := MOUSE_SENS * lerpf(1.0, 0.6, ads_t)
		rotate_y(-event.relative.x * sens)
		pitch = clamp(pitch - event.relative.y * sens, -1.45, 1.45)
		head.rotation.x = pitch
		mouse_delta += event.relative
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
	bloom = move_toward(bloom, 0.0, delta * 0.06)
	if reload_left > 0.0:
		reload_left -= delta
		_reload_sounds()
		if reload_left <= 0.0:
			ammo = MAG_SIZE
			_hud_ammo()

	if not alive:
		velocity = Vector3.ZERO
		ads = false
		_publish()
		_animate_viewmodel(delta)
		return

	var input_dir := Vector2.ZERO
	var want_jump := false
	var sprint := false
	var want_fire := false
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if is_bot:
		input_dir = _bot_think(delta)
		want_fire = bot_fire
		want_jump = randf() < 0.006
	elif captured:
		if Input.is_physical_key_pressed(KEY_W): input_dir.y -= 1
		if Input.is_physical_key_pressed(KEY_S): input_dir.y += 1
		if Input.is_physical_key_pressed(KEY_A): input_dir.x -= 1
		if Input.is_physical_key_pressed(KEY_D): input_dir.x += 1
		want_jump = Input.is_physical_key_pressed(KEY_SPACE)
		sprint = Input.is_physical_key_pressed(KEY_SHIFT)
		want_fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	ads = (is_bot and main.debug_ads) or not is_bot and captured and reload_left <= 0.0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	sprint = sprint and not ads and input_dir.y < 0 and not want_fire

	var dir := transform.basis * Vector3(input_dir.x, 0, input_dir.y)
	dir.y = 0
	if dir.length() > 0.01:
		dir = dir.normalized()
	var speed := ADS_SPEED if ads else (SPRINT_SPEED if sprint else WALK_SPEED)
	var accel := 12.0 if is_on_floor() else 3.0
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * speed * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * speed * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif want_jump:
		velocity.y = JUMP_VELOCITY

	var was_airborne := not is_on_floor()
	var fall_speed := -velocity.y
	move_and_slide()
	if was_airborne and is_on_floor():
		_on_landed(fall_speed)

	# шаги
	var horiz := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and horiz > 1.0 and not ads:
		step_dist += horiz * delta
		if step_dist > (2.7 if sprint else 2.1):
			step_dist = 0.0
			_snd("step", -16.0 if not sprint else -12.0, 0.15)

	if want_fire:
		_try_fire()

	if global_position.y < -25.0 and not fell_pending:
		fell_pending = true
		srv_fell.rpc_id(1)

	_publish()
	_animate_viewmodel(delta)


func _on_landed(speed: float) -> void:
	if speed > 4.0:
		land_dip = clampf(speed * 0.007, 0.0, 0.12)
		_snd("land", lerpf(-14.0, 0.0, clampf((speed - 4.0) / 10.0, 0.0, 1.0)), 0.08)
	if speed > FALL_SAFE_SPEED and alive:
		srv_fall_damage.rpc_id(1, speed)


func _publish() -> void:
	sync_pos = global_position
	sync_yaw = rotation.y
	sync_pitch = pitch


func _animate_viewmodel(delta: float) -> void:
	ads_t = move_toward(ads_t, 1.0 if ads else 0.0, delta * 7.0)
	var e := smoothstep(0.0, 1.0, ads_t)
	camera.fov = lerpf(HIP_FOV, ADS_FOV, e)
	red_dot.visible = e > 0.5

	var horiz := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and horiz > 0.5:
		bob_phase += delta * horiz * 1.5
	var bob_amt := clampf(horiz / SPRINT_SPEED, 0.0, 1.0) * (1.0 - e * 0.85) * (1.0 if is_on_floor() else 0.3)
	var bob := Vector3(sin(bob_phase) * 0.016, -absf(cos(bob_phase)) * 0.014, 0.0) * bob_amt

	sway = sway.lerp(mouse_delta * 0.0008 * (1.0 - e * 0.7), clampf(delta * 10.0, 0.0, 1.0)).limit_length(0.06)
	mouse_delta = Vector2.ZERO
	kick = lerpf(kick, 0.0, clampf(delta * 14.0, 0.0, 1.0))
	view_punch = lerpf(view_punch, 0.0, clampf(delta * 9.0, 0.0, 1.0))
	land_dip = lerpf(land_dip, 0.0, clampf(delta * 7.0, 0.0, 1.0))

	var pos := HIP_POS.lerp(ADS_POS, e) + bob
	pos.z += kick * lerpf(0.05, 0.03, e)
	pos.y -= land_dip * 0.4
	pos.x -= sway.x * 0.3
	pos.y += sway.y * 0.3
	var rot := Vector3(kick * lerpf(0.09, 0.03, e) + sway.y, sway.x, sway.x * 0.6 + bob.x * 2.0)

	# анимация перезарядки: наклон оружия, магазин выходит и возвращается
	var mag_off := 0.0
	if reload_left > 0.0:
		var p := clampf(1.0 - reload_left / RELOAD_TIME, 0.0, 1.0)
		var tilt := sin(p * PI)
		rot.x -= tilt * 0.35
		rot.z += tilt * 0.55
		pos.y -= tilt * 0.05
		pos.x -= tilt * 0.04
		if p > 0.15 and p < 0.75:
			var q := (p - 0.15) / 0.6
			mag_off = sin(q * PI) * 0.35
	mag_node.position = MAG_POS + Vector3(0, -mag_off, mag_off * 0.25)
	mag_node.visible = mag_off < 0.3

	gun.position = pos
	gun.rotation = rot
	camera.rotation.x = view_punch
	camera.position.y = -land_dip

	if main.hud and is_multiplayer_authority():
		main.hud.set_crosshair(_spread_px(), e > 0.6 or not alive)


# ---------------------------------------------------------------- стрельба (владелец)

func _current_spread() -> float:
	var horiz := Vector2(velocity.x, velocity.z).length()
	var s := 0.0025 + horiz / SPRINT_SPEED * 0.02 + bloom
	if not is_on_floor():
		s += 0.045
	s *= lerpf(1.0, 0.3, smoothstep(0.0, 1.0, ads_t))
	if is_bot:
		s += 0.03
	return s


func _spread_px() -> float:
	var h := float(get_viewport().get_visible_rect().size.y)
	return tan(_current_spread()) * h / (2.0 * tan(deg_to_rad(camera.fov) * 0.5))


func _try_fire() -> void:
	if fire_cd > 0.0 or reload_left > 0.0 or not alive:
		return
	if ammo <= 0:
		_snd("dry", -4.0)
		fire_cd = 0.3
		_start_reload()
		return
	ammo -= 1
	fire_cd = FIRE_DELAY
	_hud_ammo()

	var origin := camera.global_position
	var b := camera.global_transform.basis
	var spread := _current_spread()
	var ang := randf() * TAU
	var r := sqrt(randf()) * spread
	var dir := (-b.z + b.x * cos(ang) * r + b.y * sin(ang) * r).normalized()
	bloom = minf(bloom + 0.0045, 0.03)

	# мгновенный эффект у стрелка, урон подтвердит сервер
	var end := origin + dir * 200.0
	var normal := Vector3.ZERO
	var hit_player := false
	var q := PhysicsRayQueryParameters3D.create(origin, end, 1 | 2, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		end = hit["position"]
		normal = hit["normal"]
		hit_player = hit["collider"].has_method("srv_take_damage")
	_shot_fx(end, normal, hit_player, not hit.is_empty())
	if not main.is_dedicated:
		Fx.shell(main.world, eject_port.global_position, eject_port.global_transform.basis)

	# отдача: ствол уводит вверх, камеру встряхивает
	var e := smoothstep(0.0, 1.0, ads_t)
	if not is_bot:
		pitch = clamp(pitch + lerpf(0.009, 0.006, e), -1.45, 1.45)
		head.rotation.x = pitch
		rotate_y(randf_range(-0.004, 0.004))
		view_punch += lerpf(0.014, 0.006, e)
	kick = minf(kick + 1.0, 1.8)

	srv_shoot.rpc_id(1, origin, dir)
	if ammo == 0:
		_start_reload()


func _shot_fx(end: Vector3, normal: Vector3, hit_player: bool, did_hit: bool) -> void:
	if main.is_dedicated or main.world == null:
		return
	_snd("shot", 0.0 if is_multiplayer_authority() else 2.0, 0.05)
	Fx.muzzle_flash(muzzle)
	Fx.tracer(main.world, muzzle.global_position, end)
	if did_hit:
		Fx.impact(main.world, end, normal, hit_player)


func _start_reload() -> void:
	if reload_left > 0.0 or ammo == MAG_SIZE or not alive:
		return
	reload_left = RELOAD_TIME
	reload_stage = 0
	_hud_ammo()


func _reload_sounds() -> void:
	var p := 1.0 - reload_left / RELOAD_TIME
	if reload_stage == 0 and p > 0.18:
		reload_stage = 1
		_snd("mag_out", -4.0)
	elif reload_stage == 1 and p > 0.62:
		reload_stage = 2
		_snd("mag_in", -2.0)
	elif reload_stage == 2 and p > 0.82:
		reload_stage = 3
		_snd("bolt", -2.0)


func _hud_ammo() -> void:
	if main.hud and is_multiplayer_authority():
		main.hud.set_ammo(ammo, MAG_SIZE, reload_left > 0.0)


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
	cl_set_hp.rpc(0, Vector3.ZERO, false)
	_srv_kill(0, false, "void")


@rpc("any_peer", "call_local", "reliable")
func srv_fall_damage(speed: float) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != peer_id or not alive:
		return
	speed = clampf(speed, 0.0, 40.0)
	var dmg := int((speed - FALL_SAFE_SPEED) * FALL_DAMAGE_MULT)
	if dmg > 0:
		if main.is_dedicated:
			print("[server] %s: урон от падения %d (скорость %.1f м/с)" % [player_name, dmg, speed])
		srv_take_damage(dmg, 0, false, Vector3.ZERO, "fall")


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
	var normal := Vector3.ZERO
	var hit_player := false
	var q := PhysicsRayQueryParameters3D.create(origin, end, 1 | 2, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		end = hit["position"]
		normal = hit["normal"]
		var target = hit["collider"]
		if target != self and target.has_method("srv_take_damage"):
			hit_player = true
			var headshot: bool = (end.y - target.global_position.y) > HEAD_HEIGHT - 0.2
			var dist := origin.distance_to(end)
			var falloff := lerpf(1.0, 0.6, clampf((dist - FALLOFF_START) / (FALLOFF_END - FALLOFF_START), 0.0, 1.0))
			var dmg := int(round((HEAD_DAMAGE if headshot else BODY_DAMAGE) * falloff))
			if target.srv_take_damage(dmg, peer_id, headshot, origin, ""):
				cl_hitmarker.rpc_id(peer_id, headshot, not target.alive)
	cl_fx_shot.rpc(end, normal, hit_player, not hit.is_empty())


func srv_take_damage(amount: int, attacker: int, headshot: bool, from: Vector3, cause: String) -> bool:
	if not alive or srv_invuln > 0.0:
		return false
	hp = max(hp - amount, 0)
	cl_set_hp.rpc(hp, from, attacker != 0)
	if hp <= 0:
		_srv_kill(attacker, headshot, cause)
	return true


func _srv_kill(attacker: int, headshot: bool, cause: String) -> void:
	alive = false
	cl_die.rpc(attacker)
	main.server_on_kill(attacker, peer_id, headshot, cause)
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
func cl_set_hp(value: int, from: Vector3, has_from: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	var old := hp
	hp = value
	if is_multiplayer_authority():
		if hp < old:
			_snd("hurt", -3.0, 0.1)
		if main.hud:
			main.hud.set_hp(hp, hp < old)
			if has_from and hp < old:
				var to := from - global_position
				var local := to.rotated(Vector3.UP, -rotation.y)
				main.hud.damage_from(atan2(local.x, -local.z))


@rpc("any_peer", "call_local", "reliable")
func cl_die(attacker: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	alive = false
	visible = false
	collision_layer = 0
	if is_multiplayer_authority():
		velocity = Vector3.ZERO
		reload_left = 0.0
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
		bloom = 0.0
		_publish()
		_hud_ammo()
		if main.hud:
			main.hud.hide_death()
			main.hud.set_hp(hp, false)


@rpc("any_peer", "call_local", "unreliable")
func cl_fx_shot(end: Vector3, normal: Vector3, hit_player: bool, did_hit: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1 or is_multiplayer_authority():
		return
	_shot_fx(end, normal, hit_player, did_hit)


@rpc("any_peer", "call_local", "reliable")
func cl_hitmarker(headshot: bool, killed: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	if killed:
		_snd("kill", -2.0, 0.0)
	_snd("headshot" if headshot else "hit", -3.0, 0.03)
	if main.hud:
		main.hud.hitmarker(headshot or killed)

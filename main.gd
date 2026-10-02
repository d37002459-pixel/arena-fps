extends Node
## Главный узел: меню, запуск сервера/клиента, счёт, спавн игроков.

const PORT := 7777
const MAX_PLAYERS := 16
const PlayerScript := preload("res://player.gd")
const HudScript := preload("res://hud.gd")
const MapBuilder := preload("res://map.gd")
const SETTINGS_PATH := "user://settings.cfg"

static var last_message := ""

var is_dedicated := false
var bot_mode := false
var player_name := "Игрок"
var server_ip := "127.0.0.1"
var screenshot_path := ""
var is_web := OS.has_feature("web")

var menu: Control
var name_edit: LineEdit
var ip_edit: LineEdit
var status_label: Label

var hud: CanvasLayer
var world: Node3D
var players_root: Node3D
var spawner: MultiplayerSpawner
var spawn_points: Array = []
var scores := {}  # peer_id -> {"name", "kills", "deaths"}


func _ready() -> void:
	randomize()
	_load_settings()
	var join_ip := ""
	var host_play := false
	for a in OS.get_cmdline_user_args():
		if a == "--server":
			is_dedicated = true
		elif a == "--host":
			host_play = true
		elif a == "--bot":
			bot_mode = true
		elif a.begins_with("--join="):
			join_ip = a.substr(7)
		elif a.begins_with("--name="):
			player_name = a.substr(7)
		elif a.begins_with("--screenshot="):
			screenshot_path = a.substr(13)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	if is_dedicated:
		start_host(false)
	elif host_play:
		start_host(true)
	elif join_ip != "":
		server_ip = join_ip
		join_game(join_ip)
	elif DisplayServer.get_name() == "headless":
		is_dedicated = true
		start_host(false)
	else:
		_build_menu()

	if screenshot_path != "":
		get_tree().create_timer(3.0).timeout.connect(_take_screenshot)


# ---------------------------------------------------------------- меню

func _build_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu = Control.new()
	menu.name = "Menu"
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(menu)

	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(400, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var title := Label.new()
	title.text = "ARENA FPS"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(1.0, 0.75, 0.25))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	box.add_child(_caption("Ник"))
	name_edit = LineEdit.new()
	name_edit.text = player_name
	name_edit.max_length = 16
	box.add_child(name_edit)

	ip_edit = LineEdit.new()
	ip_edit.text = server_ip
	if not is_web:
		box.add_child(_caption("Адрес сервера (IP или сайт)"))
		box.add_child(ip_edit)

	var host_btn := Button.new()
	host_btn.text = "Создать игру (хост)"
	host_btn.pressed.connect(_on_host_pressed)
	var join_btn := Button.new()
	join_btn.text = "Играть" if is_web else "Подключиться"
	join_btn.pressed.connect(_on_join_pressed)
	var quit_btn := Button.new()
	quit_btn.text = "Выход"
	quit_btn.pressed.connect(func(): get_tree().quit())
	var buttons := [join_btn] if is_web else [host_btn, join_btn, quit_btn]
	for b in buttons:
		b.custom_minimum_size.y = 44
		b.add_theme_font_size_override("font_size", 20)
		box.add_child(b)

	status_label = Label.new()
	status_label.text = last_message
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color(1, 0.45, 0.4))
	box.add_child(status_label)

	var help := Label.new()
	help.text = "WASD — ходьба, Shift — бег, Пробел — прыжок\nЛКМ — огонь, R — перезарядка, Tab — счёт, Esc — пауза"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_color_override("font_color", Color(0.6, 0.62, 0.68))
	help.add_theme_font_size_override("font_size", 14)
	box.add_child(help)


func _caption(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
	return l


func _on_host_pressed() -> void:
	player_name = name_edit.text.strip_edges()
	_save_settings()
	start_host(true)


func _on_join_pressed() -> void:
	player_name = name_edit.text.strip_edges()
	if not is_web:
		server_ip = ip_edit.text.strip_edges()
	_save_settings()
	join_game(server_ip)


func _set_status(t: String) -> void:
	print(t)
	if status_label:
		status_label.text = t


# ---------------------------------------------------------------- сеть

func start_host(play: bool) -> void:
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(PORT)
	if err != OK:
		_set_status("Не удалось открыть порт %d — он уже занят?" % PORT)
		if is_dedicated:
			get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	_build_world()
	print("[server] запущен на порту %d" % PORT)
	if play:
		_register_player(1, player_name)


func join_game(addr: String) -> void:
	var url := server_url(addr)
	if url == "":
		_set_status("Введи адрес сервера")
		return
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url)
	if err != OK:
		_set_status("Не удалось создать подключение к %s" % url)
		return
	multiplayer.multiplayer_peer = peer
	_build_world()
	if hud:
		hud.show_center("Подключение...")


## Превращает то, что ввёл игрок, в адрес WebSocket.
## В браузере — всегда сервер того же сайта: wss://сайт/ws
## 192.168.1.5 -> ws://192.168.1.5:7777, my-game.onrender.com -> wss://my-game.onrender.com/ws
func server_url(addr: String) -> String:
	if is_web:
		var proto: String = JavaScriptBridge.eval("location.protocol", true)
		var host: String = JavaScriptBridge.eval("location.host", true)
		return ("wss://" if proto == "https:" else "ws://") + host + "/ws"
	addr = addr.strip_edges()
	if addr == "":
		return ""
	if addr.begins_with("ws://") or addr.begins_with("wss://"):
		return addr
	if addr.begins_with("https://"):
		addr = addr.substr(8)
	elif addr.begins_with("http://"):
		return "ws://" + addr.substr(7).trim_suffix("/") + "/ws"
	addr = addr.trim_suffix("/")
	var host_part := addr.split(":")[0]
	if host_part.is_valid_ip_address() or host_part == "localhost":
		return "ws://%s" % addr if ":" in addr else "ws://%s:%d" % [addr, PORT]
	return "wss://" + addr + "/ws"


func leave_game() -> void:
	_back_to_menu("")


func _build_world() -> void:
	if menu:
		menu.queue_free()
		menu = null
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	spawn_points = MapBuilder.build(world)

	players_root = Node3D.new()
	players_root.name = "Players"
	add_child(players_root)

	spawner = MultiplayerSpawner.new()
	spawner.name = "Spawner"
	spawner.spawn_function = _spawn_player
	spawner.spawn_path = NodePath("../Players")
	add_child(spawner)

	if not is_dedicated:
		hud = HudScript.new()
		hud.name = "HUD"
		add_child(hud)


func _spawn_player(data: Variant) -> Node:
	var p: CharacterBody3D = PlayerScript.new()
	p.name = str(data["id"])
	p.peer_id = int(data["id"])
	p.player_name = str(data["name"])
	p.position = data["pos"]
	return p


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		print("[server] подключился peer %d" % id)


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	var n := players_root.get_node_or_null(str(id))
	if n:
		n.queue_free()
	if scores.has(id):
		var nm: String = scores[id]["name"]
		scores.erase(id)
		_broadcast_scores()
		feed.rpc("%s вышел из игры" % nm)


func _on_connected_to_server() -> void:
	register.rpc_id(1, player_name)


func _on_connection_failed() -> void:
	_back_to_menu("Не удалось подключиться к серверу. Если сервер на Render спал — подожди минуту и попробуй ещё раз.")


func _on_server_disconnected() -> void:
	_back_to_menu("Соединение с сервером потеряно")


func _back_to_menu(msg: String) -> void:
	last_message = msg
	if DisplayServer.get_name() == "headless":
		print(msg)
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()


@rpc("any_peer", "call_remote", "reliable")
func register(pname: String) -> void:
	if not multiplayer.is_server():
		return
	_register_player(multiplayer.get_remote_sender_id(), pname)


func _register_player(id: int, pname: String) -> void:
	if players_root.has_node(str(id)):
		return
	pname = pname.strip_edges().left(16)
	if pname == "":
		pname = "Игрок%d" % (id % 1000)
	scores[id] = {"name": pname, "kills": 0, "deaths": 0}
	spawner.spawn({"id": id, "name": pname, "pos": random_spawn()})
	_broadcast_scores()
	feed.rpc("%s зашёл в игру" % pname)


# ---------------------------------------------------------------- счёт и события (сервер)

func server_on_kill(killer: int, victim: int, headshot: bool) -> void:
	if scores.has(victim):
		scores[victim]["deaths"] += 1
	var vname := get_player_name(victim)
	if killer != 0 and killer != victim and scores.has(killer):
		scores[killer]["kills"] += 1
		feed.rpc("%s  убил  %s%s" % [get_player_name(killer), vname, "  (в голову)" if headshot else ""])
	else:
		feed.rpc("%s упал с карты" % vname)
	_broadcast_scores()


func _broadcast_scores() -> void:
	set_scores.rpc(scores)


func get_player_name(id: int) -> String:
	if scores.has(id):
		return scores[id]["name"]
	return ""


func random_spawn() -> Vector3:
	var best: Vector3 = spawn_points[randi() % spawn_points.size()]
	var best_d := -1.0
	for sp in spawn_points:
		var d := 1000.0
		for p in players_root.get_children():
			if p.alive:
				d = min(d, sp.distance_to(p.global_position))
		d += randf() * 8.0
		if d > best_d:
			best_d = d
			best = sp
	return best


@rpc("authority", "call_local", "reliable")
func set_scores(s: Dictionary) -> void:
	scores = s
	if hud:
		hud.update_scores(s)


@rpc("authority", "call_local", "reliable")
func feed(text: String) -> void:
	if is_dedicated or DisplayServer.get_name() == "headless":
		print("[feed] ", text)
	if hud:
		hud.add_feed(text)


# ---------------------------------------------------------------- прочее

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		player_name = cfg.get_value("player", "name", player_name)
		server_ip = cfg.get_value("player", "ip", server_ip)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "ip", server_ip)
	cfg.save(SETTINGS_PATH)


func _take_screenshot() -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(screenshot_path)
	print("screenshot saved: ", screenshot_path)

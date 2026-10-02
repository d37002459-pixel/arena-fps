extends CanvasLayer
## Интерфейс: прицел, здоровье, патроны, килфид, таблица счёта, пауза.

var main: Node
var hp_label: Label
var ammo_label: Label
var crosshair: Control
var center_label: Label
var feed_box: VBoxContainer
var score_panel: PanelContainer
var score_grid: GridContainer
var damage_flash: ColorRect
var pause_panel: PanelContainer
var hint_label: Label

var in_game := false
var death_left := 0.0
var death_killer := ""
var hit_t := 0.0


func _ready() -> void:
	main = get_parent()
	layer = 10

	damage_flash = ColorRect.new()
	damage_flash.color = Color(0.9, 0.05, 0.05, 0.0)
	_full(damage_flash)
	add_child(damage_flash)

	# углы экрана
	var margin := MarginContainer.new()
	_full(margin)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var col := VBoxContainer.new()
	_ignore(col)
	margin.add_child(col)

	var top := HBoxContainer.new()
	_ignore(top)
	col.add_child(top)
	hint_label = _label("Esc — пауза   Tab — счёт   R — перезарядка", 15, Color(1, 1, 1, 0.7))
	hint_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(hint_label)
	var sp1 := Control.new()
	_ignore(sp1)
	sp1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp1)
	feed_box = VBoxContainer.new()
	_ignore(feed_box)
	feed_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	top.add_child(feed_box)

	var sp2 := Control.new()
	_ignore(sp2)
	sp2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sp2)

	var bottom := HBoxContainer.new()
	_ignore(bottom)
	col.add_child(bottom)
	hp_label = _label("100", 44, Color(0.55, 1.0, 0.6))
	bottom.add_child(hp_label)
	var sp3 := Control.new()
	_ignore(sp3)
	sp3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(sp3)
	ammo_label = _label("30 / 30", 44, Color(1, 0.9, 0.6))
	bottom.add_child(ammo_label)

	# прицел
	var cc := CenterContainer.new()
	_full(cc)
	add_child(cc)
	crosshair = Control.new()
	_ignore(crosshair)
	crosshair.custom_minimum_size = Vector2(32, 32)
	cc.add_child(crosshair)
	for r in [Rect2(15, 4, 2, 8), Rect2(15, 20, 2, 8), Rect2(4, 15, 8, 2), Rect2(20, 15, 8, 2), Rect2(15, 15, 2, 2)]:
		var cr := ColorRect.new()
		_ignore(cr)
		cr.color = Color(1, 1, 1, 0.9)
		cr.position = r.position
		cr.size = r.size
		crosshair.add_child(cr)
	crosshair.pivot_offset = Vector2(16, 16)

	# текст по центру (смерть / подключение)
	var cc2 := CenterContainer.new()
	_full(cc2)
	add_child(cc2)
	center_label = _label("", 34, Color(1, 1, 1))
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.add_theme_constant_override("outline_size", 8)
	center_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	center_label.custom_minimum_size = Vector2(0, 220)
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	cc2.add_child(center_label)

	# таблица счёта
	var cc3 := CenterContainer.new()
	_full(cc3)
	add_child(cc3)
	score_panel = PanelContainer.new()
	_ignore(score_panel)
	score_panel.add_theme_stylebox_override("panel", _panel_style())
	score_panel.visible = false
	cc3.add_child(score_panel)
	score_grid = GridContainer.new()
	_ignore(score_grid)
	score_grid.columns = 3
	score_grid.add_theme_constant_override("h_separation", 40)
	score_grid.add_theme_constant_override("v_separation", 6)
	score_panel.add_child(score_grid)

	# пауза
	var cc4 := CenterContainer.new()
	_full(cc4)
	add_child(cc4)
	pause_panel = PanelContainer.new()
	pause_panel.add_theme_stylebox_override("panel", _panel_style())
	pause_panel.visible = false
	cc4.add_child(pause_panel)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	pv.custom_minimum_size = Vector2(280, 0)
	pause_panel.add_child(pv)
	var pt := _label("Пауза", 30, Color(1, 1, 1))
	pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(pt)
	var resume := Button.new()
	resume.text = "Продолжить"
	resume.custom_minimum_size.y = 42
	resume.pressed.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	pv.add_child(resume)
	var leave := Button.new()
	leave.text = "Выйти в меню"
	leave.custom_minimum_size.y = 42
	leave.pressed.connect(func(): main.leave_game())
	pv.add_child(leave)

	get_tree().create_timer(12.0).timeout.connect(func(): hint_label.visible = false)


func _process(delta: float) -> void:
	score_panel.visible = in_game and Input.is_physical_key_pressed(KEY_TAB)
	pause_panel.visible = in_game and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not main.bot_mode and death_left <= 0.0
	damage_flash.color.a = move_toward(damage_flash.color.a, 0.0, delta * 1.2)
	if hit_t > 0.0:
		hit_t -= delta
		if hit_t <= 0.0:
			crosshair.modulate = Color(1, 1, 1)
			crosshair.scale = Vector2.ONE
	if death_left > 0.0:
		death_left -= delta
		var who := "Тебя убил: %s" % death_killer if death_killer != "" else "Ты погиб"
		center_label.text = "%s\nВозрождение через %d" % [who, ceili(maxf(death_left, 0.0))]


# ---------------------------------------------------------------- API

func set_in_game(v: bool) -> void:
	in_game = v


func set_hp(hp: int, damaged: bool) -> void:
	hp_label.text = str(hp)
	var c := Color(0.55, 1.0, 0.6)
	if hp <= 30:
		c = Color(1.0, 0.35, 0.3)
	elif hp <= 60:
		c = Color(1.0, 0.8, 0.35)
	hp_label.add_theme_color_override("font_color", c)
	if damaged:
		damage_flash.color.a = 0.35


func set_ammo(ammo: int, mag: int, reloading: bool) -> void:
	ammo_label.text = "Перезарядка..." if reloading else "%d / %d" % [ammo, mag]


func show_center(t: String) -> void:
	center_label.text = t


func hide_center() -> void:
	center_label.text = ""


func show_death(killer: String, t: float) -> void:
	death_killer = killer
	death_left = t
	crosshair.visible = false


func hide_death() -> void:
	death_left = 0.0
	center_label.text = ""
	crosshair.visible = true


func hitmarker(headshot: bool) -> void:
	hit_t = 0.15
	crosshair.modulate = Color(1, 0.2, 0.2) if headshot else Color(1, 0.85, 0.2)
	crosshair.scale = Vector2(1.4, 1.4)


func add_feed(text: String) -> void:
	var l := _label(text, 18, Color(1, 1, 1))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	feed_box.add_child(l)
	while feed_box.get_child_count() > 6:
		feed_box.get_child(0).free()
	get_tree().create_timer(6.0).timeout.connect(func():
		if is_instance_valid(l):
			l.queue_free())


func update_scores(scores: Dictionary) -> void:
	for c in score_grid.get_children():
		c.free()
	for h in ["Игрок", "Убийства", "Смерти"]:
		score_grid.add_child(_label(h, 18, Color(0.65, 0.7, 0.8)))
	var ids := scores.keys()
	ids.sort_custom(func(a, b): return scores[a]["kills"] > scores[b]["kills"])
	var me := multiplayer.get_unique_id()
	for id in ids:
		var s: Dictionary = scores[id]
		var col := Color(1, 0.85, 0.35) if int(id) == me else Color(1, 1, 1)
		score_grid.add_child(_label(str(s["name"]), 22, col))
		score_grid.add_child(_label(str(s["kills"]), 22, col))
		score_grid.add_child(_label(str(s["deaths"]), 22, col))


# ---------------------------------------------------------------- помощники

func _label(t: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _ignore(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _full(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_preset(Control.PRESET_FULL_RECT)


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.1, 0.88)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	return sb

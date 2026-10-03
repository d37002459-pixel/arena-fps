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
var cross_lines: Array = []
var cross_gap := 5.0
var dmg_dir: Control
var dmg_t := 0.0
var hp_bar: ColorRect
var hp_icon: Label
var mag_label: Label
var gfx_button: OptionButton


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
	hint_label = _label("ПКМ — прицел   R — перезарядка   Tab — счёт   Esc — пауза", 15, Color(1, 1, 1, 0.7))
	hint_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(hint_label)
	var sp1 := Control.new()
	_ignore(sp1)
	sp1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp1)
	feed_box = VBoxContainer.new()
	_ignore(feed_box)
	feed_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	feed_box.add_theme_constant_override("separation", 4)
	top.add_child(feed_box)

	var sp2 := Control.new()
	_ignore(sp2)
	sp2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sp2)

	var bottom := HBoxContainer.new()
	_ignore(bottom)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(bottom)
	# здоровье: иконка, число, полоска
	var hp_panel := PanelContainer.new()
	_ignore(hp_panel)
	hp_panel.add_theme_stylebox_override("panel", _hud_style())
	bottom.add_child(hp_panel)
	var hp_row := HBoxContainer.new()
	_ignore(hp_row)
	hp_row.add_theme_constant_override("separation", 12)
	hp_panel.add_child(hp_row)
	hp_icon = _label("+", 44, Color(0.55, 1.0, 0.6))
	hp_row.add_child(hp_icon)
	var hp_col := VBoxContainer.new()
	_ignore(hp_col)
	hp_col.add_theme_constant_override("separation", 2)
	hp_row.add_child(hp_col)
	hp_label = _label("100", 38, Color(1, 1, 1))
	hp_col.add_child(hp_label)
	var bar_bg := ColorRect.new()
	_ignore(bar_bg)
	bar_bg.color = Color(1, 1, 1, 0.15)
	bar_bg.custom_minimum_size = Vector2(150, 6)
	hp_col.add_child(bar_bg)
	hp_bar = ColorRect.new()
	_ignore(hp_bar)
	hp_bar.color = Color(0.55, 1.0, 0.6)
	hp_bar.size = Vector2(150, 6)
	bar_bg.add_child(hp_bar)
	var sp3 := Control.new()
	_ignore(sp3)
	sp3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(sp3)
	# патроны
	var ammo_panel := PanelContainer.new()
	_ignore(ammo_panel)
	ammo_panel.add_theme_stylebox_override("panel", _hud_style())
	bottom.add_child(ammo_panel)
	var ammo_row := HBoxContainer.new()
	_ignore(ammo_row)
	ammo_row.add_theme_constant_override("separation", 10)
	ammo_panel.add_child(ammo_row)
	var wname := _label("АКМ", 16, Color(1, 1, 1, 0.55))
	wname.size_flags_vertical = Control.SIZE_SHRINK_END
	ammo_row.add_child(wname)
	ammo_label = _label("30", 44, Color(1, 1, 1))
	ammo_row.add_child(ammo_label)
	mag_label = _label("/ 30", 22, Color(1, 1, 1, 0.6))
	mag_label.size_flags_vertical = Control.SIZE_SHRINK_END
	ammo_row.add_child(mag_label)

	# прицел
	var cc := CenterContainer.new()
	_full(cc)
	add_child(cc)
	crosshair = Control.new()
	_ignore(crosshair)
	crosshair.custom_minimum_size = Vector2(32, 32)
	cc.add_child(crosshair)
	for i in 5:
		var cr := ColorRect.new()
		_ignore(cr)
		cr.color = Color(1, 1, 1, 0.92)
		crosshair.add_child(cr)
		cross_lines.append(cr)
	crosshair.pivot_offset = Vector2(16, 16)
	_layout_cross()

	# индикатор направления урона
	var cc5 := CenterContainer.new()
	_full(cc5)
	add_child(cc5)
	dmg_dir = Control.new()
	_ignore(dmg_dir)
	dmg_dir.custom_minimum_size = Vector2(0, 0)
	cc5.add_child(dmg_dir)
	var arc := ColorRect.new()
	_ignore(arc)
	arc.color = Color(1, 0.15, 0.1, 0.85)
	arc.position = Vector2(-45, -150)
	arc.size = Vector2(90, 9)
	dmg_dir.add_child(arc)
	var tip := ColorRect.new()
	_ignore(tip)
	tip.color = Color(1, 0.15, 0.1, 0.85)
	tip.position = Vector2(-8, -164)
	tip.size = Vector2(16, 14)
	dmg_dir.add_child(tip)
	dmg_dir.modulate.a = 0.0

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
	var gfx_row := HBoxContainer.new()
	pv.add_child(gfx_row)
	var gl := _label("Графика", 18, Color(1, 1, 1, 0.8))
	gl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gfx_row.add_child(gl)
	gfx_button = OptionButton.new()
	for t in ["Низкая", "Средняя", "Высокая"]:
		gfx_button.add_item(t)
	gfx_button.selected = main.graphics
	gfx_button.item_selected.connect(func(i): main.set_graphics(i))
	gfx_row.add_child(gfx_button)
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
	if dmg_t > 0.0:
		dmg_t -= delta
		dmg_dir.modulate.a = clampf(dmg_t / 0.6, 0.0, 1.0)
	if death_left > 0.0:
		death_left -= delta
		var who := "Тебя убил: %s" % death_killer if death_killer != "" else "Ты погиб"
		center_label.text = "%s\nВозрождение через %d" % [who, ceili(maxf(death_left, 0.0))]


# ---------------------------------------------------------------- API

func set_in_game(v: bool) -> void:
	in_game = v


func _layout_cross() -> void:
	var g := cross_gap
	var L := 7.0
	var rects := [
		Rect2(15, 16 - g - L, 2, L), Rect2(15, 16 + g, 2, L),
		Rect2(16 - g - L, 15, L, 2), Rect2(16 + g, 15, L, 2), Rect2(15, 15, 2, 2),
	]
	for i in 5:
		cross_lines[i].position = rects[i].position
		cross_lines[i].size = rects[i].size


## gap — разброс в пикселях; hidden — прячем при прицеливании (там красная точка)
func set_crosshair(spread_px: float, hidden: bool) -> void:
	var g := clampf(3.0 + spread_px, 3.0, 80.0)
	if absf(g - cross_gap) > 0.3:
		cross_gap = g
		_layout_cross()
	crosshair.visible = not hidden


func damage_from(angle: float) -> void:
	dmg_dir.rotation = angle
	dmg_t = 1.4
	dmg_dir.modulate.a = 1.0


func set_hp(hp: int, damaged: bool) -> void:
	hp_label.text = str(hp)
	var c := Color(0.55, 1.0, 0.6)
	if hp <= 30:
		c = Color(1.0, 0.35, 0.3)
	elif hp <= 60:
		c = Color(1.0, 0.8, 0.35)
	hp_icon.add_theme_color_override("font_color", c)
	hp_bar.color = c
	hp_bar.size = Vector2(150.0 * clampf(hp / 100.0, 0.0, 1.0), 6)
	if damaged:
		damage_flash.color.a = 0.35


func set_ammo(ammo: int, mag: int, reloading: bool) -> void:
	ammo_label.text = "···" if reloading else str(ammo)
	mag_label.text = "/ %d" % mag
	ammo_label.add_theme_color_override("font_color", Color(1, 0.4, 0.3) if ammo <= 8 and not reloading else Color(1, 1, 1))


func show_center(t: String) -> void:
	center_label.text = t


func hide_center() -> void:
	center_label.text = ""


func show_death(killer: String, t: float) -> void:
	death_killer = killer
	death_left = t



func hide_death() -> void:
	death_left = 0.0
	center_label.text = ""


func hitmarker(headshot: bool) -> void:
	hit_t = 0.15
	crosshair.modulate = Color(1, 0.2, 0.2) if headshot else Color(1, 0.85, 0.2)
	crosshair.scale = Vector2(1.4, 1.4)


func add_feed(text: String) -> void:
	var l := PanelContainer.new()
	_ignore(l)
	var st := _hud_style()
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	st.content_margin_left = 12
	st.content_margin_right = 12
	l.add_theme_stylebox_override("panel", st)
	l.size_flags_horizontal = Control.SIZE_SHRINK_END
	var t := _label(text, 17, Color(1, 1, 1))
	if "убил" in text:
		t.add_theme_color_override("font_color", Color(1, 0.92, 0.8))
	l.add_child(t)
	feed_box.add_child(l)
	while feed_box.get_child_count() > 6:
		feed_box.get_child(0).free()
	get_tree().create_timer(6.0).timeout.connect(l.queue_free)


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


func _hud_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.07, 0.55)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 16
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	return sb


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.1, 0.88)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	return sb

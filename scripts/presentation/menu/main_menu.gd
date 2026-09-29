extends Control

const Kit = preload("res://scripts/presentation/ui_theme.gd")
const Content = preload("res://scripts/presentation/menu/menu_content.gd")
const UiText = preload("res://scripts/presentation/ui_text.gd")
const BATTLE_SCENE := "res://scenes/battle/prototype_battle.tscn"
const CUSTOM_SIZES = Content.CUSTOM_SIZES
const MAP_OPTIONS = Content.MAP_OPTIONS
const TUTORIALS = Content.TUTORIALS
const CHALLENGES = Content.CHALLENGES
const IMPLEMENTED_TUTORIAL_LEVEL_IDS = Content.IMPLEMENTED_TUTORIAL_LEVEL_IDS

var content: VBoxContainer
var custom_size_selector: OptionButton
var custom_map_selector: OptionButton
var custom_weather_selector: OptionButton
var fleet_grid: GridContainer
var custom_status: Label
var custom_start_button: Button
var selected_ship_ids: Array[String] = []
var ship_buttons: Dictionary = {}
var progress_failure_banner: HBoxContainer
var progress_failure_label: Label
var progress_retry_button: Button
var page := "home"
var cover_index := 0
var covers: Array[Dictionary] = []
var cover_front: TextureRect
var cover_back: TextureRect
var clock_panel: Control
var clock_time: Label
var clock_date: Label
var clock_elapsed := 0.0
var chrome: Control
var page_panel: PanelContainer
var home_panel: Control
var cover_label: Label
var nav_buttons: Dictionary = {}
var nav_row: HBoxContainer
var header_brand: Button
var home_actions: Array[Button] = []
var gallery: PanelContainer
var restore_button: Button
var detail_column: VBoxContainer
var fleet_column: VBoxContainer
var level_buttons: Dictionary = {}
var search_text := ""
var filter_class := ""
var custom_size_index := 1
var custom_map_index := 0
var custom_weather_id := "clear_day"
var challenge_chapter := 0
var viewing := false
var idle_seconds := 0.0
var page_tween: Tween
var cover_tween: Tween
var settings_status: Label
var launching := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Kit.make_theme()
	covers = DataRegistry.assets.menu_covers()
	var preferred := str(GameFlow.menu_preferences.get("cover_id", "hood_harbor"))
	for index in range(covers.size()):
		if str(covers[index].get("id", "")) == preferred: cover_index = index
	_build_shell()
	GameFlow.progress_save_status_changed.connect(_on_progress_save_status_changed)
	_on_progress_save_status_changed(GameFlow.progress_save_state())
	_switch_cover(cover_index, false)
	match GameFlow.menu_return_page:
		"tutorial": _show_tutorial()
		"challenge": _show_challenge()
		"custom": _show_custom()
		_: _show_home()


func _box(node: Control, rect: Rect2, parent: Node = null) -> Control:
	(parent if parent != null else self).add_child(node)
	node.position = rect.position
	node.size = rect.size
	return node


func _label(parent: Node, text: String, pixels := 20, color := Kit.INK) -> Label:
	var label := Kit.label(text, pixels, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, callback: Callable, minimum := Vector2(0, 52), primary := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = minimum
	button.pressed.connect(callback)
	if primary: Kit.primary(button)
	parent.add_child(button)
	button.mouse_entered.connect(func():
		if not button.disabled: create_tween().tween_property(button, "modulate", Color(1.04, 1.04, 1.04), _motion_seconds(0.12))
	)
	button.mouse_exited.connect(func(): create_tween().tween_property(button, "modulate", Color.WHITE, _motion_seconds(0.12)))
	return button


func _column(parent: Node, gap := 16) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", gap)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	return column


func _row(parent: Node, gap := 16) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", gap)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	return row


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _texture(path: String) -> Texture2D:
	return load(path) as Texture2D if not path.is_empty() and ResourceLoader.exists(path) else null


func _portrait(ship_id: String) -> Texture2D:
	return _texture(DataRegistry.assets.character_ui_asset_path(ship_id.trim_prefix("ship."), "ui_portrait"))


func _build_shell() -> void:
	var background := ColorRect.new()
	background.color = Color("#65838e")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box(background, Rect2(0, 0, 1920, 1080))
	for index in range(2):
		var image := TextureRect.new()
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_box(image, Rect2(-8, -5, 1936, 1090))
		if index == 0: cover_back = image
		else: cover_front = image
	chrome = Control.new()
	chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box(chrome, Rect2(0, 0, 1920, 1080))
	var brand := _button(chrome, "小小海战", _show_home, Vector2(208, 62))
	header_brand = brand
	Kit.cover_button(brand)
	brand.position = Vector2(64, 40)
	brand.add_theme_font_size_override("font_size", 30)
	var nav := HBoxContainer.new()
	nav_row = nav
	nav.add_theme_constant_override("separation", 12)
	_box(nav, Rect2(700, 40, 1156, 62), chrome)
	for entry in [["tutorial", "教学关", _show_tutorial], ["challenge", "挑战关", _show_challenge], ["custom", "自定义战斗", _show_custom], ["help", "操作说明", _show_help], ["settings", "设置", _show_settings]]:
		var button := _button(nav, entry[1], entry[2], Vector2(210, 62))
		Kit.cover_button(button)
		button.toggle_mode = true
		nav_buttons[entry[0]] = button
	page_panel = PanelContainer.new()
	page_panel.add_theme_stylebox_override("panel", Kit.panel(Color(0.965, 0.985, 0.99, 0.98), 22, 30))
	_box(page_panel, Rect2(64, 176, 1792, 786), chrome)
	content = _column(page_panel, 18)
	home_panel = Control.new()
	home_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box(home_panel, Rect2(96, 210, 700, 670), chrome)
	var eyebrow := Kit.label("舰娘相伴  ·  向海而行", 22, Color("#f4dbaa"))
	_box(eyebrow, Rect2(4, 0, 650, 40), home_panel)
	var title := Kit.label("小小海战", 88, Color.WHITE)
	_box(title, Rect2(0, 54, 650, 125), home_panel)
	var subtitle := Kit.label("下一段航程，与你一起。", 28, Color("#d5e8eb"))
	_box(subtitle, Rect2(4, 194, 650, 44), home_panel)
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 18)
	_box(actions, Rect2(4, 302, 384, 244), home_panel)
	for entry in [["教学关", _show_tutorial], ["挑战关", _show_challenge], ["自定义战斗", _show_custom]]:
		var button := _button(actions, entry[0], entry[1], Vector2(384, 70))
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_font_size_override("font_size", 28)
		Kit.cover_button(button, true)
		home_actions.append(button)
	for label in [eyebrow, title, subtitle]:
		label.add_theme_color_override("font_shadow_color", Color(0.03, 0.10, 0.15, 0.85))
		label.add_theme_constant_override("shadow_offset_y", 2)
		label.add_theme_constant_override("shadow_outline_size", 2)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	_box(footer, Rect2(64, 992, 736, 54), chrome)
	_button(footer, "‹", func(): _switch_cover(cover_index - 1), Vector2(54, 54))
	cover_label = _label(footer, "", 19, Color.WHITE)
	cover_label.custom_minimum_size.x = 320
	cover_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_button(footer, "›", func(): _switch_cover(cover_index + 1), Vector2(54, 54))
	_button(footer, "看板", _show_gallery, Vector2(100, 54))
	_button(footer, "观赏", func(): set_viewing(true), Vector2(100, 54))
	for child in footer.get_children():
		if child is Button: Kit.cover_button(child)
	var music := Kit.label("♪  音乐曲库筹备中", 18, Color("#d5e8eb"))
	music.tooltip_text = "正式音乐尚未接入；切换看板不影响未来的标题音乐队列。"
	_box(music, Rect2(880, 1002, 550, 32), chrome)
	progress_failure_banner = HBoxContainer.new()
	progress_failure_banner.add_theme_constant_override("separation", 16)
	_box(progress_failure_banner, Rect2(64, 118, 1792, 44), chrome)
	progress_failure_label = _label(progress_failure_banner, "", 18, Color("#fff2cc"))
	progress_retry_button = _button(progress_failure_banner, "重试保存", _retry_progress_save, Vector2(160, 42))
	restore_button = _button(self, "返回菜单  ·  Esc", func(): set_viewing(false), Vector2(230, 52))
	Kit.cover_button(restore_button)
	restore_button.position = Vector2(64, 990)
	restore_button.visible = false
	_build_clock()


func _build_clock() -> void:
	clock_panel = Control.new()
	clock_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box(clock_panel, Rect2(72, 76, 600, 260))
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Helvetica Neue", "Arial", "sans-serif"])
	font.font_weight = 300
	clock_time = Kit.label("", 144, Color("#fff7e5"))
	clock_time.add_theme_font_override("font", font)
	clock_time.add_theme_color_override("font_shadow_color", Color(0.03, 0.10, 0.15, 0.55))
	clock_time.add_theme_constant_override("shadow_offset_y", 3)
	clock_time.add_theme_constant_override("shadow_outline_size", 1)
	_box(clock_time, Rect2(0, 0, 600, 184), clock_panel)
	clock_date = Kit.label("", 26, Color("#fff7e5"))
	clock_date.add_theme_color_override("font_shadow_color", Color(0.03, 0.10, 0.15, 0.9))
	clock_date.add_theme_constant_override("shadow_offset_y", 2)
	_box(clock_date, Rect2(6, 186, 560, 42), clock_panel)
	_update_clock()
	clock_panel.hide()


func _update_clock() -> void:
	var now := Time.get_datetime_dict_from_system()
	clock_time.text = "%02d:%02d" % [now.hour, now.minute]
	clock_date.text = "%d年%02d月%02d日  ·  %s" % [now.year, now.month, now.day, ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"][now.weekday]]


func _process(delta: float) -> void:
	idle_seconds += delta
	clock_elapsed += delta
	if viewing and clock_elapsed >= 1.0:
		clock_elapsed = 0.0
		_update_clock()
	var offset := Vector2.ZERO
	if not bool(GameFlow.menu_preferences.get("reduce_motion", false)):
		offset = (get_local_mouse_position() / Vector2(1920, 1080) - Vector2(0.5, 0.5)).clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5)) * Vector2(12, 8)
	cover_front.position = cover_front.position.lerp(Vector2(-8, -5) + offset, minf(delta * 3, 1))
	cover_back.position = cover_front.position
	if page == "home" and not viewing and gallery == null and not progress_failure_banner.visible and bool(GameFlow.menu_preferences.get("auto_view", true)) and idle_seconds >= 20.0:
		set_viewing(true)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton or event is InputEventKey:
		idle_seconds = 0.0
	if viewing and (event is InputEventMouseButton or (event is InputEventKey and event.pressed)):
		set_viewing(false)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if gallery != null: _close_gallery()
		elif page != "home": _show_home()
		get_viewport().set_input_as_handled()


func _motion_seconds(value: float) -> float:
	return 0.01 if bool(GameFlow.menu_preferences.get("reduce_motion", false)) else value


func set_viewing(value: bool) -> void:
	if value and progress_failure_banner.visible: return
	viewing = value
	idle_seconds = 0.0
	if gallery != null: _close_gallery()
	chrome.visible = true
	# Hidden controls lose focus and become invisible immediately to GUI input.
	if value:
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null: focused.release_focus()
		chrome.hide()
	clock_panel.visible = value
	if value: _update_clock()
	restore_button.visible = value


func _switch_cover(index: int, persist := true) -> void:
	if covers.is_empty():
		cover_label.text = "海风与你相伴"
		return
	cover_index = posmod(index, covers.size())
	if cover_tween != null: cover_tween.kill()
	cover_back.texture = cover_front.texture
	cover_front.texture = _texture(str(covers[cover_index].get("image", "")))
	cover_front.modulate.a = 0.0 if cover_back.texture != null else 1.0
	cover_tween = create_tween()
	cover_tween.tween_property(cover_front, "modulate:a", 1.0, _motion_seconds(0.55))
	cover_label.text = "%s · %s" % [covers[cover_index].get("display_name", ""), covers[cover_index].get("title", "")]
	if persist and not GameFlow.save_menu_preference("cover_id", covers[cover_index]["id"]):
		cover_label.text += "（偏好保存失败）"


func _show_gallery() -> void:
	if gallery != null: _close_gallery(); return
	gallery = PanelContainer.new()
	_box(gallery, Rect2(510, 420, 1346, 530), chrome)
	var column := _column(gallery)
	var top := _row(column)
	_label(top, "选择陪伴你的舰娘", 30)
	_button(top, "关闭", _close_gallery, Vector2(100, 42))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	column.add_child(grid)
	for index in range(covers.size()):
		var cover: Dictionary = covers[index]
		var button := _button(grid, "%s · %s\n%s" % [cover["display_name"], cover["category"], cover["title"]], func(): _switch_cover(index); _close_gallery(), Vector2(315, 190))
		button.icon = _texture(str(cover["image"]))
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 270)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.add_theme_font_size_override("font_size", 17)
		button.toggle_mode = true
		button.button_pressed = index == cover_index


func _close_gallery() -> void:
	if gallery == null: return
	gallery.queue_free()
	gallery = null


func _begin_page(next_page: String, title: String, subtitle: String) -> void:
	_close_gallery()
	page = next_page
	header_brand.visible = next_page != "home"
	for key in ["tutorial", "challenge", "custom"]:
		nav_buttons[key].visible = next_page != "home"
	nav_row.position = Vector2(64, 40) if next_page == "home" else Vector2(700, 40)
	nav_row.size.x = 440 if next_page == "home" else 1156
	idle_seconds = 0.0
	set_viewing(false)
	_clear(content)
	ship_buttons.clear()
	level_buttons.clear()
	page_panel.visible = next_page != "home"
	home_panel.visible = next_page == "home"
	for key in nav_buttons: nav_buttons[key].set_pressed_no_signal(key == next_page)
	if next_page == "home":
		if page_tween != null: page_tween.kill()
		home_panel.modulate.a = 0.25
		page_tween = create_tween()
		page_tween.tween_property(home_panel, "modulate:a", 1.0, _motion_seconds(0.3))
		return
	_label(content, title, 36)
	_label(content, subtitle, 19, Kit.MUTED)
	if page_tween != null: page_tween.kill()
	page_panel.modulate.a = 0.25
	page_tween = create_tween()
	page_tween.tween_property(page_panel, "modulate:a", 1.0, _motion_seconds(0.22))


func _show_home() -> void:
	_begin_page("home", "", "")


func _show_tutorial() -> void:
	_begin_page("tutorial", "教学 · 从容启航", "从一次移动到舰队协同，选择你想练习的内容。所有教学均可直接进入。")
	var row := _row(content, 26)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := _scroll(row, 440)
	var list := _column(scroll, 10)
	for entry in TUTORIALS:
		var code := str(entry[0])
		var button := _button(list, "%s  %s" % [code, entry[1]], _show_level_detail.bind(IMPLEMENTED_TUTORIAL_LEVEL_IDS[code], entry[2], true), Vector2(420, 62))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		level_buttons[IMPLEMENTED_TUTORIAL_LEVEL_IDS[code]] = button
	detail_column = _column(row, 14)
	_show_level_detail(IMPLEMENTED_TUTORIAL_LEVEL_IDS["T-01"], TUTORIALS[0][2], true)


func _show_challenge() -> void:
	_begin_page("challenge", "挑战 · 下一片海", "小型、中型、大型各自推进，首关无需前置通关；完成一关后开放同板块下一关。")
	var tabs := _row(content)
	var names: Array = CHALLENGES.keys()
	for index in range(names.size()):
		var button := _button(tabs, names[index], func(): challenge_chapter = index; _show_challenge(), Vector2(350, 48))
		button.toggle_mode = true
		button.button_pressed = challenge_chapter == index
	var row := _row(content, 26)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := _column(_scroll(row, 440), 12)
	var entries: Array = CHALLENGES[names[challenge_chapter]]
	var initial_id := ""
	var initial_open := false
	for index in range(entries.size()):
		var entry: Array = entries[index]
		var id := _challenge_level_id(entry[0])
		var exists: bool = not DataRegistry.registry.get_definition("levels", id).is_empty()
		var unlocked: bool = exists and (index == 0 or _challenge_level_id(entries[index - 1][0]) in GameFlow.completed_challenge_level_ids)
		var status := "筹备中" if not exists else ("已完成" if id in GameFlow.completed_challenge_level_ids else ("可出击" if unlocked else "完成本板块前一关后开放"))
		var button := _button(list, "%s  %s\n%s" % [entry[0], entry[1], status], _show_level_detail.bind(id, "", unlocked), Vector2(420, 86))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		level_buttons[id] = button
		if index == 0: initial_id = id; initial_open = unlocked
	detail_column = _column(row, 12)
	_show_level_detail(initial_id, "", initial_open)


func _challenge_level_id(code: String) -> String:
	return "level.challenge.%s" % code.to_lower().replace("-", "")


func _scroll(parent: Node, width := 0) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if width > 0: scroll.custom_minimum_size.x = width
	else: scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	return scroll


func _show_level_detail(id: String, summary: String, unlocked: bool) -> void:
	_clear(detail_column)
	for key in level_buttons: level_buttons[key].set_pressed_no_signal(key == id)
	var level: Dictionary = DataRegistry.registry.get_definition("levels", id)
	if level.is_empty():
		_label(detail_column, "新的航程，正在准备", 32)
		_label(detail_column, "本关内容正在制作，暂时无法出击。三个板块独立推进，无需先通关其他板块。", 21, Kit.MUTED)
		return
	_label(detail_column, str(level.get("display_name", "作战任务")), 30)
	var objective: Dictionary = DataRegistry.registry.get_definition("objectives", str(level.get("objective_set_id", "")))
	var description := summary
	if description.is_empty(): description = str(objective.get("description", objective.get("title", "完成关卡指定任务")))
	_label(detail_column, description, 21, Kit.MUTED)
	var fleets := _row(detail_column, 30)
	_fleet_preview(fleets, "出击舰队", level.get("player_fleet", []))
	_fleet_preview(fleets, "敌方舰队", level.get("enemy_fleet", []))
	var objective_scroll := _scroll(detail_column)
	var instructions := _column(objective_scroll, 10)
	_label(instructions, "作战目标", 22)
	var facts: Array[String] = []
	for action in objective.get("required_actions", []):
		var instruction := str(action.get("instruction", ""))
		if not instruction.is_empty(): facts.append(instruction)
	for condition in objective.get("success_conditions", []):
		var instruction := str(condition.get("description", condition.get("instruction", "")))
		if not instruction.is_empty(): facts.append(instruction)
	if facts.is_empty() and str(objective.get("completion_text", "")).is_empty(): facts.append(str(objective.get("description", "完成指定任务，保护己方旗舰。")))
	for fact in facts: _label(instructions, "• " + fact, 19)
	if not str(objective.get("completion_text", "")).is_empty():
		_label(instructions, "完成目标：" + str(objective["completion_text"]), 19, Kit.TEAL)
	if not str(objective.get("failure_text", "")).is_empty():
		_label(instructions, "取消条件：" + str(objective["failure_text"]), 19, Color("#a7424e"))
	var rewards: Array[String] = []
	for ship in DataRegistry.registry.all("ships"):
		if str(GameFlow.ship_acquisition(str(ship["id"])).get("source_level_id", "")) == id:
			rewards.append(str(ship.get("display_name", "")))
	if not rewards.is_empty(): _label(detail_column, "首胜可获得：" + "、".join(rewards), 18, Kit.TEAL)
	var start := _button(detail_column, "准备好了 · 出击" if unlocked else "完成本板块前一关后开放", _start_level.bind(id), Vector2(0, 58), true)
	start.disabled = not unlocked


func _fleet_preview(parent: Node, title: String, fleet: Array) -> void:
	var column := _column(parent, 8)
	_label(column, "%s  /  %d 艘" % [title, fleet.size()], 18, Kit.MUTED)
	var row := _row(column, 10)
	for member in fleet:
		var id := str(member.get("ship_id", ""))
		var ship: Dictionary = DataRegistry.registry.get_definition("ships", id)
		var image := TextureRect.new()
		image.texture = _portrait(id)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.custom_minimum_size = Vector2(74, 78)
		image.tooltip_text = str(ship.get("display_name", "")) + (" · 旗舰" if member.get("is_flagship", false) else "")
		row.add_child(image)


func _show_custom() -> void:
	_begin_page("custom", "自定义 · 写下你的航线", "选择海域与天气，把喜欢的舰娘编入队伍。编成中的第一位担任旗舰。")
	var selectors := _row(content)
	custom_size_selector = _selector_with_label(selectors, "舰队规模")
	for option in CUSTOM_SIZES: custom_size_selector.add_item(option["label"])
	custom_size_selector.select(custom_size_index)
	custom_map_selector = _selector_with_label(selectors, "作战海域")
	custom_weather_selector = _selector_with_label(selectors, "天气与时段")
	_refresh_custom_maps()
	_load_weather_options()
	custom_size_selector.item_selected.connect(func(index): custom_size_index = index; custom_map_index = 0; _refresh_custom_maps(); _refresh_fleet_state())
	custom_map_selector.item_selected.connect(func(index): custom_map_index = index)
	custom_weather_selector.item_selected.connect(func(index): custom_weather_id = str(custom_weather_selector.get_item_metadata(index)))
	var body := _row(content, 24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var roster := _column(body, 12)
	var filters := _row(roster)
	var search := LineEdit.new()
	search.placeholder_text = "搜索舰娘姓名"
	search.text = search_text
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.custom_minimum_size.y = 46
	filters.add_child(search)
	search.text_changed.connect(func(value): search_text = value; _filter_ships())
	var classes := OptionButton.new()
	classes.custom_minimum_size = Vector2(210, 46)
	filters.add_child(classes)
	var keys := ["", "Destroyer", "LightCruiser", "HeavyCruiser", "Battleship", "Carrier", "Submarine"]
	for key in keys: classes.add_item("全部舰种" if key.is_empty() else UiText.ship_class_name(key))
	classes.select(maxi(0, keys.find(filter_class)))
	classes.item_selected.connect(func(index): filter_class = keys[index]; _filter_ships())
	fleet_grid = GridContainer.new()
	fleet_grid.columns = 4
	fleet_grid.add_theme_constant_override("h_separation", 10)
	fleet_grid.add_theme_constant_override("v_separation", 10)
	fleet_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll(roster).add_child(fleet_grid)
	_build_ship_cards()
	var summary := PanelContainer.new()
	summary.custom_minimum_size.x = 380
	body.add_child(summary)
	var summary_column := _column(summary, 12)
	_label(summary_column, "你的出击舰队", 25)
	custom_status = _label(summary_column, "", 19)
	fleet_column = _column(_scroll(summary_column), 10)
	custom_start_button = _button(summary_column, "确认编成 · 出击", _start_custom_battle, Vector2(340, 58), true)
	_refresh_fleet_state()
	_filter_ships()


func _selector_with_label(parent: Node, text: String) -> OptionButton:
	var column := _column(parent, 6)
	_label(column, text, 17, Kit.MUTED)
	var selector := OptionButton.new()
	selector.custom_minimum_size = Vector2(380, 46)
	column.add_child(selector)
	return selector


func _load_weather_options() -> void:
	var palettes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/environments/ocean_palettes.json")).get("palettes", {})
	var ids: Array = palettes.keys()
	for alias in ["day_clear", "cloudy", "dusk"]: ids.erase(alias)
	ids.sort()
	for id in ids:
		custom_weather_selector.add_item(str(palettes[id].get("display_name", id)))
		custom_weather_selector.set_item_metadata(custom_weather_selector.item_count - 1, id)
	custom_weather_selector.select(maxi(0, ids.find(custom_weather_id)))


func _refresh_custom_maps() -> void:
	custom_map_selector.clear()
	var count := int(CUSTOM_SIZES[custom_size_index]["count"])
	for option in MAP_OPTIONS:
		if count not in option["sizes"]: continue
		custom_map_selector.add_item(option["label"])
		custom_map_selector.set_item_metadata(custom_map_selector.item_count - 1, CUSTOM_SIZES[custom_size_index]["base"] if option["label"] == "开阔海域" else option["level"])
	custom_map_index = mini(custom_map_index, custom_map_selector.item_count - 1)
	custom_map_selector.select(custom_map_index)


func _build_ship_cards() -> void:
	var ships: Array = DataRegistry.registry.all("ships")
	ships.sort_custom(func(a, b):
		var owned_a := GameFlow.is_ship_unlocked(str(a["id"]))
		var owned_b := GameFlow.is_ship_unlocked(str(b["id"]))
		return owned_a if owned_a != owned_b else str(a["id"]) < str(b["id"])
	)
	for ship in ships:
		var id := str(ship["id"])
		var unlocked := GameFlow.is_ship_unlocked(id)
		var button := Button.new()
		button.toggle_mode = true
		button.disabled = not unlocked
		button.custom_minimum_size = Vector2(305, 115)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 16)
		button.icon = _portrait(id)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 76)
		button.text = "%s\n%s · Lv.%d · Cost %d\n%s" % [ship.get("display_name", ""), UiText.ship_class_name(str(ship["ship_class"])), int(ship["level"]), int(ship["cost"]), "已拥有" if unlocked else "未拥有"]
		button.tooltip_text = GameFlow.ship_acquisition_label(id)
		button.toggled.connect(_toggle_ship.bind(id))
		fleet_grid.add_child(button)
		ship_buttons[id] = button


func _filter_ships() -> void:
	for id in ship_buttons:
		var ship: Dictionary = DataRegistry.registry.get_definition("ships", id)
		ship_buttons[id].visible = (search_text.is_empty() or str(ship.get("display_name", "")).contains(search_text)) and (filter_class.is_empty() or str(ship.get("ship_class", "")) == filter_class)


func _toggle_ship(pressed: bool, id: String) -> void:
	if pressed and not GameFlow.is_ship_unlocked(id): return
	if pressed and id not in selected_ship_ids:
		if selected_ship_ids.size() >= int(CUSTOM_SIZES[custom_size_index]["count"]):
			ship_buttons[id].set_pressed_no_signal(false)
			custom_status.text = "舰队已满，请先移除一位舰娘。"
			return
		selected_ship_ids.append(id)
	elif not pressed: selected_ship_ids.erase(id)
	_refresh_fleet_state()


func _refresh_fleet_state() -> void:
	if custom_status == null or not is_instance_valid(custom_status): return
	var option: Dictionary = CUSTOM_SIZES[custom_size_index]
	var required := int(option["count"])
	while selected_ship_ids.size() > required: selected_ship_ids.pop_back()
	var used := 0
	for id in selected_ship_ids: used += int(DataRegistry.registry.get_definition("ships", id).get("cost", 0))
	custom_status.text = "已选 %d / %d 艘\nCost %d / %d%s" % [selected_ship_ids.size(), required, used, int(option["cost"]), " · 超出预算" if used > int(option["cost"]) else ""]
	custom_status.add_theme_color_override("font_color", Color("#a7424e") if used > int(option["cost"]) else Kit.INK)
	for id in ship_buttons: ship_buttons[id].set_pressed_no_signal(id in selected_ship_ids)
	_clear(fleet_column)
	for index in range(selected_ship_ids.size()):
		var id := selected_ship_ids[index]
		var ship: Dictionary = DataRegistry.registry.get_definition("ships", id)
		var row := _row(fleet_column, 6)
		var label := _label(row, ("旗舰 " if index == 0 else "%02d " % (index + 1)) + str(ship.get("display_name", "")), 18)
		label.tooltip_text = "旗舰" if index == 0 else "可设为旗舰"
		if index > 0: _button(row, "旗舰", func(): selected_ship_ids.erase(id); selected_ship_ids.push_front(id); _refresh_fleet_state(), Vector2(64, 38)).add_theme_font_size_override("font_size", 15)
		_button(row, "移除", func(): selected_ship_ids.erase(id); _refresh_fleet_state(), Vector2(64, 38)).add_theme_font_size_override("font_size", 15)
	if selected_ship_ids.is_empty(): _label(fleet_column, "从左侧选择已拥有的舰娘。\n第一位加入的舰娘成为旗舰。", 19, Kit.MUTED)
	custom_start_button.disabled = selected_ship_ids.size() != required or used > int(option["cost"]) or custom_map_selector.item_count == 0 or custom_weather_selector.item_count == 0


func _start_custom_battle() -> void:
	var result: Dictionary = GameFlow.configure_custom_battle(str(CUSTOM_SIZES[custom_size_index]["base"]), str(custom_map_selector.get_item_metadata(custom_map_selector.selected)), str(custom_weather_selector.get_item_metadata(custom_weather_selector.selected)), selected_ship_ids)
	if not result.get("ok", false):
		custom_status.text = "编成或地图暂不可用，请检查舰队人数与角色解锁状态。"
		return
	_start_level(str(result["level_id"]))


func _start_level(id: String) -> void:
	if launching: return
	launching = true
	GameFlow.menu_return_page = page
	GameFlow.select_level(id)
	var error := get_tree().change_scene_to_file(BATTLE_SCENE)
	if error != OK:
		launching = false
		_label(content, "暂时无法进入战场，请重新尝试。", 22, Color("#a7424e"))


func _show_help() -> void:
	_begin_page("help", "操作说明 · 把战术变成行动", "从基础指挥开始。主要武器与技能由你把握时机，自动辅助可以逐舰开启。")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 20)
	content.add_child(grid)
	var groups := [
		["选择与航行", "左键 / 拖框    选择舰娘，Shift 增选\n左键敌舰    集火；右键海面    移动\n1–9 / 0 / -    切换舰娘\nZ    连续航点；Esc 退出布置"],
		["武器与技能", "E    主要武器瞄准，左键确认\nQ    切换 HE / AP 弹药\nF    主动技能\n右键 / Esc    取消当前瞄准"],
		["辅助与潜航", "X    辅助航行；V    主武器自动\nC    水面舰副武器 / 潜艇上下潜\nCmd / Alt + X / C / V    舰队开关\n舰队 C 不改变潜艇深度"],
		["镜头与战术暂停", "WASD    移动镜头；滚轮    缩放\nG    跟踪选中舰娘\nSpace    暂停 / 继续并执行计划\n暂停时可布置航点、集火与攻击指令"],
	]
	for group in groups:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(850, 230)
		grid.add_child(panel)
		var column := _column(panel, 14)
		_label(column, group[0], 27)
		var text := _label(column, group[1], 21, Kit.MUTED)
		text.add_theme_constant_override("line_spacing", 9)
	_label(content, "港湾设施：H 控制 · J 补给维修 · K 空袭（Shift 巡逻 / Cmd 侦察）· L 布雷 · U / Backspace 取消或离泊", 18, Kit.MUTED)


func _show_settings() -> void:
	_begin_page("settings", "设置 · 让陪伴更舒适", "窗口尺寸与封面偏好会保存在本机，随时可以调整。")
	var row := _row(content, 40)
	var column := _column(row, 22)
	_label(column, "画面与窗口", 26)
	var selector := OptionButton.new()
	selector.custom_minimum_size = Vector2(660, 52)
	var options: Array[Vector2i] = GameFlow.window_size_options()
	for index in range(options.size()):
		selector.add_item("%d × %d" % [options[index].x, options[index].y])
		if options[index] == GameFlow.current_window_size: selector.select(index)
	column.add_child(selector)
	_button(column, "应用窗口尺寸", func():
		settings_status.text = "已应用窗口尺寸" if GameFlow.apply_window_size(options[selector.selected]) else "窗口偏好保存失败，请重试。"
	, Vector2(0, 52), true)
	for entry in [["reduce_motion", "减少动效", "缩短封面与页面切换，保留清楚的状态反馈。"], ["auto_view", "自动进入观赏", "首页静置 20 秒后收起菜单；点击或按任意键返回。"]]:
		var toggle := CheckButton.new()
		toggle.text = entry[1]
		toggle.button_pressed = bool(GameFlow.menu_preferences.get(entry[0], false))
		toggle.toggled.connect(func(enabled): settings_status.text = "偏好已保存" if GameFlow.save_menu_preference(entry[0], enabled) else "偏好保存失败，请重试。")
		column.add_child(toggle)
		_label(column, entry[2], 18, Kit.MUTED)
	settings_status = _label(column, "", 18, Kit.TEAL)
	var companion := _column(row, 20)
	_label(companion, "看板与音乐", 26)
	_label(companion, "七幅相伴的风景\n海港 · 日常 · 出游", 27, Kit.TEAL)
	_label(companion, "底部“看板”可选择角色与场景，左右箭头快速切换。观赏时按 Esc 或点击返回菜单。", 21, Kit.MUTED)
	_label(companion, "音乐曲库筹备中。正式曲目接入后提供播放、暂停、下一首与单曲循环。", 21, Kit.MUTED)


func _on_progress_save_status_changed(state: Dictionary) -> void:
	progress_failure_banner.visible = str(state.get("status", "Idle")) == "Failed"
	progress_failure_label.text = str(state.get("message", ""))
	progress_retry_button.disabled = not bool(state.get("can_retry", false))
	if progress_failure_banner.visible and viewing: set_viewing(false)


func _retry_progress_save() -> void:
	GameFlow.retry_progress_save()
	_on_progress_save_status_changed(GameFlow.progress_save_state())

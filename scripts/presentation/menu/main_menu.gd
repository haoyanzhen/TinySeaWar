extends Control

const BATTLE_SCENE := "res://scenes/battle/prototype_battle.tscn"
const PALETTE_PATH := "res://data/environments/ocean_palettes.json"
const TEXT_DARK := Color("#244b5a")
const TEXT_SOFT := Color("#5a7883")
const SKY_BLUE := Color("#2fbae6")
const MINT := Color("#35c99a")
const LOCKED := Color("#9aaeb6")
const PANEL_FILL := Color(0.97, 0.99, 1.0, 0.94)
const PANEL_STROKE := Color("#8dd9e8")

const CUSTOM_SIZES := [
	{"label": "1v1 单舰对决", "count": 1, "cost": 12, "base": "level.prototype_1v1"},
	{"label": "3v3 小型舰队", "count": 3, "cost": 22, "base": "level.prototype_3v3"},
	{"label": "5v5 中型舰队", "count": 5, "cost": 34, "base": "level.prototype_5v5"},
	{"label": "11v11 大型舰队", "count": 11, "cost": 64, "base": "level.prototype_11v11"},
]
const MAP_OPTIONS := [
	{"label": "开阔海域", "level": "level.prototype_3v3", "sizes": [1, 3, 5, 11]},
	{"label": "港湾入口", "level": "level.prototype_harbor_3v3", "sizes": [1, 3, 5, 11]},
	{"label": "破碎环礁", "level": "level.prototype_broken_atoll_3v3", "sizes": [1, 3, 5, 11]},
	{"label": "中央沙洲", "level": "level.prototype_central_sandbar_3v3", "sizes": [1, 3, 5, 11]},
	{"label": "新月岛", "level": "level.prototype_crescent_bay_3v3", "sizes": [1, 3, 5, 11]},
	{"label": "双岛长海峡", "level": "level.prototype_double_island_long_channel_3v3", "sizes": [1, 3, 5, 11]},
	{"label": "双航道礁线", "level": "level.prototype_dual_channel_reef_line_3v3", "sizes": [1, 3, 5, 11]},
	{"label": "细长群岛", "level": "level.prototype_long_archipelago_3v3", "sizes": [1, 3, 5, 11]},
	{"label": "大岛偏置", "level": "level.prototype_offset_large_island_3v3", "sizes": [1, 3, 5, 11]},
	{"label": "环岛泻湖", "level": "level.prototype_ring_lagoon_3v3", "sizes": [1, 3, 5, 11]},
	{"label": "散岛群", "level": "level.prototype_scattered_islands_3v3", "sizes": [1, 3, 5, 11]},
]
const TUTORIALS := [
	["T-01", "航向与选择", "移动、连续航点、镜头与旗舰胜利目标"],
	["T-02", "主炮与弹药", "瞄准、HE/AP、射角、装填和装甲伤害"],
	["T-03", "技能窗口", "技能目标、冷却与自动交火边界"],
	["T-04", "重甲压制", "大口径压制、副武器自动能力与月光区"],
	["T-05", "隐蔽雷击", "侦查、隐蔽、雷击角度与脱离"],
	["T-06", "航母猎杀", "目标价值、护航与自动索敌"],
	["T-07", "侦查共享", "前出接触与舰队共享目标"],
	["T-08", "编队考核", "框选、集火、自动开关与旗舰保护"],
]
const IMPLEMENTED_TUTORIAL_LEVEL_IDS := {
	"T-01": "level.tutorial.t01",
	"T-02": "level.tutorial.t02",
	"T-03": "level.tutorial.t03",
	"T-04": "level.tutorial.t04",
	"T-05": "level.tutorial.t05",
	"T-06": "level.tutorial.t06",
	"T-07": "level.tutorial.t07",
	"T-08": "level.tutorial.t08",
}
const CHALLENGES := {
	"小型海战 · 3v3": [["S-01", "首轮接敌"], ["S-02", "侧翼雷线"], ["S-03", "航空诱饵"], ["S-04", "双向伏击"], ["S-05", "狼群门槛"]],
	"中型海战 · 5v5": [["M-01", "港湾扩编"], ["M-02", "泻湖护航"], ["M-03", "群岛雷击"], ["M-04", "风暴猎场"], ["M-05", "海峡封锁"]],
	"大型海战 · 11v11": [["L-01", "舰队展开"], ["L-02", "岛侧航空走廊"], ["L-03", "双航道巨炮"], ["L-04", "风暴群岛合围"], ["L-05", "雷夜环礁终局"]],
}

var content: VBoxContainer
var custom_size_selector: OptionButton
var custom_map_selector: OptionButton
var custom_weather_selector: OptionButton
var fleet_grid: GridContainer
var custom_status: Label
var custom_start_button: Button
var selected_ship_ids: Array[String] = []
var ship_buttons: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_shell()
	_show_home()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#d8eef3"), true)
	for index in range(16):
		var y := 30.0 + index * 72.0
		draw_line(Vector2(0.0, y), Vector2(size.x, y + sin(index) * 24.0), Color(0.3, 0.67, 0.78, 0.09), 3.0)


func _build_shell() -> void:
	var root_margin := MarginContainer.new()
	root_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_margin.add_theme_constant_override("margin_left", 54)
	root_margin.add_theme_constant_override("margin_top", 40)
	root_margin.add_theme_constant_override("margin_right", 54)
	root_margin.add_theme_constant_override("margin_bottom", 40)
	add_child(root_margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 20)
	root_margin.add_child(rows)
	var header := _panel()
	header.custom_minimum_size = Vector2(0, 112)
	rows.add_child(header)
	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 30)
	header_margin.add_theme_constant_override("margin_top", 18)
	header.add_child(header_margin)
	var title := Label.new()
	title.text = "小小海战  /  作战指挥部"
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", TEXT_DARK)
	header_margin.add_child(title)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(body)
	var navigation := _panel()
	navigation.custom_minimum_size = Vector2(270, 0)
	body.add_child(navigation)
	var nav_margin := MarginContainer.new()
	nav_margin.add_theme_constant_override("margin_left", 18)
	nav_margin.add_theme_constant_override("margin_top", 22)
	nav_margin.add_theme_constant_override("margin_right", 18)
	navigation.add_child(nav_margin)
	var nav := VBoxContainer.new()
	nav.add_theme_constant_override("separation", 14)
	nav_margin.add_child(nav)
	_add_nav(nav, "教学", _show_tutorial)
	_add_nav(nav, "挑战", _show_challenge)
	_add_nav(nav, "自定义", _show_custom)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav.add_child(spacer)
	_add_nav(nav, "操作说明", _show_help)
	_add_nav(nav, "设置", _show_settings)

	var content_panel := _panel()
	content_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(content_panel)
	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 30)
	content_margin.add_theme_constant_override("margin_top", 24)
	content_margin.add_theme_constant_override("margin_right", 30)
	content_margin.add_theme_constant_override("margin_bottom", 24)
	content_panel.add_child(content_margin)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	content_margin.add_child(content)


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_FILL
	style.border_color = PANEL_STROKE
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _add_nav(parent: VBoxContainer, label: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0, 58)
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(callback)
	parent.add_child(button)


func _clear_content() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	selected_ship_ids.clear()
	ship_buttons.clear()


func _heading(title_text: String, body_text: String) -> void:
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", TEXT_DARK)
	content.add_child(title)
	var body := Label.new()
	body.text = body_text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 18)
	body.add_theme_color_override("font_color", TEXT_SOFT)
	content.add_child(body)


func _show_home() -> void:
	_clear_content()
	_heading("选择作战入口", "教学用于理解操作、自动能力与海战概念；挑战使用固定舰队完成递进任务；自定义允许选择海域、天气并编成己方舰队。")
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 18)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cards)
	for entry in [["教学", "8 个默认开放训练关", _show_tutorial], ["挑战", "3 个规模章节，共 15 关", _show_challenge], ["自定义", "地图、天气与舰队编成", _show_custom]]:
		var button := Button.new()
		button.text = "%s\n\n%s" % [entry[0], entry[1]]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 24)
		button.pressed.connect(entry[2])
		cards.add_child(button)


func _show_tutorial() -> void:
	_clear_content()
	_heading("教学", "所有教学默认开放。八个教学关均已接入正式运行时。")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for tutorial in TUTORIALS:
		var button := Button.new()
		var tutorial_code := str(tutorial[0])
		var level_id := str(IMPLEMENTED_TUTORIAL_LEVEL_IDS.get(tutorial_code, ""))
		var implemented := not level_id.is_empty()
		button.text = "%s  %s\n%s    · %s" % [tutorial[0], tutorial[1], tutorial[2], "可开始" if implemented else "默认开放 · 待关卡接入"]
		button.custom_minimum_size = Vector2(0, 70)
		button.disabled = not implemented
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if implemented: button.pressed.connect(func(): _start_level(level_id))
		list.add_child(button)


func _show_challenge() -> void:
	_clear_content()
	_heading("挑战", "每个规模章节默认开放第一关，成功后开放同章下一关。任务完成即胜利；正式关卡数据接入前保持禁用。")
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	for chapter_name in CHALLENGES:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 10)
		columns.add_child(column)
		var title := Label.new()
		title.text = chapter_name
		title.add_theme_font_size_override("font_size", 22)
		title.add_theme_color_override("font_color", TEXT_DARK)
		column.add_child(title)
		var levels: Array = CHALLENGES[chapter_name]
		for index in range(levels.size()):
			var button := Button.new()
			var level_code := str(levels[index][0])
			var level_id := _challenge_level_id(level_code)
			var implemented: bool = level_code.begins_with("S-")
			var unlocked: bool = index == 0 or (chapter_name == "小型海战 · 3v3" and ("level.challenge.s%02d" % index) in GameFlow.completed_challenge_level_ids)
			var state_text := "可开始" if implemented and unlocked else ("完成前一关后开放" if implemented else ("默认开放 · 待接入" if index == 0 else "完成前一关后开放"))
			button.text = "%s  %s\n%s" % [levels[index][0], levels[index][1], state_text]
			button.custom_minimum_size = Vector2(0, 80)
			button.disabled = not implemented or not unlocked
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if implemented and unlocked: button.pressed.connect(func(): _start_level(level_id))
			column.add_child(button)


func _challenge_level_id(level_code: String) -> String:
	return "level.challenge.%s" % level_code.to_lower().replace("-", "")


func _show_custom() -> void:
	_clear_content()
	_heading("自定义战斗", "选择规模、已验收地图和 20 套天气，再从全部角色中选择已解锁舰船。第一艘入选舰自动担任旗舰。")
	var selectors := HBoxContainer.new()
	selectors.add_theme_constant_override("separation", 12)
	content.add_child(selectors)
	custom_size_selector = _selector_with_label(selectors, "规模")
	for option in CUSTOM_SIZES:
		custom_size_selector.add_item(option["label"])
	custom_size_selector.select(1)
	custom_size_selector.item_selected.connect(func(_index): _refresh_custom_maps(); _refresh_fleet_state())
	custom_map_selector = _selector_with_label(selectors, "地图")
	custom_weather_selector = _selector_with_label(selectors, "天气与时段")
	_load_weather_options()
	_refresh_custom_maps()

	custom_status = Label.new()
	custom_status.add_theme_font_size_override("font_size", 18)
	custom_status.add_theme_color_override("font_color", TEXT_DARK)
	content.add_child(custom_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	fleet_grid = GridContainer.new()
	fleet_grid.columns = 4
	fleet_grid.add_theme_constant_override("h_separation", 10)
	fleet_grid.add_theme_constant_override("v_separation", 10)
	fleet_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(fleet_grid)
	_build_ship_cards()
	custom_start_button = Button.new()
	custom_start_button.text = "开始自定义战斗"
	custom_start_button.custom_minimum_size = Vector2(0, 54)
	custom_start_button.add_theme_font_size_override("font_size", 22)
	custom_start_button.pressed.connect(_start_custom_battle)
	content.add_child(custom_start_button)
	_refresh_fleet_state()


func _selector_with_label(parent: HBoxContainer, label_text: String) -> OptionButton:
	var group := VBoxContainer.new()
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(group)
	var label := Label.new()
	label.text = label_text
	label.add_theme_color_override("font_color", TEXT_SOFT)
	group.add_child(label)
	var selector := OptionButton.new()
	selector.custom_minimum_size = Vector2(0, 46)
	group.add_child(selector)
	return selector


func _load_weather_options() -> void:
	var file := FileAccess.open(PALETTE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		return
	var palettes: Dictionary = parsed.get("palettes", {})
	var ids: Array = palettes.keys()
	for legacy_id in ["day_clear", "cloudy", "dusk"]:
		ids.erase(legacy_id)
	ids.sort()
	for palette_id in ids:
		custom_weather_selector.add_item(str(palettes[palette_id].get("display_name", palette_id)))
		custom_weather_selector.set_item_metadata(custom_weather_selector.item_count - 1, palette_id)
	var clear_day_index := ids.find("clear_day")
	if clear_day_index >= 0:
		custom_weather_selector.select(clear_day_index)


func _refresh_custom_maps() -> void:
	if custom_map_selector == null:
		return
	custom_map_selector.clear()
	var count := int(CUSTOM_SIZES[custom_size_selector.selected]["count"])
	for option in MAP_OPTIONS:
		if count not in option["sizes"]:
			continue
		custom_map_selector.add_item(option["label"])
		var map_level_id := str(CUSTOM_SIZES[custom_size_selector.selected]["base"]) if option["label"] == "开阔海域" else str(option["level"])
		custom_map_selector.set_item_metadata(custom_map_selector.item_count - 1, map_level_id)


func _build_ship_cards() -> void:
	var flow := get_node_or_null("/root/GameFlow")
	for ship in DataRegistry.registry.all("ships"):
		var ship_id := str(ship.get("id", ""))
		var unlocked: bool = flow != null and bool(flow.is_ship_unlocked(ship_id))
		var button := Button.new()
		button.toggle_mode = true
		button.disabled = not unlocked
		button.custom_minimum_size = Vector2(285, 82)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "%s\n%s · Lv.%d · Cost %d\n%s" % [ship.get("display_name", ship_id), ship.get("ship_class", ""), int(ship.get("level", 1)), int(ship.get("cost", 0)), "已解锁" if unlocked else "未解锁"]
		button.tooltip_text = "可加入编成" if unlocked else "通过教学或挑战关解锁"
		button.add_theme_color_override("font_disabled_color", LOCKED)
		button.toggled.connect(func(pressed: bool, id := ship_id): _toggle_ship(id, pressed))
		fleet_grid.add_child(button)
		ship_buttons[ship_id] = button


func _toggle_ship(ship_id: String, pressed: bool) -> void:
	if pressed:
		if ship_id not in selected_ship_ids:
			selected_ship_ids.append(ship_id)
	else:
		selected_ship_ids.erase(ship_id)
	_refresh_fleet_state()


func _refresh_fleet_state() -> void:
	if custom_size_selector == null or custom_status == null:
		return
	var option: Dictionary = CUSTOM_SIZES[custom_size_selector.selected]
	var required := int(option["count"])
	var cap := int(option["cost"])
	while selected_ship_ids.size() > required:
		var removed: String = selected_ship_ids.pop_back()
		if ship_buttons.has(removed):
			ship_buttons[removed].set_pressed_no_signal(false)
	var used := 0
	for ship_id in selected_ship_ids:
		used += int(DataRegistry.registry.get_definition("ships", ship_id).get("cost", 0))
	custom_status.text = "已选 %d/%d    Cost %d/%d    %s" % [selected_ship_ids.size(), required, used, cap, "第一艘为旗舰" if not selected_ship_ids.is_empty() else "请选择舰船"]
	custom_status.add_theme_color_override("font_color", TEXT_DARK if used <= cap else Color("#e83f5b"))
	if custom_start_button != null:
		custom_start_button.disabled = selected_ship_ids.size() != required or used > cap or custom_map_selector.item_count == 0 or custom_weather_selector.item_count == 0


func _start_custom_battle() -> void:
	var flow := get_node_or_null("/root/GameFlow")
	if flow == null:
		return
	var size_option: Dictionary = CUSTOM_SIZES[custom_size_selector.selected]
	var result: Dictionary = flow.configure_custom_battle(
		str(size_option["base"]),
		str(custom_map_selector.get_item_metadata(custom_map_selector.selected)),
		str(custom_weather_selector.get_item_metadata(custom_weather_selector.selected)),
		selected_ship_ids
	)
	if not result.get("ok", false):
		custom_status.text = "无法创建自定义战斗：%s" % result.get("error", "UNKNOWN")
		return
	var error := get_tree().change_scene_to_file(BATTLE_SCENE)
	if error != OK:
		custom_status.text = "无法进入战斗场景：%s" % error


func _start_level(level_id: String) -> void:
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null: flow.select_level(level_id)
	var error := get_tree().change_scene_to_file(BATTLE_SCENE)
	if error != OK: push_error("Could not start level %s: %s" % [level_id, error])


func _show_help() -> void:
	_clear_content()
	_heading("操作说明", "1-9 / 0 / - 选舰；右键移动；Z 连续航点；X 自动航行；C 副武器自动开火；V 主要武器自动开火；E 主要武器瞄准；Q 切换弹药；F 技能；G 镜头跟踪；空格暂停。\n\n教学入口会逐步解释这些能力、自动开关、侦查共享、雷击、主炮伤害和旗舰目标。")


func _show_settings() -> void:
	_clear_content()
	_heading("界面设置", "选择窗口尺寸，应用后立即生效。")
	var selector := OptionButton.new()
	selector.custom_minimum_size = Vector2(520, 52)
	var flow := get_node_or_null("/root/GameFlow")
	var options: Array[Vector2i] = flow.window_size_options() if flow != null else []
	for index in range(options.size()):
		selector.add_item("%d × %d" % [options[index].x, options[index].y])
		if options[index] == flow.current_window_size:
			selector.select(index)
	content.add_child(selector)
	var status := Label.new()
	status.add_theme_color_override("font_color", TEXT_SOFT)
	content.add_child(status)
	var apply := Button.new()
	apply.text = "应用"
	apply.custom_minimum_size = Vector2(180, 50)
	apply.pressed.connect(func():
		if flow != null and selector.selected >= 0 and flow.apply_window_size(options[selector.selected]):
			status.text = "已应用：%d × %d" % [options[selector.selected].x, options[selector.selected].y]
		else:
			status.text = "设置保存失败。"
	)
	content.add_child(apply)

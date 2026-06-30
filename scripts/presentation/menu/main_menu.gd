extends Control

const UiText = preload("res://scripts/presentation/ui_text.gd")
const BATTLE_SCENE := "res://scenes/battle/prototype_battle.tscn"
const PANEL_FILL := Color(0.93, 0.98, 1.0, 0.88)
const PANEL_STROKE := Color(0.48, 0.82, 0.95, 0.62)
const TEXT_DARK := Color("#123443")
const TEXT_SOFT := Color("#5d8793")
const ACCENT := Color("#ffc857")

var texture_cache: Dictionary = {}
var cover_character_id := "warspite"
var info_title := "选择模式"
var info_body := ""
var mode_buttons: Array[Button] = []
var info_panel_visible := true
var settings_overlay: Control
var resolution_selector: OptionButton
var resolution_status: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	cover_character_id = _random_character_id()
	info_body = _mode_body()
	_create_buttons()
	_create_settings_panel()
	queue_redraw()


func _draw() -> void:
	var viewport_size := size
	_draw_ocean_background(viewport_size)
	_draw_cover_art(Rect2(Vector2(viewport_size.x * 0.43, 36.0), Vector2(viewport_size.x * 0.55, viewport_size.y - 72.0)))
	_draw_title_panel(Rect2(Vector2(56.0, 56.0), Vector2(620.0, 190.0)))
	_draw_info_panel(Rect2(Vector2(56.0, 284.0), Vector2(650.0, 420.0)))
	_draw_footer(Rect2(Vector2(56.0, viewport_size.y - 142.0), Vector2(650.0, 88.0)))


func _create_buttons() -> void:
	_add_button("btn_mode_1v1", "开始 1v1", Vector2(84.0, 724.0), Vector2(180.0, 48.0), func(): _start_level("level.prototype_1v1"))
	_add_button("btn_mode_3v3", "开始 3v3", Vector2(284.0, 724.0), Vector2(180.0, 48.0), func(): _start_level("level.prototype_3v3"))
	_add_button("btn_mode_5v5", "开始 5v5", Vector2(484.0, 724.0), Vector2(180.0, 48.0), func(): _start_level("level.prototype_5v5"))
	_add_button("btn_mode_11v11", "开始 11v11", Vector2(84.0, 786.0), Vector2(180.0, 48.0), func(): _start_level("level.prototype_11v11"))
	_add_button("btn_operation", "操作说明", Vector2(284.0, 786.0), Vector2(180.0, 48.0), func(): _show_operation_guide())
	_add_button("btn_game_intro", "游戏介绍", Vector2(484.0, 786.0), Vector2(180.0, 48.0), func(): _show_game_intro())
	_add_button("btn_settings", "设置", Vector2(84.0, 848.0), Vector2(180.0, 48.0), func(): _show_settings())
	_add_button("btn_mode_harbor", "港湾 3v3", Vector2(284.0, 848.0), Vector2(180.0, 48.0), func(): _start_level("level.prototype_harbor_3v3"))


func _add_button(node_name: String, label: String, position_value: Vector2, size_value: Vector2, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = label
	button.position = position_value
	button.size = size_value
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(callback)
	add_child(button)
	mode_buttons.append(button)
	return button


func _start_level(level_id: String) -> void:
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.select_level(level_id)
	var error := get_tree().change_scene_to_file(BATTLE_SCENE)
	if error != OK:
		push_error("Could not start battle scene: %s" % error)


func _create_settings_panel() -> void:
	settings_overlay = Control.new()
	settings_overlay.name = "SettingsOverlay"
	settings_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_overlay.z_index = 100
	settings_overlay.visible = false
	add_child(settings_overlay)

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.12, 0.17, 0.58)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_overlay.add_child(shade)

	var panel := PanelContainer.new()
	panel.name = "SettingsPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-270.0, -170.0)
	panel.size = Vector2(540.0, 340.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("eefaff")
	panel_style.border_color = PANEL_STROKE
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", panel_style)
	settings_overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	margin.add_child(content)

	var title := Label.new()
	title.text = "界面设置"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", TEXT_DARK)
	content.add_child(title)
	var hint := Label.new()
	hint.text = "选择游戏窗口大小，应用后立即生效。"
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", TEXT_SOFT)
	content.add_child(hint)

	resolution_selector = OptionButton.new()
	resolution_selector.name = "ResolutionSelector"
	resolution_selector.custom_minimum_size = Vector2(0.0, 48.0)
	resolution_selector.add_theme_font_size_override("font_size", 18)
	for option in _window_size_options():
		resolution_selector.add_item("%d x %d" % [option.x, option.y])
	content.add_child(resolution_selector)
	resolution_status = Label.new()
	resolution_status.add_theme_font_size_override("font_size", 16)
	resolution_status.add_theme_color_override("font_color", TEXT_SOFT)
	content.add_child(resolution_status)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	content.add_child(actions)
	var close_button := Button.new()
	close_button.name = "CloseSettingsButton"
	close_button.text = "关闭"
	close_button.custom_minimum_size = Vector2(110.0, 44.0)
	close_button.pressed.connect(func(): settings_overlay.hide())
	actions.add_child(close_button)
	var apply_button := Button.new()
	apply_button.name = "ApplySettingsButton"
	apply_button.text = "应用"
	apply_button.custom_minimum_size = Vector2(110.0, 44.0)
	apply_button.pressed.connect(_apply_selected_window_size)
	actions.add_child(apply_button)


func _show_settings() -> void:
	var current_size := _current_window_size()
	var options := _window_size_options()
	for index in range(options.size()):
		if options[index] == current_size:
			resolution_selector.select(index)
			break
	resolution_status.text = "当前：%d x %d" % [current_size.x, current_size.y]
	settings_overlay.show()


func _apply_selected_window_size() -> void:
	var options := _window_size_options()
	var selected_index := resolution_selector.selected
	if selected_index < 0 or selected_index >= options.size():
		resolution_status.text = "未找到可用的界面尺寸。"
		return
	var selected_size := options[selected_index]
	var flow := get_node_or_null("/root/GameFlow")
	if flow == null or not flow.apply_window_size(selected_size):
		resolution_status.text = "设置保存失败。"
		return
	resolution_status.text = "已应用：%d x %d" % [selected_size.x, selected_size.y]


func _window_size_options() -> Array[Vector2i]:
	var flow := get_node_or_null("/root/GameFlow")
	return flow.window_size_options() if flow != null else []


func _current_window_size() -> Vector2i:
	var flow := get_node_or_null("/root/GameFlow")
	return flow.current_window_size if flow != null else Vector2i(1920, 1080)


func _show_mode_select() -> void:
	info_title = "选择模式"
	info_body = _mode_body()
	queue_redraw()


func _show_operation_guide() -> void:
	info_title = "操作说明"
	info_body = "基础界面：\n- 顶部为敌我舰队，左下为小地图，右侧为日志与选中角色。\n- 底部两排操作槽显示武器、技能、路径、自动控制与镜头状态。\n\n键鼠操作：\n- 1-9 / 0 / - 选舰；左键选择/确认；右键下达单点移动；滚轮缩放。\n- Z：进入连续路径模式，左键追加途径点，再按 Z 或 Esc 结束。\n- X：自动航行；C：副武器自动开火；V：主要武器自动开火。\n- 按住 Cmd 或 Alt 再按 X/C/V：对全部存活己方舰船生效。\n- E：主要武器瞄准；Q：切换弹种；F：手动释放技能。\n- G：跟踪镜头；W/A/S/D：移动镜头；空格：暂停；Esc：取消。"
	queue_redraw()


func _show_game_intro() -> void:
	info_title = "游戏介绍"
	info_body = "小小海战是开阔海域中的轻量二维舰队战。己方舰船默认静止并自动使用副武器；玩家负责规划航线、决定主要武器和技能时机，也可按舰开启受限辅助航行与主要武器自动开火。\n\n核心玩法：\n- 保持己方旗舰存活，同时寻找机会击沉敌方旗舰。\n- 用 Z/右键规划航线，通过 E 抓住主要武器窗口，Q 切换合适弹种。\n- 使用 G 跟随关键角色，用小地图观察整体态势。\n\n胜利条件：\n- 击沉敌方旗舰立即胜利。\n- 时间耗尽时，按双方剩余总耐久比例判定胜负。\n- 双方旗舰同一结算周期沉没时，当前规则判定玩家胜利。"
	queue_redraw()


func _mode_body() -> String:
	return "请选择本次出击模式。\n\n1v1：单舰对决，适合熟悉镜头、选择、主要武器瞄准和旗舰胜负。\n\n3v3：小队舰队战，适合练习角色槽位切换、集火目标、技能和小地图阅读。\n\n5v5：完整小舰队交战，覆盖潜艇、驱逐、巡洋、战列的混合威胁。\n\n11v11：大规模压力战，验证操作槽、侦查密度和表现层性能。\n\n港湾 3v3：验证浅水、航道、岛岸阻挡、海雾/海流和岸基设施。"


func _draw_ocean_background(viewport_size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color("#d8eef3"), true)
	for index in range(18):
		var y := float(index) * 74.0 + 28.0
		var color := Color(0.3, 0.67, 0.78, 0.12 if index % 2 == 0 else 0.07)
		draw_line(Vector2(0.0, y), Vector2(viewport_size.x, y + sin(index) * 28.0), color, 3.0)
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(1.0, 1.0, 1.0, 0.22), true)


func _draw_cover_art(rect: Rect2) -> void:
	var texture := _character_texture(cover_character_id, "illust_skill_cutin_alpha")
	if texture == null:
		return
	var cover_draw_rect := _cover_rect(texture, rect)
	draw_texture_rect(texture, cover_draw_rect, false, Color(1.0, 1.0, 1.0, 0.92))
	draw_rect(Rect2(rect.position + Vector2(18.0, rect.size.y - 112.0), Vector2(rect.size.x - 36.0, 74.0)), Color(0.04, 0.18, 0.24, 0.36), true)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(44.0, rect.size.y - 70.0), "本次封面：%s" % UiText.character_name(cover_character_id), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 88.0, 24, Color.WHITE)


func _draw_title_panel(rect: Rect2) -> void:
	_draw_panel(rect)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(26.0, 58.0), "小小海战", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 52.0, 44, TEXT_DARK)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(28.0, 100.0), "开阔海域舰队战术原型", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 56.0, 20, TEXT_SOFT)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(28.0, 142.0), "选择模式，阅读操作，再把舰队带上海面。", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 56.0, 18, TEXT_DARK)


func _draw_info_panel(rect: Rect2) -> void:
	_draw_panel(rect)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(28.0, 42.0), info_title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 56.0, 28, TEXT_DARK)
	draw_rect(Rect2(rect.position + Vector2(28.0, 62.0), Vector2(96.0, 4.0)), ACCENT, true)
	draw_multiline_string(ThemeDB.fallback_font, rect.position + Vector2(28.0, 112.0), info_body, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 56.0, 18, -1, TEXT_DARK)


func _draw_footer(rect: Rect2) -> void:
	_draw_panel(rect)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(24.0, 36.0), "提示：先用 1v1 熟悉 E 瞄准，再进入 3v3 / 5v5 练习多角色切换。", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 48.0, 18, TEXT_SOFT)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(24.0, 66.0), "11v11 是大规模压力模式，主界面封面每次启动随机选择角色横向立绘。", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 48.0, 16, TEXT_SOFT)


func _draw_panel(rect: Rect2) -> void:
	draw_rect(rect, PANEL_FILL, true)
	draw_rect(rect, PANEL_STROKE, false, 2.0)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 5.0)), Color(0.43, 0.82, 0.96, 0.82), true)


func _random_character_id() -> String:
	var ids: Array[String] = []
	for ship in DataRegistry.registry.all("ships"):
		var slug := str(ship.get("id", "")).trim_prefix("ship.")
		if _character_texture(slug, "illust_skill_cutin_alpha") != null:
			ids.append(slug)
	if ids.is_empty():
		return "warspite"
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return ids[rng.randi_range(0, ids.size() - 1)]


func _character_texture(character_id: String, asset_name: String) -> Texture2D:
	var path := "res://assets/characters/%s/processed/ui/%s_%s.png" % [character_id, character_id, asset_name]
	return _texture(path)


func _texture(path: String) -> Texture2D:
	if texture_cache.has(path): return texture_cache[path]
	var resource := load(path)
	texture_cache[path] = resource if resource is Texture2D else null
	return texture_cache[path]


func _cover_rect(texture: Texture2D, rect: Rect2) -> Rect2:
	var scale_value := maxf(rect.size.x / texture.get_width(), rect.size.y / texture.get_height())
	var draw_size := texture.get_size() * scale_value
	return Rect2(rect.position + (rect.size - draw_size) * 0.5, draw_size)

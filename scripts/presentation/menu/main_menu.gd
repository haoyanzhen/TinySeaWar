extends Control

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


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	cover_character_id = _random_character_id()
	info_body = _mode_body()
	_create_buttons()
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


func _show_mode_select() -> void:
	info_title = "选择模式"
	info_body = _mode_body()
	queue_redraw()


func _show_operation_guide() -> void:
	info_title = "操作说明"
	info_body = "基础 UI：\n- 顶部左右为敌我舰队头像栏，头像下方显示生命状态。\n- 左下角是战术小地图，右侧是战斗日志和选中单位信息。\n- 底部操作槽显示 E / Q / F / V 的当前可用状态。\n\n键鼠操作：\n- 1-9 / 0 / -：切换己方角色槽位。\n- 鼠标左键：选择单位、设置集火目标、确认瞄准。\n- 鼠标右键：普通状态下移动，瞄准状态下取消。\n- E：主要武器瞄准；Q：切换 HE/AP；F：释放技能；V：跟踪镜头。\n- WASD：移动镜头；Space：暂停；Esc：取消当前操作。"
	queue_redraw()


func _show_game_intro() -> void:
	info_title = "游戏介绍"
	info_body = "Tiny Sea War 是开阔海域中的轻量 2D 舰队战。角色会自动航行、索敌并使用副武器，玩家负责关键角色轮换、主要武器瞄准、弹种切换、技能释放和集火目标选择。\n\n核心玩法：\n- 保持己方旗舰存活，同时寻找机会击沉敌方旗舰。\n- 通过 E 的手动主要武器抓住开火窗口，Q 切换合适弹种。\n- 使用 V 跟随关键角色，用小地图观察整体态势。\n\n胜利条件：\n- 击沉敌方旗舰立即胜利。\n- 时间耗尽时，按双方剩余总 HP 比例判定胜负。\n- 双方旗舰同一结算周期沉没时，当前规则判定玩家胜利。"
	queue_redraw()


func _mode_body() -> String:
	return "请选择本次出击模式。\n\n1v1：单舰对决，适合熟悉镜头、选择、主要武器瞄准和旗舰胜负。\n\n3v3：小队舰队战，适合练习角色槽位切换、集火目标、技能和小地图阅读。\n\n5v5：完整小舰队交战，覆盖潜艇、驱逐、巡洋、战列的混合威胁。\n\n11v11：大规模压力战，验证 1-9 / 0 / - 共 11 个操作槽、侦查密度、HUD 可读性和表现层性能。"


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
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(44.0, rect.size.y - 70.0), "Today's Cover: %s" % cover_character_id.capitalize(), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 88.0, 24, Color.WHITE)


func _draw_title_panel(rect: Rect2) -> void:
	_draw_panel(rect)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(26.0, 58.0), "Tiny Sea War", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 52.0, 44, TEXT_DARK)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(28.0, 100.0), "Open Sea Fleet Tactics Prototype", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 56.0, 20, TEXT_SOFT)
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

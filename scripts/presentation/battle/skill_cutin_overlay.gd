extends Control
## Pure presentation; receives only observer-filtered successful casts.
const DEFAULTS := {"enter_seconds":0.25, "hold_seconds":0.55, "exit_seconds":0.2, "compact_seconds":1.0, "width_ratio":0.25, "height_ratio":0.45, "compact_limit":3}
var settings := DEFAULTS.duplicate()
var mode := "full"
var running := false
var interacting := false
var full: Dictionary = {}
var compact: Array[Dictionary] = []
var textures := {}

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

func configure(values: Dictionary) -> void:
	for key in DEFAULTS:
		var value: float = float(values.get(key, DEFAULTS[key]))
		settings[key] = value if is_finite(value) and value > 0.0 else DEFAULTS[key]
	settings.width_ratio = minf(settings.width_ratio, 0.25)
	settings.height_ratio = minf(settings.height_ratio, 0.45)
	settings.compact_limit = clampi(int(settings.compact_limit), 1, 3)

func set_mode(value: String) -> void:
	mode = value if value in ["full", "simple", "off"] else "full"
	clear()

func clear(release_assets := false) -> void:
	full.clear()
	compact.clear()
	if release_assets: textures.clear()
	queue_redraw()

func sync_state(sea: Rect2, phase: String, busy: bool) -> void:
	position = sea.position
	size = sea.size
	running = phase == "Running"
	visible = running
	interacting = busy
	if not running:
		clear()
	elif busy and not full.is_empty():
		var item := full.duplicate()
		item.age = 0.0
		full.clear()
		_add_compact(item)
	queue_redraw()

func cache_units(units: Dictionary) -> void:
	for unit in units.values():
		cache_character(str(unit.get("definition_id", "")).trim_prefix("ship."))

func cache_character(character_id: String) -> void:
	if character_id.is_empty() or textures.has(character_id): return
	var portrait := _load_texture(character_id, "ui_portrait_small")
	if portrait == null: portrait = _load_texture(character_id, "ui_portrait")
	textures[character_id] = {"illustration":_load_texture(character_id, "illust_full_alpha"), "portrait":portrait}

func _load_texture(character_id: String, semantic: String) -> Texture2D:
	var path := DataRegistry.assets.character_ui_asset_path(character_id, semantic)
	return load(path) as Texture2D if not path.is_empty() and ResourceLoader.exists(path) else null

func present(request: Dictionary) -> void:
	if not running or mode == "off": return
	var item := request.duplicate()
	item.age = 0.0
	cache_character(str(item.get("character_id", "")))
	var assets: Dictionary = textures.get(str(item.get("character_id", "")), {})
	if mode == "full" and not interacting and full.is_empty() and assets.get("illustration") != null:
		full = item
	else:
		_add_compact(item)
	queue_redraw()

func _add_compact(item: Dictionary) -> void:
	compact.append(item)
	while compact.size() > int(settings.compact_limit): compact.pop_front()

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if not running or (full.is_empty() and compact.is_empty()): return
	if not full.is_empty():
		full.age += delta
		if full.age >= duration(): full.clear()
	for item in compact: item.age += delta
	compact = compact.filter(func(item): return item.age < float(settings.compact_seconds))
	if not full.is_empty() or not compact.is_empty() or delta > 0.0: queue_redraw()

func duration() -> float:
	return settings.enter_seconds + settings.hold_seconds + settings.exit_seconds

func full_rect() -> Rect2:
	var extent := Vector2(size.x * float(settings.width_ratio), size.y * float(settings.height_ratio))
	return Rect2(Vector2(size.x * 0.02, size.y * 0.3), extent)

func _draw() -> void:
	if not running: return
	if not full.is_empty():
		var rect := full_rect()
		var progress := clampf(float(full.age) / float(settings.enter_seconds), 0.0, 1.0)
		var eased := smoothstep(0.0, 1.0, progress)
		rect.position.x -= size.x * 0.02 * (1.0 - eased)
		var alpha := eased * clampf((duration() - float(full.age)) / float(settings.exit_seconds), 0.0, 1.0)
		_draw_illustration(full, rect, alpha)
	for index in range(compact.size()):
		var item: Dictionary = compact[index]
		var width := minf(440.0, size.x * 0.25)
		var x := 8.0 if item.get("faction_id", "") == "player" else size.x - width - 8.0
		_draw_compact(item, Rect2(Vector2(x, 8.0 + index * 62.0), Vector2(width, 56.0)))

func _draw_illustration(item: Dictionary, rect: Rect2, alpha: float) -> void:
	var texture: Texture2D = textures.get(str(item.get("character_id", "")), {}).get("illustration")
	if texture == null: return
	var scaled := texture.get_size() * minf(rect.size.x / texture.get_width(), rect.size.y / texture.get_height())
	# Preserve native alpha: no window, fill, frame, nameplate or mirror.
	draw_texture_rect(texture, Rect2(rect.get_center() - scaled * 0.5, scaled), false, Color(1, 1, 1, alpha))

func _draw_compact(item: Dictionary, rect: Rect2) -> void:
	var friendly := str(item.get("faction_id", "")) == "player"
	var accent := Color("#58c7ff") if friendly else Color("#ff7d74")
	draw_rect(rect, Color(0.025, 0.09, 0.15, 0.9))
	draw_rect(rect, accent, false, 2.0)
	var texture: Texture2D = textures.get(str(item.get("character_id", "")), {}).get("portrait")
	var text_x := rect.position.x + 12.0
	if texture != null:
		var image_area := Rect2(rect.position + Vector2(5, 5), Vector2(46, 46))
		var scaled := texture.get_size() * minf(image_area.size.x / texture.get_width(), image_area.size.y / texture.get_height())
		draw_texture_rect(texture, Rect2(image_area.get_center() - scaled * 0.5, scaled), false)
		text_x += 48.0
	var y := rect.position.y + 22.0
	var width := rect.end.x - text_x - 10.0
	var title := "%s · %s" % ["己方" if friendly else "敌方", item.get("character_name", "舰船")]
	_draw_text(title, Vector2(text_x, y), width, 17, accent)
	_draw_text(str(item.get("skill_name", "技能")), Vector2(text_x, y + 24), width, 16, Color.WHITE)

func _draw_text(value: String, at: Vector2, width: float, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var text := value
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		while text.length() > 0 and font.get_string_size(text + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width: text = text.left(-1)
		text += "…"
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, color)

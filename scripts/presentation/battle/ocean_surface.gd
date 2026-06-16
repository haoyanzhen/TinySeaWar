extends Node2D

const PALETTE_PATH := "res://data/environments/ocean_palettes.json"
const CLOUD_TEXTURE_PATH := "res://assets/environments/ocean/common/ocean_cloud_shadow_tile.png"
const WAVE_TEXTURE_PATH := "res://assets/environments/ocean/common/ocean_wave_highlight_tile.png"

var map_size := Vector2(4096.0, 2304.0)
var animation_time := 0.0
var animation_paused := false
var palettes := {}


func _ready() -> void:
	_load_palettes()
	queue_redraw()


func _process(delta: float) -> void:
	if not animation_paused:
		animation_time += delta
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter("animation_time", animation_time)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, map_size), Color.WHITE, true)


func configure(new_map_size: Vector2, palette_id: String) -> void:
	map_size = new_map_size
	if palettes.is_empty(): _load_palettes()
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter("map_size", map_size)
	set_palette(palette_id)
	queue_redraw()


func set_animation_paused(value: bool) -> void:
	animation_paused = value


func set_palette(palette_id: String) -> void:
	if palettes.is_empty(): _load_palettes()
	var palette: Dictionary = palettes.get(palette_id, palettes.get("day_clear", {}))
	if palette.is_empty() or not material is ShaderMaterial: return
	var shader_material := material as ShaderMaterial
	var base_texture_path := str(palette.get("base_texture", ""))
	if not base_texture_path.is_empty(): shader_material.set_shader_parameter("base_texture", load(base_texture_path))
	shader_material.set_shader_parameter("cloud_texture", load(CLOUD_TEXTURE_PATH))
	shader_material.set_shader_parameter("wave_texture", load(WAVE_TEXTURE_PATH))
	for parameter in ["deep_color", "surface_color", "shallow_color", "highlight_color", "cloud_color", "warm_reflection_color"]:
		shader_material.set_shader_parameter(parameter, Color(str(palette.get(parameter, "#ffffff"))))
	for parameter in ["wave_strength", "sparkle_strength", "cloud_opacity", "warm_reflection_strength", "animation_speed", "ai_texture_strength"]:
		shader_material.set_shader_parameter(parameter, float(palette.get(parameter, 0.0)))


func _load_palettes() -> void:
	var file := FileAccess.open(PALETTE_PATH, FileAccess.READ)
	if file == null:
		push_error("Cannot read ocean palettes: %s" % PALETTE_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("palettes")) != TYPE_DICTIONARY:
		push_error("Invalid ocean palette document: %s" % PALETTE_PATH)
		return
	palettes = parsed["palettes"]

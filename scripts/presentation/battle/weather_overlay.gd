extends Node2D

const PALETTE_PATH := "res://data/environments/ocean_palettes.json"
const WEATHER_TEXTURE_DEFAULTS := {
	"weather_cloud_texture": "res://assets/environment/weather/ocean_weather_cloudy_shadow_master.png",
	"foam_texture": "res://assets/environment/weather/ocean_weather_foam_wind_master.png",
	"rain_line_texture": "res://assets/environment/weather/ocean_weather_rain_lines_master.png",
	"rain_ripple_texture": "res://assets/environment/weather/ocean_weather_rain_ripples_master.png",
	"storm_shadow_texture": "res://assets/environment/weather/ocean_weather_storm_shadow_master.png",
	"lightning_mask_texture": "res://assets/environment/weather/ocean_weather_lightning_flash_master.png",
	"snow_flake_texture": "res://assets/environment/weather/ocean_weather_snow_flakes_master.png",
	"snow_haze_texture": "res://assets/environment/weather/ocean_weather_snow_haze_master.png",
}
const NUMERIC_PARAMETER_DEFAULTS := {
	"cloud_opacity": 0.0,
	"foam_strength": 0.0,
	"rain_strength": 0.0,
	"mist_strength": 0.0,
	"lightning_strength": 0.0,
	"cloud_scale": 1.0,
	"rain_angle": -0.55,
	"rain_density": 1.0,
	"rain_line_strength": 1.0,
	"rain_ripple_strength": 1.0,
	"squall_strength": 0.0,
	"snow_strength": 0.0,
	"snow_haze_strength": 0.0,
	"animation_speed": 1.0,
}

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
	if palettes.is_empty():
		_load_palettes()
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter("map_size", map_size)
	set_palette(palette_id)
	queue_redraw()


func set_animation_paused(value: bool) -> void:
	animation_paused = value


func set_palette(palette_id: String) -> void:
	if palettes.is_empty():
		_load_palettes()
	var palette: Dictionary = palettes.get(palette_id, palettes.get("day_clear", {}))
	if palette.is_empty() or not material is ShaderMaterial:
		return
	var shader_material := material as ShaderMaterial
	for parameter in WEATHER_TEXTURE_DEFAULTS.keys():
		var texture_path := str(palette.get(parameter, WEATHER_TEXTURE_DEFAULTS[parameter]))
		if not texture_path.is_empty():
			shader_material.set_shader_parameter(parameter, _texture(texture_path))
	for parameter in ["highlight_color", "cloud_color"]:
		shader_material.set_shader_parameter(parameter, Color(str(palette.get(parameter, "#ffffff"))))
	for parameter in NUMERIC_PARAMETER_DEFAULTS.keys():
		shader_material.set_shader_parameter(parameter, float(palette.get(parameter, NUMERIC_PARAMETER_DEFAULTS[parameter])))


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


func _texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var resource := load(path)
		if resource is Texture2D:
			return resource
	if not path.begins_with("res://"):
		return null
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK:
		return null
	return ImageTexture.create_from_image(image)

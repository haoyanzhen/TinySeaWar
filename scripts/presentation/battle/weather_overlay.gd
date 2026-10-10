extends Node2D

signal lightning_flashed

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
	"atmosphere_strength": 0.0,
	"weather_detail_scale": 1.0,
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
var lightning_speed := 1.0
var lightning_enabled := false
var lightning_above := false
var atmosphere_enabled := false
var detail_activity := 1.0
var detail_target := 1.0
var last_flash_event := -1


static func flash_start(cycle: int) -> float:
	# Presentation-only deterministic sequence, independent of battle RNG and wave speed.
	return float(cycle) * 12.0 + 2.0 + fposmod(float(cycle) * 1.61803398875, 1.0) * 3.0


static func flash_envelope(clock: float) -> float:
	var cycle := int(floor(clock / 12.0))
	var age := clock - flash_start(cycle)
	if age < 0.0 or age >= 0.36: return 0.0
	return smoothstep(0.0, 0.05, age) * (1.0 - smoothstep(0.14, 0.36, age))


func sync_readability(snapshot: Dictionary, camera_zoom: float, aiming: bool, aim: Vector2) -> void:
	if not material is ShaderMaterial: return
	var points := PackedVector2Array()
	var units: Dictionary = snapshot.get("units", {})
	for unit in units.values():
		if str(unit.get("life_state", "Alive")) != "Alive": continue
		points.append(unit.get("position", Vector2.ZERO))
		if points.size() == 24: break
	var count := points.size()
	points.resize(24)
	material.set_shader_parameter("focus_count", count)
	material.set_shader_parameter("focus_points", points)
	material.set_shader_parameter("focus_radius", 110.0 / maxf(camera_zoom, 0.01))
	material.set_shader_parameter("aim_active", aiming)
	material.set_shader_parameter("aim_position", aim)
	var projectile_count: int = snapshot.get("projectiles", {}).size()
	detail_target = lerpf(1.0, 0.55, clampf(float(projectile_count) / 24.0, 0.0, 1.0))



func _ready() -> void:
	_load_palettes()
	queue_redraw()


func _process(delta: float) -> void:
	if not animation_paused:
		animation_time += delta
	if atmosphere_enabled:
		var cycle := int(floor(animation_time / 12.0))
		if lightning_enabled and not animation_paused and animation_time >= flash_start(cycle) and last_flash_event != cycle:
			# Also catches low-frame-rate steps crossing the brief visible flash.
			if animation_time - flash_start(cycle) < maxf(delta, 0.36): lightning_flashed.emit()
			last_flash_event = cycle
	else:
		var above := lightning_enabled and sin(animation_time * lightning_speed * 0.73) > 0.97
		if above and not lightning_above and not animation_paused: lightning_flashed.emit()
		lightning_above = above
	if not animation_paused:
		detail_activity = move_toward(detail_activity, detail_target, delta * 0.65)
	if material is ShaderMaterial:
		material.set_shader_parameter("animation_time", animation_time)
		material.set_shader_parameter("lightning_flash", flash_envelope(animation_time) if atmosphere_enabled and lightning_enabled else 0.0)
		material.set_shader_parameter("detail_activity", detail_activity)



func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, map_size), Color.WHITE, true)


func configure(new_map_size: Vector2, palette_id: String) -> void:
	map_size = new_map_size
	animation_time = 0.0
	last_flash_event = -1
	lightning_above = false
	detail_activity = 1.0
	detail_target = 1.0
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
	atmosphere_enabled = float(palette.get("atmosphere_strength", 0.0)) > 0.0
	lightning_speed = float(palette.get("animation_speed", 1.0))
	lightning_enabled = float(palette.get("lightning_strength", 0)) > 0
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

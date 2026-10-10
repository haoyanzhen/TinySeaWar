extends RefCounted
# Test-only manifest resolver. Formal AssetCatalog and processed/ stay unchanged.
const MANIFEST = "res://reports/art/20261009-far-view/manifest.json"
var entries: Dictionary = {}
var textures: Dictionary = {}
func _init() -> void:
	if FileAccess.file_exists(MANIFEST):
		entries = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)).get("characters", {})
func has_character(id: String) -> bool:
	return entries.has(id) and texture(id,"body") != null and texture(id,"rig") != null
func texture(id: String, role: String) -> Texture2D:
	var key := id + ":" + role
	if textures.has(key): return textures[key]
	var info: Dictionary = entries.get(id, {}).get("roles", {}).get(role, {})
	if info.is_empty(): return null
	var source := Image.load_from_file(ProjectSettings.globalize_path("res://" + str(info.path)))
	if source == null: return null
	var a: Array = info.alpha_rect
	var cropped := source.get_region(Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3])))
	cropped.generate_mipmaps()
	textures[key] = ImageTexture.create_from_image(cropped)
	return textures[key]
func rig_width(id: String) -> float:
	return float(entries.get(id, {}).get("rig_width", 60.0))

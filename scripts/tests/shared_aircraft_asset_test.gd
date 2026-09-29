extends SceneTree

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog = root.get_node("DataRegistry").assets
	_check(catalog.errors.is_empty(), "asset catalog loads")
	for kind in ["fighter", "bomber", "torpedo_bomber", "scout", "asw"]:
		var visual: Dictionary = catalog.projectile_visual("aircraft." + kind)
		var path: String = visual.get("sprite", "")
		_check(path.ends_with("aircraft_%s_v2.png" % kind), "public sprite mapping: " + kind)
		_check(catalog.combat_vfx_asset_path("aircraft." + kind) == path, "public manifest agrees: " + kind)
		var texture = load(path) if not path.is_empty() else null
		_check(texture is Texture2D, "texture imports: " + kind)
		if texture is Texture2D:
			_check(texture.get_size() == Vector2(256, 256), "normalized canvas: " + kind)
		for key in ["trail_profile_id", "hit_profile", "fall_profile"]:
			_check(not catalog.vfx_playback_profile(visual.get(key, "")).is_empty(), "profile resolves: %s/%s" % [kind, key])
		if visual.has("payload_visual_id"):
			_check(not catalog.projectile_visual(visual["payload_visual_id"]).is_empty(), "payload resolves: " + kind)
	var cases := [
		["enterprise_cv6", "weapon.enterprise_airstrike", "bomber"],
		["argus", "weapon.argus_airstrike", "bomber"],
		["pobeda", "weapon.pobeda_bomber", "bomber"],
		["pobeda", "weapon.pobeda_ap_bomber", "bomber"],
		["hosho", "weapon.hosho_airstrike", "bomber"],
		["illustrious", "weapon.illustrious_bomber", "bomber"],
		["illustrious", "weapon.illustrious_scout", "scout"],
		["graf_zeppelin", "weapon.graf_zeppelin_bomber", "bomber"],
		["shokaku", "weapon.shokaku_bomber", "bomber"],
		["shokaku", "weapon.shokaku_torpedo_bomber", "torpedo_bomber"],
		["shokaku", "weapon.shokaku_scout", "scout"],
		["i_19", "weapon.i_19_scout", "scout"],
	]
	for entry in cases:
		var weapon: Dictionary = root.get_node("DataRegistry").registry.get_definition("weapons", entry[1])
		var mapping: Dictionary = catalog.weapon_visual(entry[0], entry[1])
		if mapping.is_empty():
			mapping = catalog.weapon_visual(entry[0], weapon.get("weapon_group_id", ""))
		_check(mapping.get("projectile_visual_id", "") == "visual.projectile.aircraft." + entry[2], "actual weapon maps to task type: " + entry[1])
	_check(catalog.weapon_visual("shokaku", "weapon.shokaku_torpedo_bomber").get("projectile_visual_id") != catalog.weapon_visual("shokaku", "shokaku_airstrike").get("projectile_visual_id"), "shared group does not erase torpedo override")
	for message in failures:
		push_error(message)
	print("Shared aircraft assets: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

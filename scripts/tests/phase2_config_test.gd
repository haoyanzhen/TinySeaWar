extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const AssetCatalog = preload("res://scripts/infrastructure/assets/asset_catalog.gd")
const UiText = preload("res://scripts/presentation/ui_text.gd")

const PHASE2_IDS := [
	"fletcher", "cleveland", "baltimore", "wahoo",
	"jervis", "belfast", "illustrious", "upholder",
	"tashkent", "chapayev", "gangut", "k_21",
	"z23", "nurnberg", "scharnhorst", "graf_zeppelin",
	"akizuki", "takao", "shokaku", "i_19",
	"yat_sen", "chang_chun", "dingyuan", "hai_lung",
]

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = ConfigRegistry.new()
	_check(registry.load_all(), "configuration registry loads: %s" % str(registry.errors))
	_check(registry.all("ships").size() == 48, "phase two extends the runtime roster to 48 ships")
	var assets = AssetCatalog.new()
	_check(assets.load_all(), "asset catalog and visual definitions load: %s" % str(assets.errors))
	var level_ship_ids := {}
	for level in registry.all("levels"):
		for fleet_name in ["player_fleet", "enemy_fleet"]:
			for member in level.get(fleet_name, []):
				level_ship_ids[str(member.get("ship_id", ""))] = true
	for character_id in PHASE2_IDS:
		var ship: Dictionary = registry.get_definition("ships", "ship.%s" % character_id)
		_check(not ship.is_empty(), "%s has runtime ship data" % character_id)
		_check(str(ship.get("asset_root", "")) == "res://assets/characters/%s/processed" % character_id, "%s exposes the canonical asset root" % character_id)
		_check(UiText.character_name(character_id) != "未知角色", "%s has a localized UI name" % character_id)
		_check(not level_ship_ids.has("ship.%s" % character_id), "%s does not change existing playable level rosters" % character_id)
		var skill: Dictionary = registry.get_definition("skills", str(ship.get("skill_id", "")))
		_check(not skill.is_empty(), "%s has a loadable runtime skill" % character_id)
		_check(str(skill.get("implementation_status", "")) in ["supported", "partial"], "%s declares skill implementation coverage" % character_id)
		for weapon_id in ship.get("weapon_mounts", []):
			var weapon: Dictionary = registry.get_definition("weapons", str(weapon_id))
			_check(not weapon.is_empty(), "%s resolves" % weapon_id)
			_check(not assets.weapon_visual(character_id, str(weapon.get("weapon_group_id", ""))).is_empty(), "%s has a weapon visual mapping" % weapon_id)
	if failures.is_empty():
		print("PASS: %d phase-two configuration checks" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d phase-two configuration checks" % [failures.size(), checks])
		quit(1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

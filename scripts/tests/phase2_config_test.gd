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
	var jervis_asw: Dictionary = assets.weapon_visual("jervis", "jervis_asw")
	_check(str(jervis_asw.get("launch_bind", "")) == "asw_launch_01", "Jervis ASW uses a stern ASW launch bind")
	_check(str(jervis_asw.get("muzzle_vfx_role", "")) == "water_splash", "Jervis ASW launch uses water-splash semantics")
	_check(str(jervis_asw.get("impact_vfx_role", "")) == "asw_underwater_blast", "Jervis ASW hit uses underwater-blast semantics")
	_check(not assets.vfx_playback_profile(str(jervis_asw.get("launch_profile", ""))).is_empty(), "Jervis ASW launch profile resolves")
	_check(not assets.vfx_playback_profile(str(jervis_asw.get("impact_profile", ""))).is_empty(), "Jervis ASW impact profile resolves")
	_check(not assets.vfx_role("jervis", "asw_underwater_blast").is_empty(), "Jervis ASW public impact role resolves")
	var jervis_asw_bind: Dictionary = assets.bind_point("jervis", "asw_launch_01")
	_check(str(jervis_asw_bind.get("asset_name", "")) == "jervis_battle_rig_base.png", "Jervis ASW bind resolves on the rig base")
	var tashkent_torpedo: Dictionary = assets.weapon_visual("tashkent", "tashkent_torpedo")
	_check(str(tashkent_torpedo.get("vfx_role_mappings", {}).get("torpedo_launch_flash", "")) == "torpedo.launch.surface", "Tashkent torpedo flash uses surface-launch semantics")
	var chapayev_main: Dictionary = assets.weapon_visual("chapayev", "chapayev_main")
	var chapayev_torpedo: Dictionary = assets.weapon_visual("chapayev", "chapayev_torpedo")
	_check(not chapayev_main.has("muzzle_vfx_role"), "Chapayev main guns do not misuse the AA burst as muzzle flash")
	_check(not chapayev_torpedo.has("muzzle_vfx_role"), "Chapayev torpedoes do not misuse the rectangular fire grid as launch flash")
	var gangut_main: Dictionary = assets.weapon_visual("gangut", "gangut_main")
	var gangut_secondary: Dictionary = assets.weapon_visual("gangut", "gangut_secondary")
	_check(not gangut_main.has("muzzle_vfx_role") and not gangut_secondary.has("muzzle_vfx_role"), "Gangut guns do not misuse the steel-line skill aura as muzzle flash")
	var k_21_torpedo: Dictionary = assets.weapon_visual("k_21", "k_21_torpedo")
	_check(str(k_21_torpedo.get("muzzle_vfx_role", "")) == "torpedo_launch_flash", "K-21 torpedoes use the authored launch-flash role")
	_check(str(k_21_torpedo.get("vfx_role_mappings", {}).get("torpedo_launch_flash", "")) == "torpedo.launch.submerged", "K-21 torpedo flash uses submerged-launch semantics")
	_check(not assets.bind_point("tashkent", "torpedo_mount_03").is_empty(), "Tashkent third torpedo mount bind resolves")
	_check(not assets.bind_point("chapayev", "turret_mount_04").is_empty(), "Chapayev fourth main-turret bind resolves")
	_check(not assets.bind_point("gangut", "secondary_mount_08").is_empty(), "Gangut eighth secondary-turret bind resolves")
	_check(not assets.bind_point("k_21", "torpedo_aft_mount_04").is_empty(), "K-21 fourth aft torpedo bind resolves")
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

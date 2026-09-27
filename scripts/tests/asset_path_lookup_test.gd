extends SceneTree

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog = root.get_node("DataRegistry").assets
	_check(catalog.errors.is_empty(), "catalog loads without errors")
	for character_id in catalog.characters:
		for semantic in ["ui_portrait", "illust_full_alpha"]:
			_check(ResourceLoader.exists(catalog.character_ui_asset_path(character_id, semantic)), "character UI exists: %s/%s" % [character_id, semantic])
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(catalog.MINIMAP_MANIFEST_PATH))
	for mask in manifest["masks"]:
		_check(catalog.minimap_asset_path(mask["terrain_definition_id"]) == mask["path"], "minimap resolves authored path")
	_check(catalog.character_ui_asset_path("missing", "ui_portrait").is_empty(), "unknown character returns empty")
	_check(catalog.character_ui_asset_path("warspite", "missing").is_empty(), "unknown role returns empty")
	_check(catalog.minimap_asset_path("terrain.map.missing").is_empty(), "unknown map returns empty")
	_check(catalog.ui_asset_path("ui.icon.torpedo", "2x") == catalog.ui_asset_path("ui_icon_torpedo", "2x"), "UI semantic alias retains export")
	_check(catalog._uses_only_shared_vfx(catalog.character("anshan")["configs"]["vfx"]), "shared VFX permits absent local directory")
	_check(not catalog._uses_only_shared_vfx({"roles": {}}), "empty VFX cannot bypass missing-directory validation")
	_check(not catalog._uses_only_shared_vfx({"roles": {"wake": {"file": "res://assets/vfx/combat/missing.png"}}}), "missing shared VFX cannot bypass validation")
	_check(not catalog._uses_only_shared_vfx({"roles": {"wake": {"file": catalog.character_ui_asset_path("anshan", "ui_portrait")}}}), "non-VFX resource cannot bypass validation")

	# An arbitrary catalog mapping must win over any filename inferred from the ID.
	var remapped_path: String = catalog.ui_asset_path("ui.icon.torpedo", "2x")
	catalog.characters["path_probe"] = {"ui_assets": {"ui_portrait": remapped_path}, "battle_assets": {"rig_base": remapped_path, "body_r": remapped_path}}
	var hud = load("res://scripts/presentation/battle/battle_hud.gd").new()
	var view = load("res://scripts/presentation/battle/prototype_battle.gd").new()
	_check(hud._portrait_texture({"definition_id": "ship.path_probe"}).resource_path == remapped_path, "portrait falls back through catalog without filename assumptions")
	var visuals: Dictionary = view._unit_visuals({"definition_id": "ship.path_probe"})
	_check(visuals["rig"].resource_path == remapped_path and visuals["body"].resource_path == remapped_path, "battle parts follow remapped catalog entries")
	_check(hud._texture("") == null and view._texture("") == null, "missing semantic skips resource loading")
	catalog.characters.erase("path_probe")
	hud.free()
	view.free()
	for failure in failures:
		push_error(failure)
	print("Asset path lookup: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

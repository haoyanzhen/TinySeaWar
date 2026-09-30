extends SceneTree

const Catalog = preload("res://scripts/infrastructure/data/ship_acquisition_catalog.gd")
var failures: Array[String] = []
var checks := 0

class MemoryStore extends RefCounted:
	var document := {}
	var writes := 0
	func save(_path: String, value: Dictionary) -> bool:
		document = value.duplicate(true)
		writes += 1
		return true
	func load_best(_path: String) -> Dictionary:
		return document.duplicate(true)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = root.get_node("DataRegistry").registry
	var catalog: Dictionary = registry.get_definition("progress", Catalog.CATALOG_ID)
	_check(registry.errors.is_empty(), "registry accepts complete catalog")
	var counts := {}
	for item in catalog.get("ships", []):
		counts[item["category"]] = int(counts.get(item["category"], 0)) + 1
	_check(counts == {"DefaultOwned": 3, "TutorialReward": 6, "ChallengeReward": 18, "Pending": 21}, "all 48 ships partitioned")
	var broken := catalog.duplicate(true)
	broken["ships"].remove_at(0)
	_check(not _validate(broken, registry).is_empty(), "missing ship rejected")
	broken = catalog.duplicate(true)
	broken["ships"].append(broken["ships"][0].duplicate())
	_check(not _validate(broken, registry).is_empty(), "duplicate membership rejected")
	broken = catalog.duplicate(true)
	broken["ships"][0]["category"] = "Unknown"
	_check(not _validate(broken, registry).is_empty(), "unknown category rejected")
	broken = catalog.duplicate(true)
	broken["ships"][0] = {"ship_id": broken["ships"][0]["ship_id"], "category": "Pending", "source_level_id": "level.tutorial.t01"}
	_check(not _validate(broken, registry).is_empty(), "pending cannot carry reward source")
	broken = catalog.duplicate(true)
	broken["ships"][0] = {"ship_id": broken["ships"][0]["ship_id"], "category": "TutorialReward", "source_level_id": "level.challenge.s01"}
	_check(not _validate(broken, registry).is_empty(), "reward source category mismatch rejected")
	broken = catalog.duplicate(true)
	broken.erase("planned_challenge_level_ids")
	_check(not _validate(broken, registry).is_empty(), "planned source list required")
	broken = catalog.duplicate(true)
	broken["ships"][0] = {"ship_id": broken["ships"][0]["ship_id"], "category": "TutorialReward", "source_level_id": "level.tutorial.missing"}
	_check(not _validate(broken, registry).is_empty(), "unknown reward source rejected")
	var flow = load("res://scripts/application/game_flow.gd").new()
	var store := MemoryStore.new()
	flow._progress_store = store
	flow._apply_loaded_progress({"schema_version": 1, "unlocked_ship_ids": ["ship.argus", "ship.akizuki", "ship.future"], "completed_challenge_level_ids": ["level.challenge.s01"]})
	_check(flow.is_ship_unlocked("ship.ward") and flow.is_ship_unlocked("ship.hosho"), "defaults merged into old save")
	_check(flow.is_ship_unlocked("ship.argus") and flow.is_ship_unlocked("ship.akizuki"), "legacy reward and pending ownership preserved")
	_check(not flow.is_ship_unlocked("ship.future"), "unknown future ship not playable")
	_check(flow.record_level_victory("level.tutorial.t01") and flow.is_ship_unlocked("ship.fletcher"), "tutorial reward follows catalog")
	_check("ship.future" in store.document.get("unlocked_ship_ids", []), "unknown ID preserved on next save")
	var before: int = flow.unlocked_ship_ids.size()
	flow.record_level_victory("level.tutorial.t01")
	_check(flow.unlocked_ship_ids.size() == before, "repeat victory idempotent")
	_check(flow.record_level_victory("level.challenge.s05"), "implemented challenge succeeds")
	for ship_id in ["ship.chongqing", "ship.yukikaze", "ship.hood", "ship.san_diego"]:
		_check(flow.is_ship_unlocked(ship_id), "chapter reward %s" % ship_id)
	_check(flow.record_level_victory("level.challenge.m01") and flow.is_ship_unlocked("ship.kirov"), "implemented medium challenge grants Kirov")
	var writes_before := store.writes
	_check(not flow.record_level_victory("level.challenge.missing"), "missing challenge cannot grant rewards")
	_check(not flow.record_level_victory("level.prototype_3v3"), "prototype cannot grant rewards")
	_check(flow.record_level_victory("level.tutorial.t08"), "reward-free tutorial succeeds without save")
	_check(store.writes == writes_before, "unimplemented and reward-free results do not write")
	_check(not flow.ship_acquisition_label("ship.kirov").contains("尚未开放"), "implemented source label truthful")
	_check(flow.ship_acquisition_label("ship.akizuki").contains("暂无获取途径"), "pending source label truthful")
	flow.free()
	var menu = load("res://scripts/presentation/menu/main_menu.gd").new()
	root.add_child(menu)
	menu._show_custom()
	_check(menu.ship_buttons.size() == 48, "menu lists complete roster")
	_check(menu.ship_buttons["ship.akizuki"].tooltip_text.contains("暂无获取途径"), "menu renders pending source")
	_check(not menu.ship_buttons["ship.kirov"].tooltip_text.contains("尚未开放"), "menu renders implemented reward source")
	menu.free()
	for failure in failures:
		push_error(failure)
	print("Ship acquisition: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)


func _validate(catalog: Dictionary, registry) -> Array[String]:
	return Catalog.validate(catalog, registry.definitions["ships"], registry.definitions["levels"])


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

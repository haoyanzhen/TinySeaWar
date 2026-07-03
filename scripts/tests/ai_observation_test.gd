extends SceneTree

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BattleSession = preload("res://scripts/application/battle_session.gd")
const AIObservation = preload("res://scripts/application/ai/ai_observation.gd")

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = ConfigRegistry.new()
	_check(registry.load_all(), "configuration registry loads")
	var session = BattleSession.new(registry)
	_check(session.create_battle("level.prototype_3v3", 20260630).get("ok", false), "3v3 observation fixture starts")
	var observer: Dictionary = session.state["units_by_id"]["unit.enemy.bismarck"]
	var visible: Dictionary = session.state["units_by_id"]["unit.player.aurora"]
	var hidden: Dictionary = session.state["units_by_id"]["unit.player.warspite"]
	session.state["visible_by_faction"]["enemy"] = {visible["entity_id"]: true}
	session.state["contacts_by_faction"]["enemy"] = {
		hidden["entity_id"]: {"unit_id": hidden["entity_id"], "visible": false, "last_known_position": Vector2(111.0, 222.0), "ghost_remaining": 4.0},
	}
	session.state["projectiles_by_id"] = {
		"projectile.hidden": {"entity_id": "projectile.hidden", "faction_id": "player", "position": Vector2(300.0, 300.0)},
		"projectile.known": {"entity_id": "projectile.known", "faction_id": "player", "position": Vector2(400.0, 300.0), "source_unit_id": hidden["entity_id"], "source_status_effects": [{"stat":"Damage"}], "attack_id":"secret.attack", "observed_raw_damage":420.0},
	}
	session.state["known_projectiles_by_faction"]["enemy"] = {"projectile.known": true}
	session.state["facilities_by_id"] = {
		"facility.hidden": {"facility_id": "facility.hidden", "faction_id": "player", "known_by_faction": ["player"]},
		"facility.known": {"facility_id": "facility.known", "faction_id": "neutral", "publicly_known": true},
	}
	session.state["minefields_by_id"] = {
		"mine.hidden": {"minefield_id": "mine.hidden", "owner_faction_id": "player", "known_by_faction": ["player"]},
		"mine.known": {"minefield_id": "mine.known", "owner_faction_id": "player", "known_by_faction": ["enemy"]},
	}
	var observation = AIObservation.from_battle_state(session.state, "enemy")
	_check(observation.friendly_units.size() == 3, "observation includes every friendly unit")
	_check(observation.visible_enemy_ids() == ["unit.player.aurora"], "observation includes only visible enemies")
	_check(observation.contact_ghosts.has(hidden["entity_id"]), "lost contact is retained only as a ghost")
	_check(observation.contact_ghosts[hidden["entity_id"]].get("last_known_position") == Vector2(111.0, 222.0), "ghost exposes the last known position")
	_check(observation.known_projectiles.has("projectile.known") and not observation.known_projectiles.has("projectile.hidden"), "unknown hostile projectile is excluded")
	_check(not observation.known_projectiles["projectile.known"].has("source_unit_id") and not observation.known_projectiles["projectile.known"].has("source_status_effects"), "hostile projectile does not reveal hidden launcher truth")
	_check(float(observation.known_projectiles["projectile.known"].get("observed_raw_damage", 0.0)) == 420.0, "hostile projectile retains only its observable damage potential")
	_check(observation.known_facilities.has("facility.known") and not observation.known_facilities.has("facility.hidden"), "unknown facility is excluded")
	_check(observation.known_minefields.has("mine.known") and not observation.known_minefields.has("mine.hidden"), "unknown minefield is excluded")
	visible["current_hp"] = 1.0
	_check(float(observation.visible_enemies[visible["entity_id"]]["current_hp"]) != 1.0, "observation is an immutable decision snapshot")
	session._ai_observations_by_faction.clear()
	var selected_before: Dictionary = session._select_target(observer)
	hidden["position"] = observer["position"]
	hidden["current_hp"] = 1.0
	hidden["is_flagship"] = true
	session._ai_observations_by_faction.clear()
	var selected_after: Dictionary = session._select_target(observer)
	_check(str(selected_before.get("entity_id", "")) == visible["entity_id"], "AI selects the sole observed enemy")
	_check(str(selected_after.get("entity_id", "")) == visible["entity_id"], "hidden truth changes cannot alter target selection")
	if failures.is_empty():
		print("PASS: %d AI observation checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("FAIL: %s" % failure)
		print("FAILED: %d of %d AI observation checks" % [failures.size(), checks])
		quit(1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

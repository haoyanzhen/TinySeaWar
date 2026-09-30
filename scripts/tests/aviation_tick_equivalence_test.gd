extends SceneTree
const Session = preload("res://scripts/application/battle_session.gd")
const Registry = preload("res://scripts/infrastructure/data/config_registry.gd")
const FIXTURE = "res://scripts/tests/fixtures/aviation_abstract_baseline.json"
func _init(): call_deferred("run")
func run():
	var registry = Registry.new()
	assert(registry.load_all())
	# Historical A-mode golden facts predate the 2026-09-30 balance multipliers.
	registry.definitions.settings["settings.combat"]["battle_multipliers"] = {"shell_speed":1.0, "shell_spread":1.0, "aircraft_speed":1.0}
	var legacy := "--capture-legacy" in OS.get_cmdline_user_args()
	var implementation = load("res://reports/aviation/20260929-runtime/battle_session_before.gd") if legacy else Session
	var expected: Dictionary = {} if legacy else JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var hashes := {}
	var failures := 0
	for palette in ["day_clear", "rain_night"]:
		for carrier in ["enterprise_cv6", "argus", "pobeda", "hosho", "illustrious", "graf_zeppelin", "shokaku"]:
			var s = implementation.new(registry)
			var level: Dictionary = registry.get_definition("levels", "level.prototype_1v1").duplicate(true)
			level.player_fleet[0].ship_id = "ship." + carrier
			level.player_fleet[0].position = [1700.0, 1100.0]
			level.enemy_fleet[0].position = [2350.0, 1100.0]
			level.map.ocean_palette = palette
			s.create_battle_from_definition(level, 2910)
			s.configure_full_ai_factions(["player", "enemy"])
			var facts: Array = []
			for tick in range(150):
				for event in s.advance_tick(0.1):
					if str(event.event_type).begins_with("Aviation"): continue
					var fact: Dictionary = event.duplicate(true)
					normalize(fact)
					facts.append(fact)
				if "--no-snapshots" not in OS.get_cmdline_user_args(): s.snapshot("player")
			var units := {}
			for id in s.state.units_by_id:
				var unit: Dictionary = s.state.units_by_id[id]
				units[id] = {"hp":unit.current_hp, "position":unit.position, "weapons":unit.weapon_states, "life":unit.life_state}
			facts.append({"rng":s.random_source._random.state, "entities":s._entity_sequence, "units":units, "result":s.state.get("result", {})})
			var key: String = carrier + "/" + palette
			if carrier == "enterprise_cv6" and palette == "day_clear": FileAccess.open("res://reports/aviation/20260929-runtime/tick-" + ("before" if legacy else "after") + ".txt", FileAccess.WRITE).store_string(var_to_str(facts))
			hashes[key] = {"sha256":var_to_str(facts).sha256_text(), "facts":facts.size()}
			if not legacy and hashes[key].sha256 != expected.get(key, {}).get("sha256", ""):
				push_error("Tick equivalence differs: " + key)
				failures += 1
	if legacy: FileAccess.open(FIXTURE,FileAccess.WRITE).store_string(JSON.stringify(hashes,"\t") + "\n")
	print("Aviation full Tick equivalence: ", hashes.size(), " cases, ", failures, " failures, legacy=",legacy)
	quit(0 if failures == 0 else 1)

func normalize(value) -> void:
	if value is Dictionary:
		for key in value.keys():
			# Wall-clock profiling is not a deterministic rule fact.
			if str(key) == "event_id" or str(key).ends_with("_usec"): value.erase(key)
			else: normalize(value[key])
	elif value is Array:
		for item in value: normalize(item)

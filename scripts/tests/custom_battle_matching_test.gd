extends SceneTree

const Registry = preload("res://scripts/infrastructure/data/config_registry.gd")
const Catalog = preload("res://scripts/infrastructure/data/custom_battle_catalog.gd")
const Matcher = preload("res://scripts/application/custom_battle_matcher.gd")
const Session = preload("res://scripts/application/battle_session.gd")
var checks := 0
var failures: Array[String] = []

func _init() -> void: call_deferred("_run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var registry = Registry.new()
	check(registry.load_all(), "registry loads: " + str(registry.errors))
	var matcher = Matcher.new(registry)
	var pool: Array = registry.all("custom_rosters")
	check(pool.size() == 112, "112 registered rosters")
	var settings: Dictionary = registry.get_definition("custom_matching", Catalog.MATCHING_ID)
	for mutation in ["missing", "duplicate", "flagship", "size", "budget", "shape", "fraction", "set", "id"]:
		var bad: Array = pool.duplicate(true)
		match mutation:
			"missing": bad[0].ship_ids[0] = "ship.missing"
			"duplicate": bad[50].ship_ids[1] = bad[50].ship_ids[0]
			"flagship": bad[0].flagship_ship_id = ""
			"size": bad[0].unit_count = 5
			"budget": bad[0].ship_ids = ["ship.yamato", "ship.bismarck", "ship.warspite"]; bad[0].unit_count = 3; bad[0].flagship_ship_id = "ship.yamato"
			"shape": bad[0].ship_ids = "invalid"
			"fraction": bad[0].unit_count = 1.5
			"set": bad[1].ship_ids = bad[0].ship_ids.duplicate(); bad[1].flagship_ship_id = bad[0].flagship_ship_id
			"id": bad[1].id = bad[0].id
		check(not Catalog.validate(bad, settings, registry.definitions.ships, registry.definitions.ai_profiles).is_empty(), "reject invalid roster " + mutation)
	var wrong_policy := settings.duplicate(true)
	wrong_policy.difficulties.Hard.enemy_ai_profile_id = "ai.profile.easy"
	check(not Catalog.validate(pool, wrong_policy, registry.definitions.ships, registry.definitions.ai_profiles).is_empty(), "reject mismatched AI difficulty")
	var maps: Array = registry.all("levels").filter(func(level): return str(level.id).begins_with("level.prototype_") and str(level.id).ends_with("_3v3") and not str(level.map.get("terrain_definition_id", "")).is_empty())
	var flow = root.get_node("GameFlow")
	var unlocks: Array[String] = flow.unlocked_ship_ids.duplicate()
	flow.unlocked_ship_ids.assign(registry.all("ships").map(func(ship): return str(ship.id)))
	var map_placements := 0
	for roster in pool:
		for level in maps:
			for faction in ["player", "enemy"]:
				check(matcher.spawns_legal(roster.ship_ids, flow._custom_spawn_slots(level, faction), level.map), "legal spawns " + str(roster.id) + " " + str(level.id) + " " + faction)
				map_placements += 1
		var base_id := "level.prototype_%dv%d" % [int(roster.unit_count), int(roster.unit_count)]
		var base: Dictionary = registry.get_definition("levels", base_id)
		check(matcher.spawns_legal(roster.ship_ids, flow._custom_spawn_slots(base, "enemy"), base.map), "open sea roster legal " + str(roster.id))
	# Reproduce the design's complete reachable budget coverage without running battles.
	var reachable := {0:{0:true}}
	for ship in registry.all("ships"):
		for count in range(11, 0, -1):
			if not reachable.has(count): reachable[count] = {}
			for cost in reachable.get(count - 1, {}):
				if cost + int(ship.cost) <= 64: reachable[count][cost + int(ship.cost)] = true
	var interval_count := 0
	for count in Catalog.SCALES:
		var base: Dictionary = registry.get_definition("levels", "level.prototype_%dv%d" % [count,count])
		var slots: Array = flow._custom_spawn_slots(base, "enemy")
		for cost in reachable[count]:
			if cost > Catalog.SCALES[count]: continue
			for difficulty in ["Easy", "Standard", "Hard"]:
				var result: Dictionary = matcher.choose(count, cost, difficulty, slots, base.map, 42)
				check(result.ok and result.enemy_cost >= result.lower and result.enemy_cost <= result.upper, "covered budget %d/%d/%s" % [count, cost, difficulty])
				interval_count += 1
	check(interval_count == 282, "all 282 legal intervals")
	var base: Dictionary = registry.get_definition("levels", "level.prototype_3v3")
	var slots: Array = flow._custom_spawn_slots(base, "enemy")
	var histogram := {}
	for seed_value in range(1000):
		var result: Dictionary = matcher.choose(3, 12, "Standard", slots, base.map, seed_value)
		check(result.ok and str(result.roster.id) in result.candidate_ids, "draw never leaves eligible set")
		histogram[result.roster.id] = int(histogram.get(result.roster.id, 0)) + 1
	var first: Dictionary = matcher.choose(3, 12, "Standard", slots, base.map, 42)
	check(histogram.size() == first.candidate_count, "all eligible rosters sampled")
	for tally in histogram.values(): check(absf(float(tally) - 1000.0 / first.candidate_count) < 60, "seed sample distribution")
	var other_players: Array[String] = ["ship.chapayev", "ship.cleveland", "ship.san_diego"]
	check(matcher.choose(3, matcher.fleet_cost(other_players), "Standard", slots, base.map, 42).candidate_ids == first.candidate_ids, "same cost different ships keeps same candidates")
	check(matcher.cost_interval(3, 19, "Standard").lower != first.lower, "actual player cost changes budget")
	check(first.roster.id == matcher.choose(3, 12, "Standard", slots, base.map, 42).roster.id, "same seed deterministic")
	check(not matcher.choose(3, 12, "Invalid", slots, base.map, 42).ok, "reject unknown difficulty")
	check(not matcher.choose(3, 12, "Standard", [], base.map, 42).ok, "empty spawn pool refuses fallback")
	var player: Array[String] = ["ship.shimakaze", "ship.yukikaze", "ship.aurora"]
	var previous: Dictionary = flow.runtime_level_definition("level.custom_runtime")
	var preview: Dictionary = flow.configure_custom_battle(base.id, base.id, "clear_day", player, "", "Hard", 52, 73, true)
	check(preview.ok and flow.runtime_level_definition("level.custom_runtime") == previous, "preview does not commit runtime state")
	var configured: Dictionary = flow.configure_custom_battle(base.id, base.id, "clear_day", player, "", "Hard", 52, 73)
	check(configured.ok and configured.level.enemy_fleet == preview.level.enemy_fleet, "preview matches committed fleet")
	check(configured.level.enemy_ai_profile_id == "ai.profile.hard", "difficulty selects AI profile")
	check(registry.get_definition("levels", "level.custom_runtime").is_empty(), "isolated runtime definition")
	var session = Session.new(registry)
	check(session.create_battle_from_definition(configured.level, 73).ok, "custom session starts")
	var initial: Dictionary = session.state.duplicate(true)
	for tick in range(10): session.advance_tick(0.1)
	var restarted = Session.new(registry)
	check(restarted.create_battle_from_definition(flow.runtime_level_definition("level.custom_runtime"), 73).ok and restarted.state == initial, "restart restores identical initial state and seed")
	check(session.state.custom_match.roster_id == configured.roster.id, "session stores match diagnostics")
	var duplicate: Array[String] = ["ship.ward", "ship.ward", "ship.ward"]
	check(not flow.configure_custom_battle(base.id, base.id, "clear_day", duplicate).ok, "duplicate player rejected")
	var overspend: Array[String] = ["ship.yamato", "ship.bismarck", "ship.warspite"]
	check(not flow.configure_custom_battle(base.id, base.id, "clear_day", overspend).ok, "overspend rejected in Application")
	flow.unlocked_ship_ids.assign(["ship.ward"])
	check(not flow.configure_custom_battle(base.id, base.id, "clear_day", player).ok, "locked player rejected")
	flow.unlocked_ship_ids.assign(registry.all("ships").map(func(ship): return str(ship.id)))
	check(not flow.record_level_victory("level.custom_runtime"), "custom victory cannot write progress")
	var menu = load("res://scenes/menu/main_menu.tscn").instantiate()
	root.add_child(menu)
	menu.selected_ship_ids.assign(player)
	menu._show_custom()
	check(menu.custom_difficulty_selector.item_count == 3 and menu.custom_preview.ok, "menu difficulty and preview available")
	menu.custom_difficulty_selector.select(2)
	menu.custom_difficulty_selector.item_selected.emit(2)
	check(menu.custom_preview.difficulty == "Hard" and menu.custom_enemy_summary.text.contains("困难"), "menu difficulty updates range and preview")
	var old_battle_seed := int(menu.custom_preview.battle_seed)
	menu._reroll_custom_enemy()
	check(menu.custom_preview.ok and not menu.custom_start_button.disabled, "reroll creates valid preview")
	check(menu.custom_preview_key != "" and int(menu.custom_preview.battle_seed) == old_battle_seed, "reroll preserves combat seed")
	menu.queue_free()
	var battle = load("res://scenes/battle/prototype_battle.tscn").instantiate()
	root.add_child(battle)
	battle.set_process(false)
	check(battle.session.state.battle_seed == 73, "actual scene uses frozen combat seed")
	var actual_roster: Array = battle.session.state.units_by_id.values().filter(func(unit): return unit.faction_id == "enemy").map(func(unit): return unit.definition_id)
	battle._restart_battle()
	battle.set_process(false)
	check(battle.session.state.battle_seed == 73 and actual_roster == battle.session.state.units_by_id.values().filter(func(unit): return unit.faction_id == "enemy").map(func(unit): return unit.definition_id), "actual restart preserves roster and seed")
	battle.queue_free()
	await process_frame
	flow.unlocked_ship_ids.assign(unlocks)
	print("CUSTOM_MATCHING %d/%d; placements=%d; intervals=%d; histogram=%s" % [checks-failures.size(),checks,map_placements,interval_count,histogram])
	for failure in failures: print("FAIL " + failure)
	quit(0 if failures.is_empty() else 1)

extends SceneTree
const Registry = preload("res://scripts/infrastructure/data/config_registry.gd")
const Session = preload("res://scripts/application/battle_session.gd")
const Tuning = preload("res://scripts/domain/services/combat_tuning_service.gd")
const Facility = preload("res://scripts/domain/services/facility_service.gd")
var checks := 0
var failures: Array = []
var registry
func _init(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message)
func fixture(mode := "Abstract"):
	var s = Session.new(registry)
	var level: Dictionary = registry.get_definition("levels", "level.prototype_1v1").duplicate(true)
	level.aviation_rules_mode = mode
	check(s.create_battle_from_definition(level, 93030).get("ok", false), "fixture")
	s.state.units_by_id["unit.player.warspite"].position = Vector2(400, 400)
	s.state.units_by_id["unit.enemy.bismarck"].position = Vector2(1000, 400)
	return s
func check_flights(s, weapon: Dictionary, skill := false):
	check(not s.delayed_attacks.is_empty(), "attacks created")
	for attack in s.delayed_attacks:
		var duration: float = float(attack.resolve_at_time) - float(attack.get("launch_at_time", s.state.elapsed_time))
		var expected: float = (attack.origin as Vector2).distance_to(attack.target_position) / s.get_weapon_flight_speed(weapon)
		if weapon.mount_type == "Aviation": expected *= s._aviation_delay_multiplier(attack.origin, attack.target_position)
		check(is_equal_approx(duration, expected), "flight time shared: " + weapon.id)
func run():
	registry = Registry.new()
	check(registry.load_all(), "load registry")
	var settings: Dictionary = registry.get_definition("settings", "settings.combat")
	for weapon in registry.all("weapons"):
		var speed: float = weapon.get("projectile_speed", 1.0)
		var spread: float = weapon.get("spread", 0.0)
		var factor := 2.0 if weapon.mount_type == "Aviation" else (1.5 if weapon.mount_type in ["Gun", "AntiAir"] else 1.0)
		check(is_equal_approx(Tuning.weapon_flight_speed(weapon, settings), speed * factor), "speed: " + weapon.id)
		check(is_equal_approx(Tuning.weapon_spread(weapon, settings), spread * (0.5 if weapon.mount_type in ["Gun", "AntiAir"] else 1.0)), "spread: " + weapon.id)
		check(Tuning.weapon_flight_speed(weapon, {}) == speed, "missing settings means identity")
	var gun: Dictionary = registry.get_definition("weapons", "weapon.warspite_381_ap")
	var aircraft: Dictionary = registry.get_definition("weapons", "weapon.enterprise_airstrike")
	check(Tuning.weapon_flight_speed(gun, settings) == 315, "Warspite AP 210 -> 315")
	check(Tuning.weapon_flight_speed(aircraft, settings) == 180, "Enterprise 90 -> 180")
	for mode in ["Abstract", "Physical"]:
		for weapon in [gun, aircraft]:
			for auto_fire in [false, true]:
				var s = fixture(mode)
				var source: Dictionary = s.state.units_by_id["unit.player.warspite"]
				var target: Dictionary = s.state.units_by_id["unit.enemy.bismarck"]
				if auto_fire: s._fire_weapon(source, target, source.weapon_states[0], weapon)
				else: s._fire_weapon_at_position(source, target.position, source.weapon_states[0], weapon, true)
				check_flights(s, weapon)
				if weapon.mount_type == "Aviation":
					var wave: Dictionary = s.aviation_projection.waves.values()[0]
					var middle: float = (float(wave.launch_at_time) + float(wave.resolve_at_time)) / 2.0
					var active := {}
					for a in s.delayed_attacks: active[a.attack_id] = true
					s.aviation_projection.advance(middle, s.state.units_by_id, active)
					check(is_equal_approx(wave.progress, 0.5), "plane presentation uses same accelerated arrival")
					if mode == "Physical":
						var physical: Dictionary = s.aviation_service.waves.values()[0]
						check(is_equal_approx(physical.resolve_at_time, wave.resolve_at_time), "Physical and projection share arrival")
			var skill_session = fixture(mode)
			var source: Dictionary = skill_session.state.units_by_id["unit.player.warspite"]
			skill_session._queue_skill_attack(source, {"id":"skill.test"}, {"weapon_id":weapon.id,"waves":2,"wave_interval":2.0,"charge_time":1.0}, Vector2(1000,400), {})
			check_flights(skill_session, weapon, true)
			check(is_equal_approx(float(skill_session.delayed_attacks[0].launch_at_time), 1.0), "skill charge is not accelerated")
	var s = fixture()
	var source: Dictionary = s.state.units_by_id["unit.player.warspite"]
	var aim := Vector2(1480,400)
	var spread: Dictionary = s._sample_gun_impact(source.position, aim, gun)
	check(is_equal_approx(spread.lateral_sigma, 75.0) and is_equal_approx(spread.longitudinal_sigma, 37.5), "both dispersion sigmas halved")
	check(s.get_primary_aim_status(source.entity_id, aim).spread_degrees == 7.0, "HUD exposes tuned spread")
	check(s._automatic_attack_speed(source, gun) == 315, "AI intercept speed tuned")
	var unmodified := gun.duplicate(true)
	s.get_weapon_flight_speed(gun)
	s.get_weapon_flight_speed(gun)
	check(gun == unmodified and gun.projectile_speed == 210, "no repeated multiplication or definition mutation")
	s.delayed_attacks.clear()
	s._fire_facility_weapon({"facility_id":"test.coast","faction_id":"player","position":Vector2(400,400)}, s.state.units_by_id["unit.enemy.bismarck"], gun)
	check_flights(s, gun)
	check(s.presentation_context().combat_settings == settings, "presentation receives session multipliers")
	for bad in [0, -1, INF, NAN, "2", true]:
		var invalid := settings.duplicate(true)
		invalid.battle_multipliers.shell_speed = bad
		registry.errors.clear()
		registry._validate_combat_settings(invalid)
		check(not registry.errors.is_empty(), "reject invalid multiplier: " + str(bad))
	registry.errors.clear()
	var invalid := settings.duplicate(true)
	invalid.battle_multipliers = []
	registry._validate_combat_settings(invalid)
	check(not registry.errors.is_empty(), "reject non-object multipliers")
	test_support()
	for message in failures: push_error(message)
	print("Combat tuning: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
func test_support():
	var f = Facility.new()
	f.definitions_by_id = {"airport":{"capabilities":["SupportMissionProvider"],"support_mission_ids":["air"]}, "air":{"mission_type":"Airstrike","launch_time":2.0,"arrival_time":10.0,"max_range":1000,"cooldown":0,"charges":1}}
	f.facilities_by_id = {"port":{"facility_id":"port","definition_id":"airport","operation_state":"Active","life_state":"Alive","faction_id":"player","position":Vector2.ZERO,"cooldown_remaining":0.0,"mission_charges_remaining":{"air":1}}}
	var result: Dictionary = f.request_support("port", "air", "player", Vector2(500,0), 10.0, {"aviation_delay_multiplier":1.3}, 2.0)
	check(result.get("accepted", false), "support accepted")
	if not f.support_missions.is_empty():
		var task: Dictionary = f.support_missions[0]
		check(task.launch_at_time == 12.0 and task.resolve_at_time == 17.5, "weather flight halved while preparation preserved")

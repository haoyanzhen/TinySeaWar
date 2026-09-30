extends SceneTree
const Session = preload("res://scripts/application/battle_session.gd")
const Service = preload("res://scripts/domain/services/aviation_service.gd")
const Registry = preload("res://scripts/infrastructure/data/config_registry.gd")
var registry
var checks := 0
var failures: Array = []
func _init(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message)
func fixture(mode := "Physical"):
	var s = Session.new(registry)
	var level: Dictionary = registry.get_definition("levels", "level.prototype_1v1").duplicate(true)
	level.aviation_rules_mode = mode
	check(s.create_battle_from_definition(level, 2910).get("ok", false), "fixture loads")
	var source: Dictionary = s.state.units_by_id["unit.player.warspite"]
	var target: Dictionary = s.state.units_by_id["unit.enemy.bismarck"]
	source.position = Vector2(400, 400)
	source.definition_id = "ship.enterprise_cv6"
	source.stats.aviation_power = 120.0
	target.position = Vector2(900, 400)
	target.current_hp = target.max_hp
	target.weapon_states = [{"definition_id":"weapon.enterprise_aa", "enabled":true, "reload_remaining":0.0}]
	source.skill_state.cooldown_remaining = 0.0
	s.state.visible_by_faction.player = {target.entity_id:true}
	return s
func launch(s, id := "weapon.enterprise_airstrike"):
	var source: Dictionary = s.state.units_by_id["unit.player.warspite"]
	var target: Dictionary = s.state.units_by_id["unit.enemy.bismarck"]
	s._fire_weapon_at_position(source, target.position, source.weapon_states[0], registry.get_definition("weapons", id), true)
func time(s, value: float):
	s.state.elapsed_time = value
	s.state.tick_index = int(value * 10)
	s._resolve_delayed_attacks()
func run():
	registry = Registry.new()
	check(registry.load_all(), "registry")
	test_round()
	test_runtime()
	test_torpedo()
	test_observation()
	test_recon()
	test_coast_and_support()
	for message in failures: push_error(message)
	print("Aviation runtime: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
func test_round():
	var service = Service.new()
	var targets := {}
	for id in ["a", "b", "outside", "friendly", "hidden"]:
		targets[id] = {"phase":"Flying", "current_hp":350.0, "max_hp":350.0, "faction_id":"player" if id == "friendly" else "enemy", "position":Vector2(101 if id == "outside" else 100, 0)}
	var events: Array = service.fire_round("aa", "player", Vector2.ZERO, 100, 75, targets, {"a":true, "b":true, "outside":true, "friendly":true})
	check(events.filter(func(e): return e.event_type == "AntiAirFired").size() == 1, "one firing fact for a round")
	check(targets.a.current_hp == 275 and targets.b.current_hp == 275, "full damage to every in-range wave, inclusive boundary")
	for id in ["outside", "friendly", "hidden"]: check(targets[id].current_hp == 350, "excluded " + id)
	service.fire_round("aa2", "player", Vector2.ZERO, 100, 400, targets, {"a":true, "b":true})
	check(targets.a.phase == "Destroyed" and targets.b.phase == "Destroyed", "overlap kills every wave")
	check(service.payload_ratio({"current_hp":0, "max_hp":350, "damage_floor":0.5}) == 0, "damage floor cannot resurrect destroyed wave")
	check(service.payload_ratio({"current_hp":1, "max_hp":350, "damage_floor":0.5}) == 0.5, "living wave floor")
func test_runtime():
	var s = fixture()
	launch(s)
	launch(s)
	for wave in s.aviation_service.waves.values():
		wave.max_hp = 10000.0
		wave.current_hp = 10000.0
	var flight_midpoint: float = s.aviation_service.waves.values()[0].resolve_at_time * 0.5
	time(s, flight_midpoint)
	var tasks: Array = s.aviation_service.waves.values()
	check(tasks.size() == 2, "same tick launches have distinct wave IDs")
	check(tasks[0].current_hp == tasks[1].current_hp, "all waves receive identical full round")
	check(tasks[0].current_hp < tasks[0].max_hp, "real AA reduces airborne HP")
	var hp: float = tasks[0].current_hp
	time(s, flight_midpoint + 0.1)
	check(tasks[0].current_hp == hp, "reload prevents repeated AA")
	check(s.delayed_attacks.size() > 0, "in flight has no damage settlement")
	var no_aa = fixture()
	no_aa.state.units_by_id["unit.enemy.bismarck"].weapon_states.clear()
	launch(no_aa)
	time(no_aa, 20)
	check(no_aa.delayed_attacks.is_empty(), "surviving bombs settle once")
	check(no_aa._event_buffer.any(func(e): return e.event_type == "AttackResolved"), "bomb results exist")
	var count: int = no_aa._event_buffer.filter(func(e): return e.event_type == "AttackResolved").size()
	time(no_aa, 21)
	check(no_aa._event_buffer.filter(func(e): return e.event_type == "AttackResolved").size() == count, "bomb results never repeat")
	var killed = fixture()
	killed.state.units_by_id["unit.enemy.bismarck"].stats.anti_air_power = 100000
	launch(killed)
	time(killed, 20)
	check(killed.delayed_attacks.is_empty(), "arrival-tick lethal AA cancels payload")
	check(not killed._event_buffer.any(func(e): return e.event_type == "AttackResolved"), "destroyed wave has no bomb damage")
func test_torpedo():
	var s = fixture()
	s.state.units_by_id["unit.enemy.bismarck"].weapon_states.clear()
	launch(s, "weapon.shokaku_torpedo_bomber")
	time(s, 4)
	check(s.state.projectiles_by_id.size() == 6, "one real torpedo per payload")
	check(s.delayed_attacks.is_empty(), "no old delayed air torpedo damage")
	check(not s._event_buffer.any(func(e): return e.event_type == "AttackResolved"), "drop does not cause damage")
	var projectile: Dictionary = s.state.projectiles_by_id.values()[0]
	check(projectile.position.distance_to(Vector2(900, 400)) >= 179, "fixed standoff, never spawn at target")
	check(projectile.target_types.has("Submerged"), "retains declared submarine legality")
	check(projectile.remaining_range == 360, "independent water range")
	check(projectile.damage_multiplier == 1, "unharmed payload only one HP factor")
	check(s._visible_projectiles("enemy", false).is_empty(), "unknown torpedoes hidden")
	s._update_projectile_observation()
	var seen: Dictionary = s._visible_projectiles("enemy", false)
	for item in seen.values(): check(not item.has("source_weapon_id") and not item.has("aviation_wave_id"), "torpedo does not reveal carrier")
	for i in range(60): s._update_projectiles(0.1)
	check(s.state.projectiles_by_id.is_empty(), "public collision/range removes payloads")
	check(s._event_buffer.any(func(e): return e.event_type == "ProjectileHit"), "physical torpedoes can collide")
	var results: Array = s._event_buffer.filter(func(e): return e.event_type == "AttackResolved")
	check(results.size() <= 6, "at most one damage result per torpedo")
	for event in results: check(event.damage_result.hit_reason == "COLLISION", "public forced-hit semantics")
func test_observation():
	var s = fixture()
	# Observe a live wave independently of how quickly it enters an AA kill zone.
	s.state.units_by_id["unit.enemy.bismarck"].weapon_states.clear()
	launch(s)
	time(s, 1)
	s.state.visible_by_faction.enemy = {}
	var enemy: Dictionary = s.snapshot("enemy").aviation
	check(not enemy.is_empty(), "aircraft independently visible without carrier")
	for wave in enemy.values():
		for key in ["source_unit_id", "source_weapon_id", "character_id", "target_position", "spawn_position", "attack_ids", "remaining"]: check(not wave.has(key), "enemy projection redacts " + key)
	s.state.units_by_id["unit.enemy.bismarck"].position = Vector2(4000, 3000)
	time(s, 1.1)
	check(s.snapshot("enemy").aviation.is_empty(), "lost segment is removed")
	check(s._ai_observation_for("enemy").visible_aircraft.is_empty(), "AI shares lost visibility")
	var raw := [{"event_id":"secret", "event_type":"AttackResolved", "damage_result":{"attack_id":"a", "damage_type":"Aviation", "source_unit_id":"unit.player.warspite", "source_weapon_id":"weapon.enterprise_airstrike", "source_weapon_group_id":"enterprise_airstrike", "source_skill_id":"secret", "target_unit_id":"unit.enemy.bismarck", "impact_position":Vector2(4000,3000), "hit":true, "final_damage":10}}]
	var filtered: Array = s.presentation_events(raw, "enemy")
	check(filtered.size() == 1, "own incoming hit remains visible")
	for key in filtered[0].damage_result: check(not str(key).begins_with("source_"), "anonymous result removes " + str(key))
	s.state.visible_by_faction.player = {}
	var hidden_feedback: Array = s.presentation_events(raw, "player")
	check(hidden_feedback.size() == 1 and hidden_feedback[0].event_type == "AviationArrival" and not hidden_feedback[0].has("damage_result"), "own hidden hit reveals only committed arrival")
	var miss: Array = raw.duplicate(true)
	miss[0].damage_result.target_unit_id = ""
	miss[0].damage_result.hit = false
	check(s.presentation_events(miss, "player") == hidden_feedback, "hidden hit and miss cannot become an information oracle")
func test_recon():
	var s = fixture()
	s.state.skill_effects_by_id["recon"] = {"effect_type":"Reconnaissance", "source_unit_id":"unit.player.warspite", "source_skill_id":"test", "faction_id":"player", "position":Vector2(900,400), "current_hp":1.0, "max_hp":1.0, "remaining":20.0, "destroyed_cooldown_penalty":5.0}
	s._update_support_effects(0.1)
	check(s.state.skill_effects_by_id.recon.current_hp == 1, "old recon DPS disabled in physical mode")
	time(s, 0.1)
	check(s.state.skill_effects_by_id.is_empty(), "periodic AA destroys recon")
	check(s.state.units_by_id["unit.player.warspite"].skill_state.cooldown_remaining >= 5, "recon destruction preserves penalty")

func test_coast_and_support():
	var blocked = fixture()
	blocked.state.units_by_id["unit.enemy.bismarck"].weapon_states.clear()
	blocked.terrain_query.configure({"map_size":[2000,1200], "obstacles":[{"id":"island", "block_mask":["TorpedoTravel"], "polygon":[[700,350],[740,350],[740,450],[700,450]]}]})
	launch(blocked, "weapon.shokaku_torpedo_bomber")
	time(blocked, 4)
	check(blocked.state.projectiles_by_id.is_empty(), "reject torpedo drop on solid island")
	check(blocked._event_buffer.filter(func(e): return e.event_type == "AviationPayloadRejected").size() == 6, "every invalid payload has auditable rejection")
	check(not blocked._event_buffer.any(func(e): return e.event_type == "AttackResolved"), "illegal water cannot restore abstract damage")
	var s = Session.new(registry)
	var level: Dictionary = registry.get_definition("levels", "level.prototype_harbor_3v3").duplicate(true)
	level.aviation_rules_mode = "Physical"
	check(s.create_battle_from_definition(level, 2911).get("ok", false), "physical airfield fixture")
	var field: Dictionary = s.facility_service.facilities_by_id["facility.harbor.airfield_east"]
	var target: Vector2 = field.position + Vector2(-300,0)
	var request: Dictionary = s.facility_service.request_support(field.facility_id,"support_mission.airstrike","enemy",target,0,{})
	check(request.get("accepted", false), "airfield real support request")
	s._advance_aviation_runtime()
	check(s.aviation_service.waves.size() == 1, "support joins the same authoritative flight service")
	var task: Dictionary = s.aviation_service.waves.values()[0]
	# Simulate an independently tested AA kill before the facility arrival callback.
	task.current_hp = 0
	task.phase = "Destroyed"
	task.ended_at_time = 0
	s.state.elapsed_time = 3
	s._advance_aviation_runtime()
	check(s.aviation_service.waves.values()[0].current_hp == 0, "destroyed support cannot respawn while its mission remains en route")
	s._event_buffer.clear()
	for event in s.facility_service.advance(20,20,s.state.units_by_id): s._handle_facility_event(event)
	check(not s._event_buffer.any(func(e): return e.event_type == "AttackResolved"), "destroyed airfield wave suppresses all salvos")
	check(s._event_buffer.any(func(e): return e.event_type == "SupportMissionCancelled" and e.get("reason_code", "") == "AIRCRAFT_DESTROYED"), "support destruction reports correct reason")

extends SceneTree
const Session = preload("res://scripts/application/battle_session.gd")
var Director
var registry
var checks := 0
var failures: Array = []
func _init(): call_deferred("run")
func check(value: bool, message: String):
	checks += 1
	if not value: failures.append(message)
func fixture():
	var s = Session.new(registry)
	s.create_battle("level.prototype_1v1", 2910)
	var source: Dictionary = s.state.units_by_id["unit.player.warspite"]
	var target: Dictionary = s.state.units_by_id["unit.enemy.bismarck"]
	source.position = Vector2(400,400)
	source.definition_id = "ship.enterprise_cv6"
	target.position = Vector2(900,400)
	s.state.visible_by_faction.player = {target.entity_id:true}
	return s
func run():
	Director = load("res://scripts/presentation/battle/battle_effect_director.gd")
	registry = root.get_node("DataRegistry").registry
	var s = fixture()
	var source: Dictionary = s.state.units_by_id["unit.player.warspite"]
	s._queue_skill_attack(source, {"id":"test.waves"}, {"weapon_id":"weapon.enterprise_airstrike", "waves":3, "wave_interval":2, "charge_time":1, "shots_per_wave":2}, Vector2(900,400), {})
	var scheduled: Dictionary = s.snapshot().aviation
	check(scheduled.values().all(func(w): return w.mission_id == scheduled.values()[0].mission_id), "skill waves share one mission association")
	check(scheduled.size() == 3, "one stable view per wave, not per bomb")
	check(scheduled.values().all(func(w): return w.phase == "Scheduled"), "cast does not launch every wave")
	s.state.elapsed_time = 1.0
	source.position = Vector2(430,500)
	s._resolve_delayed_attacks()
	var first_id: String = s.aviation_projection.waves.keys()[0]
	var first: Dictionary = s.snapshot().aviation[first_id]
	check(first.spawn_position == source.position, "samples moving carrier at actual departure")
	source.position = Vector2(450,600)
	s.state.elapsed_time = 2.0
	s._resolve_delayed_attacks()
	check(s.snapshot().aviation[first_id].spawn_position == Vector2(430,500), "sample never follows mother ship")
	var frozen: Dictionary = s.snapshot().aviation
	s.pause()
	s.advance_tick(1.0)
	check(s.snapshot().aviation == frozen, "pause freezes entire aviation timeline")
	s.resume()
	var director = Director.new()
	var units := Node2D.new()
	var projectiles := Node2D.new()
	var vfx := Node2D.new()
	root.add_child(units); root.add_child(projectiles); root.add_child(vfx); root.add_child(director)
	director.setup(units, projectiles, vfx)
	var snapshot: Dictionary = s.snapshot()
	director.sync_snapshot(snapshot, source.entity_id, "")
	check(director.aviation_views.size() == 3, "rebuild restores scheduled and current state without event replay")
	var view = director.aviation_views[first_id]
	check(view.visible and view.texture != null, "public bomber texture displays")
	var context := {"state":{"units_by_id":snapshot.units, "visible_by_faction":{"player":snapshot.units}}}
	var impact := {"event_id":"test.impact", "event_type":"AviationImpact", "damage_result":{"target_unit_id":"unit.enemy.bismarck", "impact_position":Vector2(900,400), "hit":true, "final_damage":10, "damage_type":"Aviation"}}
	director.consume_events([impact, impact], context)
	var count := vfx.get_child_count()
	director.consume_events([impact], context)
	check(vfx.get_child_count() == count, "duplicate event does not duplicate VFX or numbers")
	var separate := impact.duplicate(true)
	separate.event_id = "test.impact2"
	director.consume_events([separate], context)
	check(vfx.get_child_count() > count, "same tick separate attack keeps its own impact")
	director.sync_snapshot({"aviation":{}}, "", "")
	check(director.aviation_views.is_empty() and director.aviation_pool.size() == 3, "lost contact removes views into pool")
	check(director.aviation_pool.all(func(v): return not v.visible and v.sample.is_empty()), "hidden pool clears sensitive samples")
	for carrier in ["enterprise_cv6", "argus", "pobeda", "hosho", "illustrious", "graf_zeppelin", "shokaku"]:
		var ship: Dictionary = registry.get_definition("ships", "ship." + carrier)
		for mount in ship.get("weapon_mounts", []):
			var weapon: Dictionary = registry.get_definition("weapons", str(mount))
			if weapon.get("mount_type", "") != "Aviation": continue
			var wave := {"wave_id":"check", "phase":"Flying", "character_id":carrier, "source_weapon_id":weapon.id, "source_unit_id":"", "position":Vector2.ZERO, "target_position":Vector2(50,0), "progress":0.5}
			director.sync_snapshot({"aviation":{"check":wave}, "elapsed_time":1.0}, "", "")
			var actual = director.aviation_views.check
			check(actual.texture != null and "aircraft_" in actual.texture.resource_path, "public aircraft for " + str(weapon.id))
			if weapon.id == "weapon.shokaku_torpedo_bomber": check("torpedo_bomber" in actual.texture.resource_path, "concrete weapon wins over shared group")
			director.sync_snapshot({"aviation":{}}, "", "")
	# Structural load, not a rule cap; excess flights become symbols.
	var stress := {}
	for i in range(48): stress[str(i)] = {"wave_id":str(i), "phase":"Flying", "position":Vector2(i,0), "progress":0.5}
	director.sync_snapshot({"aviation":stress}, "", "")
	check(director.aviation_views.size() == 48 and director.aviation_views.values().all(func(v): return v.symbol_only), "over 32 preserves all real flights with symbol LOD")
	director.sync_snapshot({}, "", "")
	check(director.aviation_pool.size() == 32, "pool is bounded")
	director.clear()
	await process_frame
	check(projectiles.get_child_count() == 0 and director.aviation_views.is_empty(), "clear removes every flight/payload")
	for cycle in range(10):
		director.sync_snapshot({"aviation":stress}, "", "")
		director.clear()
		await process_frame
		check(projectiles.get_child_count() == 0 and director.aviation_pool.is_empty(), "restart cleanup cycle %d" % cycle)
	# No texture is still directional and visible.
	var fallback = preload("res://scripts/presentation/battle/aircraft_squadron_view.gd").new()
	projectiles.add_child(fallback)
	fallback.configure({})
	fallback.update_wave({"phase":"Flying", "position":Vector2.ZERO}, 0, false, false)
	check(fallback.visible and fallback.texture == null, "missing texture keeps symbol fallback")
	units.queue_free(); projectiles.queue_free(); vfx.queue_free(); director.queue_free()
	var cancel = fixture()
	var caster: Dictionary = cancel.state.units_by_id["unit.player.warspite"]
	cancel._queue_skill_attack(caster, {"id":"test.cancel"}, {"weapon_id":"weapon.enterprise_airstrike", "waves":2, "wave_interval":5, "shots_per_wave":1}, Vector2(900,400), {})
	cancel._sink_unit(caster, "unit.enemy.bismarck")
	cancel._advance_aviation_projection()
	check(cancel.delayed_attacks.size() == 1, "sinking cancels only unlaunched wave")
	check(cancel.aviation_projection.waves.values().any(func(w): return w.phase == "Cancelled"), "cancellation is distinct from destruction")
	for message in failures: push_error(message)
	print("Aviation presentation: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

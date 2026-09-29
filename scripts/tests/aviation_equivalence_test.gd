extends SceneTree
const Session = preload("res://scripts/application/battle_session.gd")
const Registry = preload("res://scripts/infrastructure/data/config_registry.gd")
const BASELINE = "res://reports/aviation/20260929-runtime/baseline.txt"
func _init(): call_deferred("run")
func run():
	var registry = Registry.new()
	assert(registry.load_all())
	var facts := []
	for weather in ["Normal", "Limited"]:
		for id in ["enterprise_airstrike", "argus_airstrike", "pobeda_bomber", "pobeda_ap_bomber", "hosho_airstrike", "illustrious_bomber", "graf_zeppelin_bomber", "shokaku_bomber", "shokaku_torpedo_bomber"]:
			var s = Session.new(registry)
			s.create_battle("level.prototype_1v1", 2910)
			var source: Dictionary = s.state.units_by_id["unit.player.warspite"]
			var target: Dictionary = s.state.units_by_id["unit.enemy.bismarck"]
			source.position = Vector2(400, 400)
			target.position = Vector2(900, 400)
			source.stats.aviation_power = 120.0
			s.terrain_context_service.global_environment["aviation_delay_multiplier"] = 1.5 if weather == "Limited" else 1.0
			var weapon: Dictionary = registry.get_definition("weapons", "weapon." + id)
			s._fire_weapon_at_position(source, target.position, source.weapon_states[0], weapon, true)
			s._queue_skill_attack(source, {"id":"test.waves"}, {"weapon_id":weapon.id, "waves":3, "wave_interval":1.0, "charge_time":0.5, "shots_per_wave":2}, target.position, {})
			for tick in range(160):
				s.state.elapsed_time = tick * 0.1
				s.state.tick_index = tick
				source.position += Vector2(0, 0.5)
				s._resolve_delayed_attacks()
				# Snapshot creation must remain read-only and independent of frame frequency.
				if tick % 3 == 0: s.snapshot("player")
			for event in s._event_buffer:
				if str(event.event_type).begins_with("Aviation"): continue
				var copy: Dictionary = event.duplicate(true)
				copy.erase("event_id")
				facts.append(copy)
			facts.append({"rng":s.random_source._random.state, "entity_sequence":s._entity_sequence, "hp":target.current_hp, "reload":source.weapon_states[0].reload_remaining})
	var text := var_to_str(facts)
	if "--record" in OS.get_cmdline_user_args():
		FileAccess.open(BASELINE, FileAccess.WRITE).store_string(text)
		print("Recorded aviation baseline: ", facts.size(), " facts")
		quit()
	else:
		var matches := FileAccess.get_file_as_string(BASELINE) == text
		print("Aviation equivalence: ", matches, " / ", facts.size(), " facts")
		if not matches: FileAccess.open(BASELINE + ".actual", FileAccess.WRITE).store_string(text)
		quit(0 if matches else 1)

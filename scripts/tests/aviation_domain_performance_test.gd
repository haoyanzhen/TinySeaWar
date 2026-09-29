extends SceneTree
const Session = preload("res://scripts/application/battle_session.gd")
const Registry = preload("res://scripts/infrastructure/data/config_registry.gd")
func _init(): call_deferred("run")
func run():
	var registry = Registry.new()
	assert(registry.load_all())
	var session = Session.new(registry)
	var level: Dictionary = registry.get_definition("levels","level.prototype_11v11").duplicate(true)
	level.aviation_rules_mode = "Physical"
	assert(session.create_battle_from_definition(level,2910).get("ok",false))
	var units: Array = session.state.units_by_id.values()
	var weapon: Dictionary = registry.get_definition("weapons","weapon.enterprise_airstrike")
	for i in range(32):
		var source: Dictionary = units[i % units.size()]
		var attack := {"attack_id":"stress.%d" % i,"source_unit_id":source.entity_id,"source_weapon_id":weapon.id,"origin":source.position,"target_position":source.position + Vector2(100,0),"launch_at_time":0.0,"resolve_at_time":60.0}
		session.delayed_attacks.append(attack)
		session._register_aviation_wave([attack],source,weapon)
	# Keep the specified pressure constant; this is not a damage/balance fixture.
	for task in session.aviation_service.waves.values(): task.current_hp = 1e9; task.max_hp = 1e9
	var samples: Array = []
	for tick in range(200):
		session.state.elapsed_time = tick * 0.1
		session._update_cooldowns_and_statuses(0.1)
		session._event_buffer.clear()
		var started := Time.get_ticks_usec()
		session._advance_aviation_runtime()
		if tick >= 20: samples.append(float(Time.get_ticks_usec()-started)/1000)
	samples.sort()
	var total := 0.0
	for value in samples: total += value
	var result := {"fixture":"11v11,32 persistent waves,HP inflated solely to hold stress constant", "samples":samples.size(),"mean_ms":total/samples.size(),"p95_ms":samples[int(samples.size()*0.95)],"p99_ms":samples[int(samples.size()*0.99)]}
	FileAccess.open("res://reports/aviation/20260929-runtime/domain-performance.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("Aviation domain pressure: ",JSON.stringify(result))
	quit()

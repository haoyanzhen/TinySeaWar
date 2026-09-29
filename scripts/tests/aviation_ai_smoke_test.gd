extends SceneTree
const Session = preload("res://scripts/application/battle_session.gd")
const Registry = preload("res://scripts/infrastructure/data/config_registry.gd")
func _init(): call_deferred("run")
func run():
	var registry = Registry.new()
	assert(registry.load_all())
	var rows: Array = []
	for mode in ["Abstract","Physical"]:
		for carrier in ["enterprise_cv6","argus","pobeda","hosho","illustrious","graf_zeppelin","shokaku"]:
			var s = Session.new(registry)
			var level: Dictionary = registry.get_definition("levels","level.prototype_1v1").duplicate(true)
			level.player_fleet[0].ship_id = "ship." + carrier
			level.player_fleet[0].position = [1700.0,1100.0]
			level.enemy_fleet[0].position = [2250.0,1100.0]
			level.aviation_rules_mode = mode
			s.create_battle_from_definition(level,2910)
			s.configure_full_ai_factions(["player","enemy"])
			for tick in range(1000): s.advance_tick(0.1)
			var stats: Dictionary = s.get_statistics()
			rows.append({"mode":mode,"carrier":carrier,"seconds":s.state.elapsed_time,"phase":s.state.phase,"aviation":stats.aviation,"pending_attacks":s.delayed_attacks.size(),"source_damage":stats.units.get("unit.player.warspite",{}).get("damage_dealt",0)})
	FileAccess.open("res://reports/aviation/20260929-runtime/ai-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"\t"))
	print("Aviation AI smoke: ",JSON.stringify(rows))
	quit()

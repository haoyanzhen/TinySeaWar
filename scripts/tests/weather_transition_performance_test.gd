extends SceneTree
const Registry = preload("res://scripts/infrastructure/data/config_registry.gd")
const Session = preload("res://scripts/application/battle_session.gd")
const OUT := "res://reports/weather/20260930-runtime/performance.json"
func _init(): call_deferred("run")
func summary(samples: Array) -> Dictionary:
	if samples.is_empty(): return {}
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for n in samples: total += float(n)
	return {"count":samples.size(), "mean_ms":total / samples.size() / 1000.0, "p95_ms":float(sorted[mini(sorted.size()-1, int(ceil(sorted.size()*0.95))-1)]) / 1000.0, "p99_ms":float(sorted[mini(sorted.size()-1, int(ceil(sorted.size()*0.99))-1)]) / 1000.0, "max_ms":float(sorted[-1]) / 1000.0}
func run():
	var registry = Registry.new()
	assert(registry.load_all())
	var report := {"seed":9330, "note":"11v11 full AI; same initial state. Validation overrides to thunderstorm_day at Tick 201, clear_day at 401; rule changes cause later trajectories to diverge. CPU headless, not GPU or balance acceptance.", "runs":{}}
	for mode in ["fixed", "switch"]:
		var level: Dictionary = registry.get_definition("levels", "level.prototype_11v11").duplicate(true)
		level.map.ocean_palette = "clear_day"
		var session = Session.new(registry)
		assert(session.create_battle_from_definition(level, 9330).ok)
		session.configure_full_ai_factions(["player", "enemy"])
		session.configure_performance_profiling(true)
		var changes: Array = []
		for tick in range(500):
			if mode == "switch" and tick in [200, 400]: session.queue_environment_override("thunderstorm_day" if tick == 200 else "clear_day", "Validation")
			var events: Array = session.advance_tick(0.1)
			changes.append_array(events.filter(func(e): return e.event_type == "GlobalEnvironmentChanged"))
			if session.state.phase != "Running": break
		var profile: Dictionary = session.get_performance_profile()
		var result := {"tick":summary(profile.tick_total_usec), "navigation":summary(profile.navigation_usec), "environment":summary(profile.tick_setup_environment_usec), "change_events":changes, "samples":{}}
		for center in [200,400]:
			var window: Array = []
			for index in range(maxi(0,center-2), mini(center+4, profile.tick_total_usec.size())):
				window.append({"tick":index+1, "tick_ms":profile.tick_total_usec[index]/1000.0, "navigation_ms":profile.navigation_usec[index]/1000.0, "normal_plans":profile.normal_plans_per_tick[index]})
			result.samples[str(center+1)] = window
		report.runs[mode] = result
		print(mode, " ", JSON.stringify(result))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	FileAccess.open(OUT, FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	quit()

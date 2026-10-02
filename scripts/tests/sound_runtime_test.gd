extends SceneTree
const Director = preload("res://scripts/presentation/audio/battle_sound_director.gd")
const PublicSignals = preload("res://scripts/application/battle_audio_public_signals.gd")
const Session = preload("res://scripts/application/battle_session.gd")
var checks := 0
var failures: Array = []
var serial := 0
var audio
var director
var public_signals = PublicSignals.new()
func _init(): call_deferred("run")
func check(value: bool, label: String):
	checks += 1
	if not value: failures.append(label)
func event(type: String, fields: Dictionary = {}) -> Dictionary:
	serial += 1
	var result := {"event_type":type,"event_id":"event.%06d" % serial,"tick_index":serial}
	result.merge(fields); return result
func ids() -> Array:
	return audio.log_entries.filter(func(e): return e.reason == "selected").map(func(e): return e.id)
func reset():
	director.setup(audio, true, 1200, false)
	audio.preferences.muted = false; audio.preferences.frequent_ui = true
	serial = 0
func view() -> Dictionary:
	return {"phase":"Running", "elapsed_time":0, "units":{"own":{"entity_id":"own","faction_id":"player", "position":Vector2.ZERO,"current_hp":1000,"max_hp":1000,"life_state":"Alive","is_flagship":true,"definition_id":"ship.warspite","primary_auto_fire_enabled":false}}, "aviation":{}, "facilities":{"port":{"faction_id":"player"}},"global_environment":{"weather":"clear","base_sea_state":1,"wind_speed":2}}
func run():
	audio = root.get_node("SoundManager")
	var preferences: Dictionary = audio.preferences.duplicate()
	var device: bool = audio.device_enabled
	audio.device_enabled = false
	director = Director.new()
	reset()
	var manifest: Dictionary = audio.manifest
	check(manifest.assets.size() == 60 and manifest.weapons.size() == 134 and manifest.ships.size() == 48 and manifest.skills.size() == 48, "full mapping counts")
	for id in manifest.assets:
		var asset: Dictionary = manifest.assets[id]
		check(asset.path.begins_with("res://assets/audio/sfx/runtime/") and FileAccess.file_exists(asset.path), id + " runtime exists")
		check(id not in manifest.cancelled_asset_ids, id + " adopted")
		var resource = audio.stream_for(id)
		check(resource is AudioStreamWAV, id + " Godot resource")
		check(resource.format == AudioStreamWAV.FORMAT_16_BITS, id + " lossless PCM16 import")
		if asset.loop: check(resource.loop_mode == AudioStreamWAV.LOOP_FORWARD and resource.loop_end > 0, id + " loop configured")
	for id in manifest.weapons: check(manifest.assets.has(manifest.weapons[id].fire), id + " fire resolves")
	for id in manifest.ships:
		for weapon in manifest.ships[id].weapons: check(manifest.weapons.has(weapon), id + " weapon coverage")
	for id in manifest.skills: check(manifest.skills[id].sound == null, id + " skill stays silent")
	var v := view()
	director.update(v, Vector2.ZERO, "own")
	var fire := event("WeaponFired", {"unit_id":"own", "weapon_id":"weapon.warspite_381_ap"})
	director.consume([fire, fire], v)
	check(ids() == ["W03"], "duplicate and salvo single owner")
	reset()
	director.consume([fire], v)
	check(ids() == ["W03"], "restart resets event IDs")
	reset()
	var concealed := [event("WeaponFired", {"unit_id":"hidden", "weapon_id":"weapon.yamato_460_ap"}),event("SubmarineDepthTransitionStarted", {"unit_id":"hidden","target_depth_state":"Surface"}),event("AttackResolved", {"damage_result":{"target_unit_id":"hidden","hit":true,"final_damage":100,"damage_type":"Torpedo","attack_id":"secret"}}),event("FacilityControlDeclared",{"facility_id":"secret","unit_id":"hidden"}),event("ContactAcquired",{"observer_faction":"enemy"})]
	director.consume(concealed,v)
	check(ids().is_empty(), "hidden sources targets facilities and enemy contacts silent")
	for type in ["SkillCast","ProjectileDetected","UnitTerrainCollision","SubmarineForcedSurface","AircraftDestroyed","FacilityWeaponFired","WeaponReady","SkillReady"]: director.consume([event(type,{"unit_id":"own"})],v)
	check(ids().is_empty(), "all cancelled trigger families silent")
	reset()
	director.consume([event("WeaponFired",{"unit_id":"own","weapon_id":"weapon.enterprise_airstrike"}),event("AviationWaveLaunched",{"source_unit_id":"own","wave_id":"wave"})],v)
	check(ids() == ["A01"], "legacy aviation suppressed; wave owns launch")
	director.consume([event("AviationWaveLaunched",{"source_unit_id":"own","wave_id":"wave"})],v)
	check(ids() == ["A01"], "wave duplicate with new event id suppressed")
	reset()
	var damage := {"target_unit_id":"own","source_unit_id":"hidden","attack_id":"hit","damage_type":"Torpedo","hit":true,"final_damage":100}
	director.consume([event("ProjectileHit",{"target_unit_id":"own"}),event("AttackResolved",{"damage_result":damage}),event("AttackResolved",{"damage_result":damage})],v)
	check(ids() == ["W14"], "projectile and damage share one hit")
	reset()
	director.consume([event("AttackResolved",{"damage_result":damage}),event("UnitSunk",{"unit_id":"own"})],v)
	check(ids() == ["W19"], "fatal hit merges into sinking")
	reset()
	var warning := view()
	warning.units.own.current_hp = 240
	warning.units.own.oxygen_state = {"current":10,"maximum":100}
	warning.units.own.position = Vector2(10000,10000)
	director.sync_warnings(warning); director.sync_warnings(warning)
	check(ids() == ["N06","S04"], "own offscreen warnings once per interval")
	warning.units.own.current_hp=270; warning.units.own.oxygen_state.current=23
	director.sync_warnings(warning)
	check(ids().size()==2,"threshold jitter does not rearm")
	warning.units.own.current_hp=500; warning.units.own.oxygen_state.current=50
	director.sync_warnings(warning)
	warning.units.own.current_hp=200; warning.units.own.oxygen_state.current=10
	director.sync_warnings(warning)
	check(ids().size()==4,"recovery hysteresis rearms")
	reset()
	director.reject({"command_type":"CastSkill"}, "COOLDOWN")
	director.reject({"command_type":"CastSkill"}, "COOLDOWN")
	director.reject({"command_type":"CastSkill","issuer_type":"AI"}, "COOLDOWN")
	check(ids() == ["U05a"], "local and deferred rejections aggregate; AI silent")
	reset()
	director.consume([event("MoveOrderAccepted",{"unit_id":"own"}),event("CommandRejected",{"command_type":"MoveUnits","successful_unit_ids":["own"],"rejected_unit_ids":["other"],"reason_code":"NO_ROUTE"})],v)
	check(ids() == ["U05a"], "partial intent never sounds fully successful")
	reset()
	director.update(v,Vector2.ZERO,"own")
	director.consume([event("UnitControlStateChanged",{"unit_id":"own","primary_auto_fire_enabled":true}),event("UnitControlStateChanged",{"unit_id":"own","primary_auto_fire_enabled":true})],v)
	check(ids() == ["U07a"], "toggle one cue; repeated values silent")
	reset()
	v.phase="Paused"
	director.consume([event("WeaponFired",{"unit_id":"own","weapon_id":"weapon.warspite_381_ap"})],v)
	check(ids().is_empty(),"pause discards world triggers")
	v.phase="Running"
	director.consume([event("BattleFinished",{"result":{"winner_faction":""}}),event("BattleFinished")],v)
	check(ids() == ["U11"],"neutral result once, no false victory")
	reset()
	for weather in ["clear","cloudy","overcast","rain","thunderstorm"]:
		for time in ["day","dawn","dusk","night"]:
			v.global_environment={"weather":weather,"time_of_day":time,"base_sea_state":5 if weather=="thunderstorm" else 2,"wind_speed":15 if weather=="thunderstorm" else 4}
			director.update(v,Vector2.ZERO,"own",true)
			check(audio.desired_loops.size()<=4,"weather layers within capacity " + weather+time)
			check(audio.desired_loops.has("E04b") == (weather=="thunderstorm"),"rain recipe " + weather+time)
	v.aviation={"a":{"phase":"Flying","position":Vector2.ZERO},"b":{"phase":"Flying","position":Vector2(10,0)},"c":{"phase":"Flying","position":Vector2(20,0)}}
	director.update(v,Vector2.ZERO,"own")
	check(audio.desired_loops.has("air.a") and audio.desired_loops.has("air.b") and not audio.desired_loops.has("air.c"),"nearest two public waves loop")
	v.aviation={}
	director.update(v,Vector2.ZERO,"own")
	check(not audio.desired_loops.has("air.a"),"visibility loss removes aircraft loop")
	reset()
	audio.preferences.muted=true
	director.consume([event("WeaponFired",{"unit_id":"own","weapon_id":"weapon.warspite_381_ap"}),event("BattleFinished")],view())
	check(ids().is_empty(),"mute includes results")
	audio.preferences.muted=false
	var cfg := ConfigFile.new(); cfg.set_value("menu","cover_id","fixture"); cfg.set_value("battle","skill_cutin_mode","simple"); cfg.save("user://sound_test.cfg")
	check(audio.save_preference("Combat",0.37,"user://sound_test.cfg"),"preferences saved")
	cfg.load("user://sound_test.cfg")
	check(cfg.get_value("audio","Combat") == 0.37 and cfg.get_value("menu","cover_id")=="fixture" and cfg.get_value("battle","skill_cutin_mode")=="simple","other preferences preserved")
	check(not audio.save_preference("UI",0.2,"user://missing_parent/audio.cfg") and audio.preferences.UI==0.2,"failed save preserves session setting")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://sound_test.cfg"))
	reset()
	v=view()
	var signals: Array = public_signals.events([event("SupportMissionStarted",{"facility_id":"port","mission_id":"mission"}),event("SupportMissionLaunched",{"facility_id":"port","faction_id":"player","mission_id":"mission"}),event("SupportMissionCompleted",{"facility_id":"port","faction_id":"player","mission_id":"mission"}),event("SupportMissionCancelled",{"facility_id":"hidden"}),event("SupportMissionLaunched",{"facility_id":"port","faction_id":"enemy"})],v,"own",[{"mission_id":"mission","faction_id":"player"}])
	check(signals.size()==3,"only own public support summaries")
	director.consume(signals,v)
	check(ids()==["U04b","A01","N11a"],"support request launch completion semantics")
	reset()
	v=view()
	v.units.own.position=Vector2(40,0)
	v.environment_zones=[{"id":"zone","position":Vector2.ZERO,"radius":100},{"id":"far","position":Vector2(1000,1000),"radius":50}]
	var zones: Array = public_signals.events([event("EnvironmentZoneChanged",{"zone_id":"zone","phase":"Dissipated"}),event("EnvironmentZoneChanged",{"zone_id":"far","phase":"Dissipated"})],v,"own")
	check(zones.size()==1,"environment notice only affects own focus")
	director.consume(zones,v)
	check(ids()==["N10"],"local environment neutral notice")
	reset()
	v=view()
	director.update(v,Vector2.ZERO,"own")
	v.aviation={"wave":{"phase":"Flying","position":Vector2.ZERO,"progress":0.95,"source_weapon_id":"weapon.enterprise_airstrike"}}
	director.update(v,Vector2.ZERO,"own"); director.update(v,Vector2.ZERO,"own")
	check(ids()==["A03"],"A public release phase once per wave")
	reset()
	director.physical=true
	director.update(v,Vector2.ZERO,"own")
	check(ids().is_empty(),"B snapshots never duplicate payload event")
	director.consume([event("AviationPayloadReleased",{"wave_id":"wave","position":Vector2.ZERO}),event("AviationPayloadReleased",{"wave_id":"torpedo","position":Vector2.ZERO,"projectile_id":"p"})],v)
	check(ids()==["A03","A05"],"B bomb and torpedo distinct actual release")
	reset()
	for i in range(4200): director.consume([event("SkillCast",{"unit_id":"own"})],view())
	director.consume([{"event_id":"event.000001","event_type":"WeaponFired","unit_id":"own","weapon_id":"weapon.warspite_381_ap"}],view())
	check(ids().is_empty() and director.seen.size()<4096,"retired event watermark prevents old replay with bounded memory")
	reset()
	audio.preferences.frequent_ui=false
	director.consume([event("MoveOrderAccepted",{"unit_id":"own"}),event("CommandRejected",{"command_type":"MoveUnits","reason_code":"NO_ROUTE"})],view())
	check(ids()==["U05a"],"optional frequent cues off retains rejection")
	audio.preferences.frequent_ui=true
	# Same fixed-seed commands and event stream; audio adapter cannot mutate battle facts.
	var registry = root.get_node("DataRegistry").registry
	var a = Session.new(registry); var b = Session.new(registry)
	a.create_battle("level.prototype_1v1",20261001); b.create_battle("level.prototype_1v1",20261001)
	a.configure_full_ai_factions(["player","enemy"]); b.configure_full_ai_factions(["player","enemy"])
	for session in [a,b]:
		session.state.units_by_id["unit.player.warspite"].position=Vector2(300,350)
		session.state.units_by_id["unit.enemy.bismarck"].position=Vector2(650,350)
	reset()
	var fired := false
	var resolved := false
	for tick in range(120):
		var ea: Array = a.advance_tick(0.1); var eb: Array = b.advance_tick(0.1)
		fired = fired or ea.any(func(e):return e.event_type=="WeaponFired")
		resolved = resolved or ea.any(func(e):return e.event_type=="AttackResolved")
		director.consume(a.presentation_events(ea), a.snapshot("player",false))
		# CPU timings are observational diagnostics, never deterministic combat facts.
		check(facts(ea)==facts(eb) and a.state==b.state,"audio preserves deterministic tick %d" % tick)
	check(fired and resolved,"audio fact equivalence includes actual firing and damage")
	var battle = load("res://scenes/battle/prototype_battle.tscn").instantiate()
	root.add_child(battle)
	battle.set_process(false)
	var token: int = audio.session_token
	battle._start_battle("level.prototype_1v1")
	check(audio.session_token > token and not audio.dense,"scene restart replaces sound session")
	battle._sync_visuals()
	check(not audio.desired_loops.is_empty(),"battle scene owns ambience lifecycle")
	battle.session.pause(); battle._sync_visuals()
	check(audio.paused,"scene pause reaches mixer")
	battle.session.resume(); battle._sync_visuals()
	check(not audio.paused,"scene resume reaches mixer")
	battle._start_battle("level.prototype_11v11")
	check(audio.dense,"11v11 enables dense mix at entry")
	for unit in battle.session.state.units_by_id.values():
		if unit.faction_id == "player" and unit.operation_slot > 1: unit.life_state="Sunk"
	battle._sync_visuals()
	check(audio.dense,"11v11 dense policy persists after losses")
	battle.session.state.phase="Finished"; battle._sync_visuals()
	check(audio.desired_loops.is_empty(),"terminal scene removes ambience")
	battle._start_battle("level.prototype_1v1")
	battle.terrain_debug_overlay.visible=true
	var enemy_id := "unit.enemy.bismarck"
	battle.session.state.units_by_id[enemy_id].oxygen_state={"current":1,"maximum":100}
	battle.session.state.units_by_id[enemy_id].current_hp=10
	battle.session.state.visible_by_faction.player={}
	battle._sync_visuals()
	check(not ids().has("S04") and not ids().has("N06"),"F9 does not grant audio enemy warnings")
	battle.free()
	check(audio.desired_loops.is_empty(),"scene exit clears loops")
	audio.clear_battle(); audio.preferences=preferences; audio.device_enabled=device; audio.apply_preferences()
	print("SOUND_RUNTIME checks=%d failures=%s" % [checks,failures])
	quit(0 if failures.is_empty() else 1)

func facts(value):
	if value is Array: return value.map(facts)
	if value is Dictionary:
		var result := {}
		for key in value:
			if str(key).ends_with("_usec"): continue
			result[key] = facts(value[key])
		return result
	return value

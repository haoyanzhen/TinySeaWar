extends RefCounted
const BattleSession = preload("res://scripts/application/battle_session.gd")
const SAMPLE_IDS = ["warspite","yukikaze","enterprise_cv6"]
static func sample_definition(registry) -> Dictionary:
	var level: Dictionary = registry.get_definition("levels","level.prototype_3v3").duplicate(true)
	level.id = "level.custom_runtime"
	level.display_name = "远景美术试验 · 三角色3v3"
	level.map = {"width":6144.0,"height":3456.0,"ocean_palette":"clear_day"}
	for faction in ["player","enemy"]:
		for i in range(3):
			var member: Dictionary = level[faction+"_fleet"][i]
			member.ship_id = "ship."+SAMPLE_IDS[i]
			member.entity_id = "review."+faction+"."+SAMPLE_IDS[i]
			member.position = [2700.0+i*300,2050.0 if faction=="player" else 1150.0]
	return level
static func density_snapshot(registry) -> Dictionary:
	var session = BattleSession.new(registry)
	assert(session.create_battle_from_definition(sample_definition(registry),20261009).ok)
	var snapshot: Dictionary = session.snapshot("player",true)
	var templates: Array = snapshot.units.values().filter(func(u): return u.faction_id=="player")
	templates.sort_custom(func(a,b): return a.definition_id<b.definition_id)
	snapshot.units = {}
	for side in range(2):
		for i in range(11):
			var u: Dictionary = templates[i%3].duplicate(true)
			var id := "fixture.%d.%02d" % [side,i]
			u.entity_id = id
			u.faction_id = "player" if side==0 else "enemy"
			u.position = Vector2(2200.0+(i%4)*220.0+side*340.0,1400.0+(i/4)*230.0+side*170.0)
			u.heading = -0.55 if side==0 else 2.6
			u.is_flagship = i==0
			u.current_hp = u.max_hp*(0.22 if i==7 else 0.8)
			snapshot.units[id] = u
	return snapshot

extends SceneTree
const Assets = preload("res://tools/art_review/far_view/review_assets.gd")
var Pilot
const Fixtures = preload("res://tools/art_review/far_view/fixtures.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func _init() -> void: call_deferred("run")
func run() -> void:
	Pilot = load("res://tools/art_review/far_view/pilot_view.gd")
	var registry = root.get_node("DataRegistry").registry
	var assets = Assets.new()
	var session = load("res://scripts/application/battle_session.gd").new(registry)
	check(session.create_battle_from_definition(Fixtures.sample_definition(registry),20261009).ok,"sample battle")
	var snapshot: Dictionary = session.snapshot("player",true)
	var original := var_to_bytes(session.state)
	for u in snapshot.units.values():
		var view = Pilot.new()
		root.add_child(view)
		view.configure(u)
		view.setup_review(assets)
		check(view.candidate_body!=null and view.candidate_rig!=null,"separate assets "+view.character_id)
		for h in [48.0,56.0,64.0]:
			view.target_height=h
			view.review_zoom=view.far_zoom
			check(is_equal_approx(view.display_height(),h),"far pixel height")
			check(view.hit_score(view.position+view.screen_body_rect().get_center()/view.review_zoom)<INF,"body center selectable")
			check(view.hit_score(view.position+Vector2(1000,1000)/view.review_zoom)==INF,"outside not selectable")
			var previous: float = h
			for z in [0.37,0.5,1.0,1.512,3.0]:
				view.review_zoom=z
				check(view.display_height()>=previous and view.display_height()<=h*1.65+0.001,"continuous bounded size")
				previous=view.display_height()
		view.play_fire_state("attack")
		view.play_hit_state()
		view._process(0.1)
		check(view.attack_remaining>0 and view.hit_remaining>0,"event feedback")
		view.frozen=true
		var t: float=view.clock_seconds
		view._process(1)
		check(view.clock_seconds==t,"pause freezes animation")
		var turned: Dictionary=u.duplicate(true)
		turned.heading=PI
		view.update_unit(turned,false,false)
		check(view.face_left,"left facing")
		turned.heading=PI*0.5
		view.update_unit(turned,false,false)
		check(view.face_left,"north south hysteresis")
		view.queue_free()
	check(var_to_bytes(session.state)==original,"presentation does not mutate Domain")
	var flow = root.get_node("GameFlow")
	flow.selected_level_id = "level.custom_runtime"
	flow._custom_level_definition = Fixtures.sample_definition(registry)
	var battle = load("res://scenes/battle/prototype_battle.tscn").instantiate()
	battle.set_script(load("res://tools/art_review/far_view/pilot_battle.gd"))
	root.add_child(battle)
	battle.set_process(false)
	battle._sync_visuals()
	var public: Dictionary=battle.session.snapshot("player",false)
	var public_id: String=public.units.keys()[0]
	var view = battle.effect_director.unit_views[public_id]
	var point: Vector2=view.position+view.screen_body_rect().get_center()/view.review_zoom
	check(battle._unit_at(point,public).get("entity_id","")==public_id,"pilot picking")
	check(battle._unit_at(point,{"units":{}}).is_empty(),"no hidden pick from cached view")
	battle._select_at(point,public)
	check(battle.selected_unit_id==public_id,"player command selection")
	var state_bytes := var_to_bytes(battle.session.state)
	battle.candidate_enabled=false
	battle._sync_visuals()
	check(var_to_bytes(battle.session.state)==state_bytes,"A/B switch does not mutate rules")
	check(not battle.progress_recording_enabled,"review never records progress")
	# Paired sessions consume identical ticks, independent of view style.
	var reference=load("res://scripts/application/battle_session.gd").new(registry)
	reference.create_battle_from_definition(Fixtures.sample_definition(registry),20260614)
	battle.candidate_enabled=true
	battle._start_battle("level.custom_runtime")
	for i in range(30):
		reference.advance_tick(0.1)
		battle._process(0.1)
	check(var_to_bytes(reference.state)==var_to_bytes(battle.session.state),"paired 30 ticks match")
	var key=InputEventKey.new()
	key.pressed=true; key.keycode=KEY_F6
	battle._unhandled_input(key)
	check(not battle.candidate_enabled,"F6 original toggle")
	key.keycode=KEY_F7
	battle._unhandled_input(key)
	check(battle.candidate_height==64.0,"F7 size cycle")
	battle.queue_free()
	await process_frame
	var result={"checks":checks,"failures":failures,"human_art_review":"pending"}
	var f=FileAccess.open("res://reports/art/20261009-far-view/technical.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(result,"\t")); f.close()
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)

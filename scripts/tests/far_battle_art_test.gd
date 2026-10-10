extends SceneTree
const Fixtures = preload("res://tools/art_review/far_view/fixtures.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var view_script = load("res://scripts/presentation/battle/far_ship_unit_view.gd")
	var data = root.get_node("DataRegistry")
	var registry = data.registry
	check(registry.errors.is_empty(),"data validation")
	check(data.assets.errors.is_empty(),"asset validation")
	var roster: Array = registry.definitions.get("ships", {}).values()
	check(roster.size()==48,"all 48 ships")
	var session = load("res://scripts/application/battle_session.gd").new(registry)
	check(session.create_battle_from_definition(Fixtures.sample_definition(registry),20261009).ok,"battle")
	var baseline := var_to_bytes(session.state)
	var template: Dictionary = session.snapshot("player",true).units.values()[0]
	for ship in roster:
		var id: String = str(ship.id).trim_prefix("ship.")
		var unit: Dictionary = template.duplicate(true)
		unit.definition_id=ship.id; unit.entity_id="qa."+id
		unit.ship_class=ship.ship_class
		var view = view_script.new()
		root.add_child(view); view.configure(unit)
		check(view.has_far_art(),id+" has body and rig")
		check(view.candidate_body==data.assets.far_battle_texture(id,"body"),id+" shared cached texture")
		for zoom in [0.2,0.365,0.5,1.0]:
			view.set_view_context(zoom,zoom,false,Vector2.ZERO,false)
			check(is_equal_approx(view.display_height(),56.0),id+" far56")
			var center: Vector2 = view.position+view.screen_body_rect().get_center()/zoom
			check(view.hit_score(center)<1.0,id+" portrait hit")
			check(view.hit_score(view.position+Vector2(1000,1000)/zoom)==INF,id+" outside miss")
		view.set_view_context(10.0,0.2,false,Vector2.ZERO,false)
		check(view.display_height()<=56.0*1.65+0.001,id+" near cap")
		view.play_fire_state("firepower");view.play_hit_state();view._process(0.1)
		check(view.current_animation_state()=="hit",id+" hit precedence")
		view.frozen=true
		var time: float=view.clock_seconds
		var fire: float=view.attack_remaining
		view._process(1.0)
		check(view.clock_seconds==time and view.attack_remaining==fire,id+" paused")
		unit.heading=PI;view.update_unit(unit,true,false,true)
		check(view.face_left and view.primary_selected,id+" heading and selection")
		unit.heading=PI*0.5;view.update_unit(unit,true,false,false)
		check(view.face_left and not view.primary_selected,id+" heading hysteresis / secondary selection")
		check(view.bind_point_world("unit_center").is_equal_approx(view.position),id+" unit center is authoritative position")
		var anchors: Dictionary=data.assets.far_battle_config(id).get("anchors",{})
		for name in anchors:
			var pair: Array=anchors[name]
			var expected: Vector2=view.position+(Vector2(pair[0],pair[1])*view.rig_screen_width()/view.review_zoom).rotated(float(unit.heading))
			check(view.bind_point_world(name).is_equal_approx(expected),id+" scaled heading anchor "+str(name))
		unit.depth_state="Submerged";view.update_unit(unit,false,false)
		if ship.ship_class=="Submarine":check(view._unit_visual_style().body_tint.a<1.0,id+" submerged style")
		unit.life_state="Sunk";view.update_unit(unit,false,false);view.frozen=false
		view._process(1.0);check(view.clock_seconds==time,id+" sunk freezes")
		view.free()
	check(var_to_bytes(session.state)==baseline,"presentation never mutates Domain")
	var broken: Dictionary = data.assets.far_battle_config("warspite").duplicate(true)
	broken.roles.body.alpha_rect=[0,0,-1,3]
	check(not data.assets._valid_far_battle_config(broken),"invalid crop rejected")
	broken=data.assets.far_battle_config("warspite").duplicate(true)
	broken.roles.body.path="assets/missing.png"
	check(not data.assets._valid_far_battle_config(broken),"missing asset rejected")
	# Only the supplied public snapshot can participate in expanded picking.
	var scene = load("res://scenes/battle/prototype_battle.tscn").instantiate()
	scene.progress_recording_enabled=false
	root.add_child(scene);scene.set_process(false)
	scene.battle_camera.zoom=Vector2.ONE*scene.camera_zoom_min;scene._sync_visuals()
	var snap: Dictionary=scene.session.snapshot("player",false)
	for id in snap.units:
		var view=scene.effect_director.unit_views[id]
		var p: Vector2=view.position+view.screen_body_rect().get_center()/view.review_zoom
		check(not scene._unit_at(p,{"units":{id:snap.units[id]}}).is_empty(),"formal visible body pick")
		check(scene._unit_at(p,{"units":{}}).is_empty(),"hidden snapshot cannot pick")
	scene.queue_free();await process_frame
	var result={"checks":checks,"failures":failures,"scope":"48 character assets and production renderer; human aesthetics separate"}
	FileAccess.open("res://reports/art/20261009-far-view-all/runtime_test.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));quit(0 if failures.is_empty() else 1)

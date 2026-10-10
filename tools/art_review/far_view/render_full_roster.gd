extends SceneTree
const Fixtures = preload("res://tools/art_review/far_view/fixtures.gd")
const OUT = "res://reports/art/20261009-far-view-all"
var records: Array = []
func _init() -> void: call_deferred("run")
func viewport(size: Vector2i) -> SubViewport:
	var v := SubViewport.new()
	v.size=size;v.size_2d_override=Vector2i(1920,1080);v.size_2d_override_stretch=true
	v.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(v);return v
func label(parent: Node, text: String, p: Vector2, size: int=20) -> void:
	var node:=Label.new();node.text=text;node.position=p;node.add_theme_font_size_override("font_size",size);node.add_theme_color_override("font_color",Color("ffdf86"));node.add_theme_color_override("font_shadow_color",Color("142d3b"));node.add_theme_constant_override("shadow_offset_x",1);node.add_theme_constant_override("shadow_offset_y",1);parent.add_child(node)
func save(v: SubViewport, name: String, scope: String) -> void:
	await process_frame;await process_frame;RenderingServer.force_draw(false)
	assert(v.get_texture().get_image().save_png(OUT+"/"+name+".png")==OK)
	records.append({"file":name+".png","scope":scope,"resolution":[v.size.x,v.size.y]})
	print("SAVED ",name)
func run() -> void:
	var registry=root.get_node("DataRegistry").registry
	var roster: Array=registry.all("ships");roster.sort_custom(func(a,b):return a.id<b.id)
	var session=load("res://scripts/application/battle_session.gd").new(registry)
	assert(session.create_battle_from_definition(Fixtures.sample_definition(registry),20261009).ok)
	var template: Dictionary=session.snapshot("player",true).units.values()[0]
	for near in [false,true]:
		var v:=viewport(Vector2i(1920,1080))
		var bg:=ColorRect.new();bg.size=Vector2(1920,1080);bg.color=Color("305d73");v.add_child(bg)
		label(v,"全48角色 · 正式战斗渲染器 · "+("近景上限92.4px" if near else "最远视角56px基准"),Vector2(36,20),26)
		for i in range(roster.size()):
			var ship: Dictionary=roster[i];var u:=template.duplicate(true)
			u.definition_id=ship.id;u.entity_id="gallery."+str(i);u.display_name=ship.display_name
			u.position=Vector2(120+(i%8)*240,175+(i/8)*170);u.heading=[0.0,-0.6,PI*0.8][i%3]
			u.is_flagship=false;u.current_hp=u.max_hp;u.ship_class=ship.ship_class;u.faction_id="player" if i%2==0 else "enemy"
			var view=load("res://scripts/presentation/battle/far_ship_unit_view.gd").new();v.add_child(view);view.configure(u)
			view.set_view_context(1.0,0.02 if near else 1.0,true,Vector2.ZERO,false);view.hovered=true;view.set_process(false)
		await save(v,"roster_"+("near" if near else "far56"),"all48 isolated rendering fixture; labels forced for review")
		v.queue_free();await process_frame
	for size in [Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3840,2160)]:
		var v:=viewport(size)
		root.get_node("GameFlow").selected_level_id="level.challenge.l01"
		var battle=load("res://scenes/battle/prototype_battle.tscn").instantiate();battle.progress_recording_enabled=false;v.add_child(battle);battle.set_process(false)
		battle.battle_camera.zoom=Vector2.ONE*battle.camera_zoom_min;battle.battle_camera.position=battle._player_fleet_center();battle._clamp_camera_to_map();battle.battle_camera.reset_smoothing()
		battle._sync_visuals();battle._update_hud()
		for view in battle.effect_director.unit_views.values():view.set_process(false)
		label(battle.battle_hud,"L-01正式开局 · 全角色新美术 · 最远视角56px（1080p逻辑基准）",Vector2(36,150),16)
		await save(v,"battle_l01_"+str(size.y),"formal L01 public snapshot opening")
		# Deliberate dense layout on an open-sea sample; no land or navigation claim.
		battle.queue_free();await process_frame
		root.get_node("GameFlow").selected_level_id="level.custom_runtime"
		root.get_node("GameFlow")._custom_level_definition=Fixtures.sample_definition(registry)
		battle=load("res://scenes/battle/prototype_battle.tscn").instantiate();battle.progress_recording_enabled=false;v.add_child(battle);battle.set_process(false)
		battle.battle_camera.zoom=Vector2.ONE*battle.camera_zoom_min
		var snap: Dictionary=Fixtures.density_snapshot(registry)
		var ids: Array=snap.units.keys();ids.sort()
		for i in range(ids.size()):
			var u: Dictionary=snap.units[ids[i]];var ship: Dictionary=roster[(i*7)%roster.size()]
			u.definition_id=ship.id;u.display_name=ship.display_name;u.ship_class=ship.ship_class
			if ship.ship_class=="Submarine":u.depth_state="Submerged"
			if i==20:u.life_state="Sunk"
		battle.battle_camera.position=Vector2(3072,1728);battle._clamp_camera_to_map();battle.battle_camera.reset_smoothing()
		battle.effect_director.clear();battle.effect_director.sync_snapshot(snap,ids[0],ids[12],[ids[0],ids[1],ids[2]])
		for view in battle.effect_director.unit_views.values():view.set_view_context(battle.camera_zoom_min,battle.camera_zoom_min,true,Vector2.ZERO,false);view.set_process(false)
		label(battle.battle_hud,"受控22单位交错布局 · 包含潜航/击沉/多选 · 非真实侦查与航行证据",Vector2(36,173),16)
		await save(v,"density22_"+str(size.y),"controlled mixed-roster22 fixture; submerged and sunk; not battle correctness")
		v.queue_free();await process_frame
	# Actual public 3v3 event integration, fixed seed and 16 simulation seconds.
	var combat_view:=viewport(Vector2i(1920,1080))
	var combat=load("res://scenes/battle/prototype_battle.tscn").instantiate();combat.progress_recording_enabled=false;combat_view.add_child(combat);combat.set_process(false)
	combat.battle_camera.zoom=Vector2.ONE*combat.camera_zoom_min;combat.battle_camera.position=Vector2(3072,1728);combat._clamp_camera_to_map();combat.battle_camera.reset_smoothing()
	combat.session.configure_full_ai_factions(["player","enemy"])
	for tick in range(160):
		combat._process(0.1)
		if tick%10==0:await process_frame
	for view in combat.effect_director.unit_views.values():view.set_process(false)
	label(combat.battle_hud,"实际3v3公开快照 · 16秒 · 正式远景渲染器 · 非平衡结论",Vector2(36,150),16)
	await save(combat_view,"combat3_1080","actual 3v3 public snapshot after 16 simulation seconds")
	combat_view.queue_free();await process_frame
	FileAccess.open(OUT+"/captures.json",FileAccess.WRITE).store_string(JSON.stringify(records,"\t"));quit()

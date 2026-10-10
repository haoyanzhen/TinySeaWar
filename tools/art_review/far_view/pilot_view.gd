extends "res://scripts/presentation/battle/ship_unit_view.gd"
var review_assets
var review_zoom := 1.0
var far_zoom := 0.365234
var target_height := 56.0
var hovered := false
var clock_seconds := 0.0
var attack_remaining := 0.0
var hit_remaining := 0.0
var face_left := false
var frozen := false
var candidate_body: Texture2D
var candidate_rig: Texture2D
func setup_review(assets) -> void:
	review_assets = assets
	candidate_body = assets.texture(character_id, "body")
	candidate_rig = assets.texture(character_id, "rig")
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
func display_height() -> float:
	return clampf(target_height * pow(maxf(review_zoom / maxf(far_zoom, 0.01), 1.0), 0.35), target_height, target_height * 1.65)
func rig_screen_width() -> float:
	return review_assets.rig_width(character_id) * display_height() / 56.0
func screen_body_rect() -> Rect2:
	var h := display_height()
	var w := h * candidate_body.get_width() / float(candidate_body.get_height()) if candidate_body else h * 0.7
	return Rect2(Vector2(-w*0.5, -h+6.0), Vector2(w,h))
func hit_score(world: Vector2) -> float:
	var p := (world - position) * review_zoom
	var rect := screen_body_rect().grow(4.0)
	if rect.has_point(p): return p.distance_to(rect.get_center()) / maxf(rect.size.y,1.0)
	var rig_point := p.rotated(-float(unit.get("heading",0.0)))
	var width := rig_screen_width()
	if Rect2(-Vector2(width,width*0.5)*0.5, Vector2(width,width*0.5)).has_point(rig_point):
		return 1.0+p.length()/width
	return INF
func update_unit(snapshot: Dictionary, is_selected: bool, is_focused: bool, is_primary_selected: bool = true) -> void:
	super.update_unit(snapshot, is_selected, is_focused, is_primary_selected)
	var x := cos(float(snapshot.get("heading",0.0)))
	if x < -0.2: face_left = true
	elif x > 0.2: face_left = false
	z_index = 0 # Parent sorts feet; keep public projectiles/VFX in their existing layers.
func _process(delta: float) -> void:
	if frozen: return
	clock_seconds += delta
	move_memory = maxf(0.0,move_memory-delta)
	attack_remaining = maxf(0.0,attack_remaining-delta)
	hit_remaining = maxf(0.0,hit_remaining-delta)
	queue_redraw()
func play_fire_state(state_name: String = "attack") -> void:
	attack_remaining = 0.3 if state_name != "firepower" else 0.6
func play_hit_state() -> void:
	hit_remaining = 0.25
func bind_point_world(_point_name: String) -> Vector2:
	# Pilot has no accepted per-mount anchors: public VFX uses true unit center.
	return position
func _draw() -> void:
	if candidate_body == null or candidate_rig == null or unit.is_empty(): return
	var zoom := maxf(review_zoom,0.01)
	var h := display_height()
	var width := rig_screen_width()
	var heading := float(unit.get("heading",0.0))
	var friendly := str(unit.get("faction_id","")) == "player"
	var color := Color("63d9fa") if friendly else Color("ff8897")
	var style := _unit_visual_style()
	if selected:
		# True Domain footprint, distinct from the enlarged art.
		draw_polyline(_ellipse_points(CollisionGeometryService.half_extents(unit),heading,true),Color(1,0.82,0.34,0.65),1.2/zoom,true)
	draw_set_transform(Vector2.ZERO, heading, Vector2.ONE / zoom)
	var rig_h := width*candidate_rig.get_height()/float(candidate_rig.get_width())
	draw_texture_rect(candidate_rig,Rect2(-Vector2(width,rig_h)*0.5,Vector2(width,rig_h)),false,style.rig_tint)
	var bob := sin(clock_seconds*3.0)*0.65
	var recoil := sin(attack_remaining/0.3*PI)*2.8 if attack_remaining>0.0 else 0.0
	var lean := (0.045 if not face_left else -0.045) if move_memory>0.0 else 0.0
	var tint: Color = style.body_tint
	if hit_remaining>0.0: tint = tint.lerp(Color(1.0,0.45,0.4,tint.a),0.6)
	draw_set_transform(Vector2(0,bob+recoil)/zoom,lean,Vector2(-1.0 if face_left else 1.0,1.0)/zoom)
	draw_texture_rect(candidate_body,screen_body_rect(),false,tint)
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE/zoom)
	var center := Vector2(0,9)
	if friendly: draw_arc(center,10,0,PI,16,color,2,true)
	else: draw_polyline(PackedVector2Array([center+Vector2(-9,0),center+Vector2(0,7),center+Vector2(9,0)]),color,2,true)
	if selected: draw_arc(center,15,0.1,PI-0.1,24,Color("ffcf67"),2.5,true)
	if focused: draw_rect(screen_body_rect().grow(4),Color("ffad55"),false,1.5)
	var tip := Vector2(width*0.5+9,0).rotated(heading)
	draw_polyline(PackedVector2Array([tip+Vector2(-6,-4).rotated(heading),tip,tip+Vector2(-6,4).rotated(heading)]),color,2,true)
	var hp := clampf(float(unit.get("current_hp",0))/maxf(1,float(unit.get("max_hp",1))),0,1)
	var bar := Rect2(Vector2(-20,-h-3),Vector2(40,4))
	draw_rect(bar,Color("203b49"))
	draw_rect(Rect2(bar.position,Vector2(bar.size.x*hp,bar.size.y)),Color("70db84") if friendly else Color("ff9a8c"))
	var flag := bool(unit.get("is_flagship",false))
	if flag: draw_circle(Vector2(-25,-h-1),3,Color("ffd565"))
	if selected or focused or hovered or flag or hp<0.3:
		var label := str(unit.get("display_name",character_id))
		draw_string_outline(ThemeDB.fallback_font,Vector2(-64,33),label,HORIZONTAL_ALIGNMENT_CENTER,128,14,3,Color("163747"))
		draw_string(ThemeDB.fallback_font,Vector2(-64,33),label,HORIZONTAL_ALIGNMENT_CENTER,128,14,Color.WHITE)
	draw_set_transform(Vector2.ZERO)

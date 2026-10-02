extends SceneTree
const Session = preload("res://scripts/application/battle_session.gd")
var checks := 0
var failures: Array[String] = []
func _init(): call_deferred("run")
func check(ok: bool, label: String):
 checks += 1
 if not ok: failures.append(label); push_error(label)
func vec(p: Array) -> Vector2: return Vector2(p[0],p[1])
func route(s, a: Vector2, b: Vector2, radius: float, tags: Array, label: String):
 var p: Dictionary = s.route_planner.plan_path(s.terrain_query,s.navigation_definition,a,b,radius,tags,s.terrain_context_service)
 check(p.get("ok",false) and not p.get("target_projected",false),label+" exact route")
 var previous := a
 for next: Vector2 in p.get("waypoints",[]):
  check(s.terrain_query.is_navigation_segment_clear(previous,next,radius,tags),label+" continuous segment")
  previous=next
 check(previous.distance_to(b)<1,label+" reaches authored destination")
func run():
 var registry=root.get_node("DataRegistry").registry
 var total:=0;var coastal:=0
 for l in registry.all("levels"):
  if not (str(l.id).begins_with("level.tutorial.") or str(l.id).begins_with("level.challenge.")):continue
  total+=1
  var s=Session.new(registry);check(s.create_battle(l.id,20261002).get("ok",false),l.id+" creates")
  if not l.map.has("terrain_definition_id"):
   check(l.id in ["level.tutorial.t01","level.tutorial.t02","level.tutorial.t03","level.tutorial.t04"],l.id+" intentional open sea")
   continue
  coastal+=1
  var terrain:Dictionary=s.state.terrain_map
  check(str(terrain.id).ends_with("_16x9") or str(terrain.id).begins_with("terrain.map.challenge_"),l.id+" uses rebuilt map")
  check(l.map.width==6144 and l.map.height==3456,l.id+" correct extent")
  var objective:Dictionary=registry.get_definition("objectives",l.objective_set_id)
  for uid in s.state.units_by_id:
   var u:Dictionary=s.state.units_by_id[uid];var r:float=u.stats.collision_radius;var tags:Array=s._movement_tags(u)
   check(s.terrain_query.can_occupy_circle(u.position,r,tags),uid+" legal initial hull")
   var other:Dictionary=l.enemy_fleet[0] if u.faction_id=="player" else l.player_fleet[0]
   route(s,u.position,vec(other.position),r,tags,uid+" opposing deployment")
   if objective.get("enemy_staging_positions",{}).has(uid):
    var target=vec(objective.enemy_staging_positions[uid])
    check(s.terrain_query.can_occupy_circle(target,r,tags),uid+" legal staging")
    route(s,u.position,target,r,tags,uid+" staging")
  if objective.has("route_player_unit_id"):
   var u:Dictionary=s.state.units_by_id[objective.route_player_unit_id];var previous:Vector2=u.position
   for zone in objective.get("route_waypoint_zones",[]):
    route(s,previous,vec(zone.position),u.stats.collision_radius,s._movement_tags(u),l.id+" "+zone.id)
    previous=vec(zone.position)
   if objective.has("retreat_zone"):route(s,previous,vec(objective.retreat_zone.position),u.stats.collision_radius,s._movement_tags(u),l.id+" retreat")
  for wave in l.get("reinforcement_waves",[]):
   var slots:Array=terrain.spawn_points.filter(func(p):return p.id==wave.spawn_point_id)
   check(slots.size()==1,l.id+" reinforcement entry exists")
   for member in wave.members:
    check(s.terrain_query.can_occupy_circle(vec(member.position),46,["Surface"]),member.entity_id+" safe reserve")
    if slots.size()==1:check(vec(slots[0].position).distance_to(vec(member.position))<1,member.entity_id+" matches declared entry")
    route(s,vec(member.position),vec(l.player_fleet[0].position),46,["Surface"],member.entity_id+" enters battle")
 check(total==23 and coastal==19,"all 23 formal levels, 19 rebuilt coastal maps")
 print("FORMAL MAP INTEGRATION: %d checks, %d failures"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)

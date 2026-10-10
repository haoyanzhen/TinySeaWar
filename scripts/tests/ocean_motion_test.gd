extends SceneTree
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok: failures.append(label)
func _init(): call_deferred("run")
func run():
 var wake = load("res://scripts/presentation/battle/ship_wake_layer.gd").new()
 root.add_child(wake)
 var unit = {"position":Vector2.ZERO,"life_state":"Alive","ship_class":"Destroyer"}
 var snap = {"elapsed_time":0.0,"units":{"visible":unit},"contacts":{"hidden":{"last_known_position":Vector2(10,10)}}}
 var original = var_to_bytes(snap)
 wake.sync_snapshot(snap,0.4)
 check(var_to_bytes(snap)==original,"does not mutate snapshot")
 check(not wake.trails.has("hidden"),"contacts never emit wakes")
 for i in range(1,61):
  snap.elapsed_time=i*0.1
  unit.position=Vector2(i*5.0,sin(i*0.1)*30)
  wake.sync_snapshot(snap,0.4)
 check(wake.trails.visible.size()>10 and wake.trails.visible.size()<=wake.max_samples,"bounded curved movement history")
 var preserved=var_to_bytes(wake.trails)
 for i in range(30): wake.sync_snapshot(snap,0.4)
 check(var_to_bytes(wake.trails)==preserved,"paused clock preserves wake without new samples")
 for i in range(61,95):
  snap.elapsed_time=i*0.1
  wake.sync_snapshot(snap,0.4)
 check(wake.trails.visible.is_empty(),"stationary wake expires")
 snap.elapsed_time=9.5;unit.position+=Vector2(5,0);wake.sync_snapshot(snap,0.4)
 check(not wake.trails.visible.is_empty(),"movement resumes")
 snap.units={};wake.sync_snapshot(snap,0.4)
 check(wake.trails.is_empty() and wake.last_positions.is_empty(),"loss of visibility removes all traces immediately")
 snap.units={"visible":unit};unit.ship_class="Submarine";unit.depth_state="Submerged";wake.sync_snapshot(snap,0.4)
 check(wake.trails.is_empty(),"submerged submarine emits no surface wake")
 unit.depth_state="Surface";wake.sync_snapshot(snap,0.4)
 snap.elapsed_time=9.6;unit.position+=Vector2(5,0);wake.sync_snapshot(snap,0.4)
 check(not wake.trails.visible.is_empty(),"surface submarine can emit wake")
 unit.life_state="Sunk";wake.sync_snapshot(snap,0.4)
 check(wake.trails.is_empty(),"sunk removes wake")
 unit.life_state="Alive";wake.sync_snapshot(snap,0.4)
 snap.elapsed_time=9.7;unit.position+=Vector2(1000,0);wake.sync_snapshot(snap,0.4)
 check(wake.trails.visible.is_empty(),"teleport does not draw a water streak")
 wake.clear();check(wake.trails.is_empty() and wake.last_positions.is_empty(),"restart clears state")
 wake.free()
 print("OCEAN MOTION: ",checks," checks; failures=",failures)
 quit(0 if failures.is_empty() else 1)

extends SceneTree
const Weather = preload("res://scripts/presentation/battle/weather_overlay.gd")
var failures: Array[String] = []
var checks := 0
var flashes := 0
func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok: failures.append(label)
func _init(): call_deferred("run")
func run():
 var weather = Weather.new()
 weather.material = ShaderMaterial.new()
 weather.material.shader = load("res://assets/environment/weather/weather_overlay.gdshader")
 root.add_child(weather)
 weather.set_process(false)
 weather.configure(Vector2(4096,2304),"thunderstorm_night")
 weather.lightning_flashed.connect(func(): flashes += 1)
 var snap={"units":{"seen":{"position":Vector2(100,200),"life_state":"Alive"},"sunk":{"position":Vector2(400,400),"life_state":"Sunk"}},"contacts":{"hidden":{"last_known_position":Vector2(900,900)}},"projectiles":{}}
 var original=var_to_bytes(snap)
 weather.sync_readability(snap,0.5,true,Vector2(300,400))
 check(var_to_bytes(snap)==original,"readability never mutates public snapshot")
 check(weather.material.get_shader_parameter("focus_count")==1,"only live visible units receive detail protection")
 check(weather.material.get_shader_parameter("focus_points")[0]==Vector2(100,200),"protection uses observed position, never remembered contact")
 check(weather.material.get_shader_parameter("aim_active"),"aim protection enabled")
 weather.sync_readability({"units":{},"projectiles":{}},1.0,false,Vector2.ZERO)
 check(weather.material.get_shader_parameter("focus_count")==0 and not weather.material.get_shader_parameter("aim_active"),"loss of visibility and aim clears protection immediately")
 for i in range(101): weather._process(0.02)
 check(flashes==1,"flash start emits once")
 var before=weather.animation_time
 weather.set_animation_paused(true)
 weather._process(5.0)
 check(is_equal_approx(before,weather.animation_time) and flashes==1,"pause freezes flash and suppresses repeated thunder")
 weather.set_animation_paused(false)
 weather._process(0.3)
 check(flashes==1 and Weather.flash_envelope(weather.animation_time)>0.0,"extended flash remains visible at 320ms without repeated thunder")
 weather._process(0.1)
 check(flashes==1 and Weather.flash_envelope(weather.animation_time)==0.0,"flash ends without repeated thunder")
 var width:=0.0
 for i in range(1000):
  if Weather.flash_envelope(2.0+i*0.001)>=0.5: width+=0.001
 check(width>=0.20 and width<=0.25,"extended flash main peak within 200-250ms")
 for i in range(12):
  var gap=Weather.flash_start(i+1)-Weather.flash_start(i)
  check(gap>=9.0 and gap<=15.0,"flash spacing bounded 9-15 seconds")
 weather.configure(Vector2(4096,2304),"thunderstorm_night")
 weather._process(2.2)
 check(flashes==2,"restart resets flash event; coarse step crossing flash still emits")
 weather.set_palette("clear_day")
 weather._process(12.0)
 check(flashes==2 and not weather.atmosphere_enabled,"clear weather disables flash and candidate path")
 weather.set_palette("cloudy")
 check(weather.atmosphere_enabled,"legacy cloudy alias keeps canonical candidate")
 var many={"units":{},"projectiles":{}}
 for i in range(60):
  many.units[str(i)]={"position":Vector2(i*30,0),"life_state":"Alive"}
  many.projectiles[str(i)]={}
 weather.sync_readability(many,0.5,false,Vector2.ZERO)
 check(weather.material.get_shader_parameter("focus_count")==24,"dense public scene bounds protected points")
 check(is_equal_approx(float(weather.material.get_shader_parameter("focus_radius"))*0.5,110.0),"protection radius remains logical-pixel sized")
 weather._process(1.0)
 check(is_equal_approx(weather.detail_activity,0.55),"dense visible projectiles reduce fine weather detail")
 weather.sync_readability({"units":{},"projectiles":{}},0.5,false,Vector2.ZERO)
 weather._process(0.1)
 check(weather.detail_activity>0.55 and weather.detail_activity<1.0,"quiet scene restores detail gradually")
 weather.free()
 print("WEATHER ATMOSPHERE: ",checks," checks; failures=",failures)
 quit(0 if failures.is_empty() else 1)

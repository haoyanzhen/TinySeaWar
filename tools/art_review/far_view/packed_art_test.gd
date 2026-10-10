extends SceneTree
func _init():call_deferred("run")
func run():
 var data=root.get_node("DataRegistry")
 var errors=[]
 for definition in data.registry.all("ships"):
  var id=str(definition.id).trim_prefix("ship.")
  for role in ["body","rig"]:
   if data.assets.far_battle_texture(id,role)==null:errors.append(id+":"+role)
 print("PCK_FAR_ART ",JSON.stringify({"characters":data.registry.all("ships").size(),"errors":errors,"catalog_errors":data.assets.errors}))
 quit(0 if errors.is_empty() and data.assets.errors.is_empty() else 1)

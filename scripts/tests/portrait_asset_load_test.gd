extends SceneTree
var checks := 0
var failures: Array[String] = []
func _init() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
func run() -> void:
	var catalog = root.get_node("DataRegistry").assets
	check(catalog.characters.size() == 48, "exact full roster coverage")
	for id in catalog.characters:
		for semantic in ["ui_portrait", "ui_portrait_small"]:
			var texture = load(catalog.character_ui_asset_path(id, semantic)) as Texture2D
			var size := 512 if semantic == "ui_portrait" else 128
			check(texture != null and texture.get_size() == Vector2(size,size), "%s %s imports new square canvas" % [id,semantic])
	check(catalog.errors.is_empty(), "catalog has no asset errors")
	for failure in failures: push_error(failure)
	print("Portrait asset load: %d/%d passed" % [checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)

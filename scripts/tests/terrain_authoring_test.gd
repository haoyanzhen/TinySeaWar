extends SceneTree

const TerrainAuthoringRoot = preload("res://addons/terrain_authoring/terrain_authoring_root.gd")

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root = TerrainAuthoringRoot.new()
	root.snapshot_path = "/tmp/tinyseawar_terrain_authoring_snapshot.json"
	get_root().add_child(root)
	var template_result: String = root.load_authoring_data()
	_check(template_result.begins_with("已加载"), "template canonical data loads into the Godot authoring workspace")
	_check(root._semantic_polygons(root).size() >= 4, "template workspace contains reviewed land and water polygons")
	_check(root._authoring_nodes("FacilityAnchor").size() == 8, "template workspace exposes all facility anchors and interaction waters")
	_check(root._authoring_nodes("LandInstance").size() == 1, "template workspace displays the aligned island artwork reference")
	root.authoring_mode = "Map"
	var map_result: String = root.load_authoring_data()
	_check(map_result.begins_with("已加载"), "map canonical data loads into the Godot authoring workspace")
	_check(root._authoring_nodes("FacilityPlacement").size() == 8, "map workspace exposes facility ownership and dependency metadata")
	_check(root._authoring_nodes("LandInstance").size() == 1, "map workspace exposes editable island instance transforms")
	var semantic_counts := {}
	var has_drift_path := false
	for polygon in root._semantic_polygons(root):
		var semantic := str(polygon.get_meta("semantic_type", ""))
		semantic_counts[semantic] = int(semantic_counts.get(semantic, 0)) + 1
		if semantic == "EnvironmentZone" and polygon.get_meta("drift_path", []).size() >= 2:
			has_drift_path = true
	_check(int(semantic_counts.get("EnvironmentZone", 0)) == 7, "map workspace exposes all soft-terrain regions")
	_check(int(semantic_counts.get("Minefield", 0)) == 1 and int(semantic_counts.get("SafeChannel", 0)) == 1, "map workspace exposes fixed minefields and safe channels")
	_check(has_drift_path, "environment authoring retains deterministic drift paths")
	root.queue_free()
	if failures.is_empty():
		print("PASS: %d terrain authoring checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error(failure)
		print("FAIL: %d failures across %d terrain authoring checks" % [failures.size(), checks])
		quit(1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

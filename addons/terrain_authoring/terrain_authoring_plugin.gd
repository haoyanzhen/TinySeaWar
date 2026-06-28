@tool
extends EditorPlugin

const TerrainAuthoringRoot = preload("res://addons/terrain_authoring/terrain_authoring_root.gd")
const TerrainAuthoringDock = preload("res://addons/terrain_authoring/terrain_authoring_dock.gd")

var dock


func _enter_tree() -> void:
	add_custom_type("TerrainAuthoringRoot", "Node2D", TerrainAuthoringRoot, null)
	dock = TerrainAuthoringDock.new()
	dock.editor_interface = get_editor_interface()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, dock)


func _exit_tree() -> void:
	if dock != null:
		remove_control_from_docks(dock)
		dock.free()
	remove_custom_type("TerrainAuthoringRoot")

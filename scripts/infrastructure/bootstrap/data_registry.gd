extends Node

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")
const AssetCatalog = preload("res://scripts/infrastructure/assets/asset_catalog.gd")

var registry = ConfigRegistry.new()
var assets = AssetCatalog.new()


func _ready() -> void:
	if not registry.load_all():
		push_error("Data registry validation failed: %s" % "; ".join(registry.errors))
	if not assets.load_all():
		push_error("Asset catalog validation failed: %s" % "; ".join(assets.errors))

extends Node

const ConfigRegistry = preload("res://scripts/infrastructure/data/config_registry.gd")

var registry = ConfigRegistry.new()


func _ready() -> void:
	if not registry.load_all():
		push_error("Data registry validation failed: %s" % "; ".join(registry.errors))

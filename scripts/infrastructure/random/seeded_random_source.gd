extends RefCounted

var _random := RandomNumberGenerator.new()


func _init(seed_value: int = 1) -> void:
	_random.seed = seed_value


func randf() -> float:
	return _random.randf()


func randi_range(from: int, to: int) -> int:
	return _random.randi_range(from, to)

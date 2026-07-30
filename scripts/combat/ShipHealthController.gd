extends RefCounted
class_name ShipHealthController

var health: ShipHealth


func setup(next_health: ShipHealth) -> void:
	health = next_health


func shutdown() -> void:
	health = null


func apply(result: DamageResult) -> float:
	if health == null or result == null:
		return 0.0
	return health.apply_damage_result(result)

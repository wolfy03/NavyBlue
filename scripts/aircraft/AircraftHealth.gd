extends Node
class_name AircraftHealth

signal health_changed(current_health: float, maximum_health: float)
signal died

var maximum_health: float = 1.0
var current_health: float = 1.0
var _dead := false


func setup(data: AircraftData) -> void:
	maximum_health = maxf(data.maximum_hp, 1.0) if data != null else 1.0
	current_health = maximum_health
	_dead = false
	health_changed.emit(current_health, maximum_health)


func apply_damage(amount: float) -> float:
	if _dead or amount <= 0.0:
		return 0.0
	var previous := current_health
	current_health = maxf(0.0, current_health - amount)
	var applied := previous - current_health
	health_changed.emit(current_health, maximum_health)
	if current_health <= 0.0:
		_dead = true
		died.emit()
	return applied


func is_alive() -> bool:
	return not _dead and current_health > 0.0

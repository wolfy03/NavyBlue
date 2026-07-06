extends Node
class_name ShipHealth

signal died

@export var max_health := 100.0
var current_health := 100.0

func _ready() -> void:
	current_health = max_health

func apply_damage(amount: float) -> void:
	current_health = maxf(0.0, current_health - amount)
	if current_health <= 0.0:
		died.emit()


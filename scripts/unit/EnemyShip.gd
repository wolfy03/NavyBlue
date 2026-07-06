extends "res://scripts/unit/ShipUnit.gd"
class_name EnemyShip

func _ready() -> void:
	team = &"enemy"
	super()

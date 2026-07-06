extends "res://scripts/unit/ShipUnit.gd"
class_name AllyShip

func _ready() -> void:
	team = &"ally"
	super()

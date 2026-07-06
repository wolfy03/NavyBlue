extends Node
class_name ShipCombat

func fire_all(turrets: Array) -> void:
	for turret in turrets:
		turret.fire()


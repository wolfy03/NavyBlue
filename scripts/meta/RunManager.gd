extends Node
class_name RunManager

var active_upgrades: Array[String] = []

func reset_run() -> void:
	active_upgrades.clear()


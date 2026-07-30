extends Node
class_name BattleTestServicesHost

var services: BattleServices


func _exit_tree() -> void:
	if services != null:
		services.shutdown()
	services = null

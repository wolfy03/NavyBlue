extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	var player_source := FileAccess.get_file_as_string(
		"res://scripts/aircraft/combat/PlayerDiveBombRun.gd"
	)
	var ai_source := FileAccess.get_file_as_string(
		"res://scripts/aircraft/missions/DiveBombMissionBehavior.gd"
	)
	var coordinator_source := FileAccess.get_file_as_string(
		"res://scripts/aircraft/combat/SquadronDiveBombCoordinator.gd"
	)
	_check(
		player_source.contains("SquadronDiveBombCoordinator.new()"),
		"player commands create the shared coordinator"
	)
	_check(
		ai_source.contains("SquadronDiveBombCoordinator.new()"),
		"AI missions create the shared coordinator"
	)
	_check(
		coordinator_source.contains("AircraftDiveBombController.new()"),
		"coordinator creates one-aircraft controllers"
	)
	_check(
		coordinator_source.contains("pass_dispersion_offset"),
		"coordinator applies one pass-wide accuracy offset"
	)
	_check(
		player_source.contains("DiveBombAttackMode.Type.QUICK_ATTACK") \
			or player_source.contains("attack_mode"),
		"player adapter accepts quick attack mode"
	)
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	print("DIVE_BOMB_SHARED_COORDINATOR_TEST failures=%d" % _failures.size())
	for failure in _failures:
		push_error("DIVE COORDINATOR: %s" % failure)
	quit(0 if _failures.is_empty() else 1)

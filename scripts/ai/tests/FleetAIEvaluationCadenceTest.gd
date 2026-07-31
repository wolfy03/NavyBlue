extends SceneTree

const SHIP_SCENE: PackedScene = preload("res://scenes/unit/ship.tscn")

var _failures := PackedStringArray()
var _database := ShipDatabase.new()
var _provider_units: Array[ShipUnit] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var arena := Node3D.new()
	root.add_child(arena)
	var ship := SHIP_SCENE.instantiate() as ShipUnit
	ship.setup(
		_database.get_ship("cl_tidebreaker"),
		&"ally",
		false,
		Color.WHITE
	)
	arena.add_child(ship)
	await process_frame
	ship.set_physics_process(false)
	ship.targeting.evaluation_interval_sec = 1.0
	ship.targeting.evaluation_jitter_sec = 0.0
	ship.configure_ai_target_provider(Callable(self, &"_get_provider_units"))
	ship.targeting.update_targeting(0.0)

	for _step in 6000:
		ship.targeting.update_targeting(0.1)

	_check(
		ship.targeting.target_evaluation_count >= 500
			and ship.targeting.target_evaluation_count <= 700,
		"targetless targeting keeps the one-second evaluation cadence"
	)
	_check(
		ship.targeting.target_change_count == 0,
		"targetless evaluations do not emit null-to-null target changes"
	)
	_check(
		ship.navigation.path_calculation_count == 0,
		"targetless evaluations do not force navigation recalculation"
	)

	var evaluation_count := ship.targeting.target_evaluation_count
	arena.queue_free()
	await process_frame
	print(
		"FLEET_AI_EVALUATION_CADENCE_TEST evaluations=%d failures=%d"
		% [
			evaluation_count,
			_failures.size(),
		]
	)
	quit(0 if _failures.is_empty() else 1)


func _get_provider_units() -> Array[ShipUnit]:
	return _provider_units


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("FLEET AI EVALUATION CADENCE: %s" % label)

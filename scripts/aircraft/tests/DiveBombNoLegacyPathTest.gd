extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_check(
		not FileAccess.file_exists(
			"res://scripts/aircraft/combat/DiveBombAttackController.gd"
		),
		"legacy squadron dive controller is removed"
	)
	_check(
		not FileAccess.file_exists(
			"res://scripts/aircraft/combat/DiveBombAccuracyResolver.gd"
		),
		"legacy accuracy resolver is removed"
	)
	var squadron_source := _read(
		"res://scripts/aircraft/AircraftSquadron.gd"
	)
	var scene_source := _read(
		"res://scenes/aircraft/aircraft_squadron.tscn"
	)
	var data_source := _read(
		"res://scripts/data/aircraft/DiveBomberCombatData.gd"
	)
	for forbidden in [
		"begin_dive_with_source",
		"select_dive_bomb_reference_aircraft",
		"DiveBombAttackController",
	]:
		_check(
			not squadron_source.contains(forbidden),
			"AircraftSquadron excludes %s" % forbidden
		)
	_check(
		not scene_source.contains("DiveBombAttackController"),
		"squadron scene excludes the legacy controller node"
	)
	for forbidden in [
		"base_dispersion_radius_m",
		"minimum_dispersion_radius_m",
		"dispersion_reduction_per_extra_aircraft_m",
		"automatic_release_distance_m",
		"dive_entry_distance_m",
	]:
		_check(
			not data_source.contains(forbidden),
			"DiveBomberCombatData excludes %s" % forbidden
		)
	_check(
		not squadron_source.contains("get_nodes_in_group(&\"ships\")"),
		"production dive targeting uses ShipRegistryService only"
	)
	_finish()


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	print("DIVE_BOMB_NO_LEGACY_PATH_TEST failures=%d" % _failures.size())
	for failure in _failures:
		push_error("DIVE LEGACY: %s" % failure)
	quit(0 if _failures.is_empty() else 1)

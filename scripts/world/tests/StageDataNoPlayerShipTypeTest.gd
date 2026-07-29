extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	var stage := StageData.new()
	_check(
		not _has_property(stage, &"player_ship_id"),
		"StageData has no production player ship field"
	)
	_check(
		stage.test_player_ship_override.is_empty(),
		"test override is empty by default"
	)
	var test_level := load(
		"res://resources/stages/test_level.tres"
	) as StageData
	_check(
		test_level.test_player_ship_override.is_empty(),
		"normal test_level has no ship override"
	)
	_check(
		not test_level.player_spawn.has("ship_id"),
		"normal player spawn contains no ship type"
	)
	_finish()


func _has_property(value: Object, property_name: StringName) -> bool:
	for property in value.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	for failure in _failures:
		push_error("STAGE DATA NO PLAYER SHIP TYPE TEST: %s" % failure)
	print(
		"STAGE_DATA_NO_PLAYER_SHIP_TYPE_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)

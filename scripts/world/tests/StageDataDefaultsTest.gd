extends SceneTree

const TEST_STAGE_PATHS := [
	"res://resources/stages/tests/weapon_combat_test.tres",
	"res://resources/stages/tests/carrier_player_test.tres",
	"res://resources/stages/tests/carrier_ai_test.tres",
	"res://resources/stages/tests/battle_loop_test.tres",
]

var _failures: Array[String] = []


func _initialize() -> void:
	var defaults := StageData.new()
	_check(
		not _has_property(defaults, &"player_ship_id"),
		"StageData does not own the player ship type"
	)
	_check(
		defaults.test_player_ship_override.is_empty(),
		"StageData test ship override defaults to empty"
	)
	for path in TEST_STAGE_PATHS:
		var stage := load(path) as StageData
		_check(stage != null, "stage loads: %s" % path)
		if stage != null:
			_check(
				stage.validate().is_empty(),
				"stage validates: %s" % stage.id
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
		push_error("STAGE DATA DEFAULTS TEST: %s" % failure)
	print(
		"STAGE_DATA_DEFAULTS_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)

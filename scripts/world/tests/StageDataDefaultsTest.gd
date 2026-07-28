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
		defaults.player_ship_id == GameConfig.DEFAULT_PLAYER_SHIP_ID,
		"StageData uses the shared default player ship"
	)
	_check(
		defaults.player_ship_id != "cv_seabastion",
		"StageData defaults are not carrier-specific"
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

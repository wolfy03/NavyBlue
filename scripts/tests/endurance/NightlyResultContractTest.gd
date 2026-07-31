extends SceneTree

const RUNNER_PATH := \
	"res://scripts/tests/endurance/run_endurance_validation.ps1"

var _failures := PackedStringArray()


func _initialize() -> void:
	var file := FileAccess.open(RUNNER_PATH, FileAccess.READ)
	_check(file != null, "nightly PowerShell runner is readable")
	var source := file.get_as_text() if file != null else ""
	if file != null:
		file.close()
	_check(
		source.contains("FLEET_AI_|AI_LONG_RUN|BATTLE_ENDURANCE"),
		"runner captures FleetAI and BattleAI summary lines"
	)
	_check(
		source.contains('$summaryMissing')
			and source.contains("-not (Test-Path $resultPath)"),
		"missing summary and missing result files fail validation"
	)
	_check(
		source.contains("ObjectDB instances leaked")
			and source.contains("resources still in use")
			and source.contains("exit 124"),
		"runner fails leak diagnostics and timeouts"
	)
	print("NIGHTLY_RESULT_CONTRACT_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("NIGHTLY RESULT CONTRACT: %s" % label)

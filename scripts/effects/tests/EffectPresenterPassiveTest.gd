extends SceneTree

const PRESENTER_PATH := "res://scripts/effects/CombatEffectPresenter.gd"

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var file := FileAccess.open(PRESENTER_PATH, FileAccess.READ)
	_check(file != null, "presenter source is readable")
	var source := file.get_as_text() if file != null else ""
	for forbidden in [
		"DamageResolver",
		"apply_damage(",
		"resolve_damage(",
		"resolve_impact(",
		"current_health",
	]:
		_check(
			source.find(forbidden) < 0,
			"presenter does not own gameplay operation %s" % forbidden
		)
	_check(
		source.find("ProjectileImpactResult") >= 0
			and source.find("EffectRequest.new()") >= 0,
		"presenter translates typed impact results into effect requests"
	)
	print(
		"EFFECT_PRESENTER_PASSIVE_TEST failures=%d"
		% _failures.size()
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("EFFECT PRESENTER PASSIVE: %s" % label)

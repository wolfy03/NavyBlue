extends SceneTree

const EFFECT_SCENES: Array[PackedScene] = [
	preload("res://scenes/effects/shell_ship_impact_effect.tscn"),
	preload("res://scenes/effects/torpedo_ship_impact_effect.tscn"),
	preload("res://scenes/effects/fighter_tracer_effect.tscn"),
]

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	for scene in EFFECT_SCENES:
		var node := scene.instantiate()
		_check(
			node is PooledEffectBase,
			"%s root uses PooledEffectBase" % scene.resource_path
		)
		if node != null:
			node.queue_free()
	await process_frame
	print("POOLED_EFFECT_COVERAGE_AUDIT_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("POOLED EFFECT COVERAGE: %s" % label)

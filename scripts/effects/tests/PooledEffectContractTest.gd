extends SceneTree

const TRACER_SCENE: PackedScene = preload(
	"res://scenes/effects/fighter_tracer_effect.tscn"
)

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var parent := Node3D.new()
	root.add_child(parent)
	var effect := TRACER_SCENE.instantiate() as PooledEffectBase
	_check(effect != null, "effect root uses typed pooled contract")
	if effect != null:
		parent.add_child(effect)
		await process_frame
		var request := EffectRequest.new()
		request.position = Vector3(1.0, 2.0, 3.0)
		request.end_position = Vector3(1.0, 2.0, -30.0)
		request.rounds_fired = 8
		request.tracer_interval = 3
		effect.activate(request)
		_check(effect.active and effect.visible, "activate exposes effect")
		effect.deactivate()
		_check(
			not effect.active and not effect.visible,
			"deactivate resets reusable state"
		)
	var pool := ReusableEffectPool.new()
	pool.setup(TRACER_SCENE, 1)
	parent.add_child(pool)
	await process_frame
	var pooled_request := EffectRequest.new()
	pooled_request.position = Vector3.ZERO
	pooled_request.end_position = Vector3(0.0, 0.0, -20.0)
	pooled_request.rounds_fired = 8
	pooled_request.tracer_interval = 3
	var first := pool.spawn_effect(pooled_request)
	var second := pool.spawn_effect(pooled_request)
	_check(
		first != null and first == second and second.active,
		"typed pool resets and reuses its bounded instance"
	)
	pool.clear_pool()
	parent.queue_free()
	await process_frame
	print("POOLED_EFFECT_CONTRACT_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("POOLED EFFECT CONTRACT: %s" % label)

extends SceneTree

const SHELL_SCENE: PackedScene = preload(
	"res://scenes/weapon/projectiles/shell_projectile.tscn"
)

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var parent := Node3D.new()
	root.add_child(parent)
	var pool := ProjectilePoolService.new()
	_check(not pool.setup(null), "missing ObjectPool setup fails")
	var result := pool.acquire_result(SHELL_SCENE, parent, true)
	_check(
		result.instance != null
			and result.ownership \
				== ProjectileCreationOwnership.Type.FACTORY_INSTANCE,
		"fallback has factory ownership"
	)
	var instance := result.instance
	_check(pool.release(instance, result.ownership), "fallback release succeeds")
	await process_frame
	_check(
		pool.pool_release_count == 0
			and pool.factory_instance_release_count == 1
			and pool.get_pool_outstanding_count() == 0,
		"fallback never enters ObjectPool release accounting"
	)
	parent.queue_free()
	await process_frame
	print("PROJECTILE_FALLBACK_OWNERSHIP_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("PROJECTILE FALLBACK OWNERSHIP: %s" % label)

extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	var pool := ProjectilePoolService.new()
	pool.pool_acquire_count = 8
	pool.pool_release_count = 3
	_check(
		pool.get_pool_outstanding_count() == 5,
		"outstanding count means successful pool acquires minus releases"
	)
	pool.pool_release_count = 8
	_check(
		pool.get_pool_outstanding_count() == 0,
		"balanced pool activity has no outstanding leases"
	)
	pool.instantiate_fallback_count = 2
	pool.factory_instance_release_count = 2
	_check(
		pool.get_pool_outstanding_count() == 0,
		"factory fallback ownership does not alter pool lease balance"
	)
	print("POOL_METRIC_SEMANTICS_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("POOL METRIC SEMANTICS: %s" % label)

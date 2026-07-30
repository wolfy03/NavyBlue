extends SceneTree

const SHELL_SCENE: PackedScene = preload(
	"res://scenes/weapon/projectiles/shell_projectile.tscn"
)
const SHELL_DATA: ProjectileData = preload(
	"res://resources/projectiles/small_ap_shell.tres"
)

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var services := BattleTestServices.create(self)
	var lifecycle := ProjectileLifecycle.new()
	_check(
		lifecycle.configure(SHELL_DATA, services),
		"lifecycle configures"
	)
	var context := ProjectileLaunchContext.new()
	_check(lifecycle.begin_launch(context), "lifecycle begins launch")
	_check(
		lifecycle.mark_impact_once()
			and not lifecycle.mark_impact_once(),
		"impact guard is one-shot"
	)
	lifecycle.reset()
	_check(
		not lifecycle.configured
			and lifecycle.projectile_data == null
			and not lifecycle.impact_emitted,
		"lifecycle reset clears common state"
	)

	var parent := Node3D.new()
	root.add_child(parent)
	var pool := ProjectilePoolService.new()
	pool.setup(null)
	var no_fallback := pool.acquire_result(SHELL_SCENE, parent, false)
	_check(
		no_fallback.instance == null
			and no_fallback.error == &"pool_acquire_failed",
		"pool acquire failure is typed"
	)
	var fallback := pool.acquire_result(SHELL_SCENE, parent, true)
	_check(
		fallback.instance != null and not fallback.used_pool,
		"instantiate fallback is explicit"
	)
	if fallback.instance != null:
		pool.release(fallback.instance)
	await process_frame
	parent.queue_free()
	await process_frame
	print(
		"PROJECTILE_LIFECYCLE_SERVICE_TEST failures=%d"
		% _failures.size()
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("PROJECTILE LIFECYCLE: %s" % label)

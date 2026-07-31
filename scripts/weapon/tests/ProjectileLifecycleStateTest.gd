extends SceneTree

const SHELL_DATA: ProjectileData = preload(
	"res://resources/projectiles/small_ap_shell.tres"
)

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var services := BattleTestServices.create(self)
	var lifecycle := ProjectileLifecycle.new()
	var context := ProjectileLaunchContext.new()
	_check(
		lifecycle.state == ProjectileLifecycle.State.UNCONFIGURED,
		"new lifecycle is unconfigured"
	)
	_check(not lifecycle.begin_launch(context), "launch before configure fails")
	_check(
		lifecycle.configure(SHELL_DATA, services)
			and lifecycle.state == ProjectileLifecycle.State.CONFIGURED,
		"configure enters configured state"
	)
	_check(
		lifecycle.begin_launch(context)
			and lifecycle.state == ProjectileLifecycle.State.LAUNCHED,
		"launch enters launched state"
	)
	_check(not lifecycle.begin_launch(context), "second launch fails")
	_check(
		lifecycle.mark_impact_once()
			and lifecycle.state == ProjectileLifecycle.State.IMPACTED,
		"impact enters impacted state"
	)
	_check(not lifecycle.mark_impact_once(), "second impact fails")
	_check(
		lifecycle.mark_released()
			and lifecycle.state == ProjectileLifecycle.State.RELEASED,
		"release enters released state"
	)
	_check(not lifecycle.begin_launch(context), "released lifecycle cannot launch")
	lifecycle.reset()
	_check(
		lifecycle.state == ProjectileLifecycle.State.UNCONFIGURED
			and not lifecycle.configured
			and not lifecycle.launched,
		"reset returns to unconfigured state"
	)
	print("PROJECTILE_LIFECYCLE_STATE_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("PROJECTILE LIFECYCLE STATE: %s" % label)

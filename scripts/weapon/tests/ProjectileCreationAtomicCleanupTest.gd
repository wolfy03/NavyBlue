extends SceneTree

const SHELL_DATA: ProjectileData = preload(
	"res://resources/projectiles/small_ap_shell.tres"
)

class ConfigureFailureProjectile extends ProjectileBase:
	func configure(
			_data: ProjectileData,
			_services: BattleServices
	) -> bool:
		return false


class LaunchFailureProjectile extends ProjectileBase:
	func launch(_context: ProjectileLaunchContext) -> bool:
		return false


var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var parent := Node3D.new()
	root.add_child(parent)
	var services := BattleTestServices.create(self)
	var context := ProjectileLaunchContext.new()

	var invalid_scene := PackedScene.new()
	var invalid_root := Node3D.new()
	invalid_scene.pack(invalid_root)
	invalid_root.free()
	var invalid_result := services.projectile_factory.create_result(
		invalid_scene,
		parent,
		SHELL_DATA,
		context
	)
	await process_frame
	_check(
		invalid_result.error \
			== ProjectileCreationResult.ErrorCode.INVALID_PROJECTILE_ROOT
			and parent.get_child_count() == 0
			and services.projectile_pool.get_pool_outstanding_count() == 0,
		"invalid root is atomically discarded"
	)

	var configure_scene := PackedScene.new()
	var configure_root := ConfigureFailureProjectile.new()
	configure_scene.pack(configure_root)
	configure_root.free()
	var configure_result := services.projectile_factory.create_result(
		configure_scene,
		parent,
		SHELL_DATA,
		context
	)
	_check(
		configure_result.error \
			== ProjectileCreationResult.ErrorCode.CONFIGURE_FAILED
			and parent.get_child_count() == 0
			and services.projectile_pool.get_pool_outstanding_count() == 0,
		"configure failure returns the lease"
	)

	var launch_scene := PackedScene.new()
	var launch_root := LaunchFailureProjectile.new()
	launch_scene.pack(launch_root)
	launch_root.free()
	var launch_result := services.projectile_factory.create_result(
		launch_scene,
		parent,
		SHELL_DATA,
		context
	)
	_check(
		launch_result.error \
			== ProjectileCreationResult.ErrorCode.LAUNCH_FAILED
			and parent.get_child_count() == 0
			and services.projectile_pool.get_pool_outstanding_count() == 0,
		"launch failure returns the lease"
	)
	parent.queue_free()
	var object_pool := root.get_node_or_null("ObjectPool")
	if object_pool != null:
		object_pool.call(&"clear_pool")
	services.shutdown()
	await process_frame
	await process_frame
	await process_frame
	print("PROJECTILE_CREATION_ATOMIC_CLEANUP_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("PROJECTILE CREATION ATOMIC CLEANUP: %s" % label)

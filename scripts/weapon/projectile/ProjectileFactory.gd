extends RefCounted
class_name ProjectileFactory

var pool_service: ProjectilePoolService
var battle_services: BattleServices
var allow_instantiate_fallback := true
var _invalid_root_warning_emitted := false


func setup(
		next_pool_service: ProjectilePoolService,
		next_battle_services: BattleServices
) -> bool:
	shutdown()
	if next_pool_service == null \
			or not next_pool_service.is_configured() \
			or next_battle_services == null:
		return false
	pool_service = next_pool_service
	battle_services = next_battle_services
	return true


func shutdown() -> void:
	pool_service = null
	battle_services = null
	_invalid_root_warning_emitted = false


func is_configured() -> bool:
	return pool_service != null \
		and pool_service.is_configured() \
		and battle_services != null


func create_result(
		scene: PackedScene,
		parent: Node,
		data: ProjectileData,
		context: ProjectileLaunchContext
) -> ProjectileCreationResult:
	var result := ProjectileCreationResult.new()
	if scene == null or parent == null or not is_instance_valid(parent) \
			or data == null or context == null or not is_configured():
		result.error = ProjectileCreationResult.ErrorCode.INVALID_ARGUMENT
		return result
	var acquire_result := pool_service.acquire_result(
		scene,
		parent,
		allow_instantiate_fallback
	)
	var node := acquire_result.instance
	result.used_pool = acquire_result.used_pool
	result.ownership = acquire_result.ownership
	if node == null:
		result.error = ProjectileCreationResult.ErrorCode.POOL_ACQUIRE_FAILED
		return result
	var projectile := node as ProjectileBase
	var rigid_projectile := node as WeaponProjectileBase
	if projectile == null and rigid_projectile == null:
		if not _invalid_root_warning_emitted:
			_invalid_root_warning_emitted = true
			push_warning(
				"Projectile scene root must inherit ProjectileBase "
				+ "or WeaponProjectileBase."
			)
		pool_service.discard_acquired_instance(
			node,
			acquire_result.ownership
		)
		result.error = ProjectileCreationResult.ErrorCode.INVALID_PROJECTILE_ROOT
		return result
	if projectile != null:
		if not projectile.configure(data, battle_services):
			_cleanup_failed_instance(projectile, acquire_result.ownership)
			result.error = ProjectileCreationResult.ErrorCode.CONFIGURE_FAILED
			return result
		projectile.lifecycle.set_creation_ownership(acquire_result.ownership)
		if not projectile.launch(context):
			_cleanup_failed_instance(projectile, acquire_result.ownership)
			result.error = ProjectileCreationResult.ErrorCode.LAUNCH_FAILED
			return result
		battle_services.events.emit_projectile_spawned(projectile)
		result.projectile = projectile
		return result
	if not rigid_projectile.configure(data, battle_services):
		_cleanup_failed_instance(rigid_projectile, acquire_result.ownership)
		result.error = ProjectileCreationResult.ErrorCode.CONFIGURE_FAILED
		return result
	rigid_projectile.lifecycle.set_creation_ownership(acquire_result.ownership)
	if not rigid_projectile.launch(context):
		_cleanup_failed_instance(rigid_projectile, acquire_result.ownership)
		result.error = ProjectileCreationResult.ErrorCode.LAUNCH_FAILED
		return result
	battle_services.events.emit_projectile_spawned(rigid_projectile)
	result.projectile = rigid_projectile
	return result


func _cleanup_failed_instance(
		instance: Node,
		ownership: ProjectileCreationOwnership.Type
) -> void:
	if instance == null or not is_instance_valid(instance):
		return
	if pool_service != null:
		pool_service.release(instance, ownership)
		return
	if instance is ProjectileBase:
		(instance as ProjectileBase).reset_for_pool()
	elif instance is WeaponProjectileBase:
		(instance as WeaponProjectileBase).reset_for_pool()
	instance.queue_free()

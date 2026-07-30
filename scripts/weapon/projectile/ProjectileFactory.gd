extends RefCounted
class_name ProjectileFactory

var pool_service: ProjectilePoolService
var battle_services: BattleServices
var allow_instantiate_fallback := true


func setup(
		next_pool_service: ProjectilePoolService,
		next_battle_services: BattleServices
) -> void:
	shutdown()
	pool_service = next_pool_service
	battle_services = next_battle_services


func shutdown() -> void:
	pool_service = null
	battle_services = null


func create_result(
		scene: PackedScene,
		parent: Node,
		data: ProjectileData,
		context: ProjectileLaunchContext
) -> ProjectileCreationResult:
	var result := ProjectileCreationResult.new()
	if scene == null or parent == null or not is_instance_valid(parent) \
			or data == null or context == null \
			or pool_service == null or battle_services == null:
		result.error = ProjectileCreationResult.ErrorCode.INVALID_ARGUMENT
		return result
	var acquire_result := pool_service.acquire_result(
		scene,
		parent,
		allow_instantiate_fallback
	)
	var node := acquire_result.instance
	result.used_pool = acquire_result.used_pool
	if node == null:
		result.error = ProjectileCreationResult.ErrorCode.POOL_ACQUIRE_FAILED
		return result
	var projectile := node as ProjectileBase
	var rigid_projectile := node as WeaponProjectileBase
	if projectile == null and rigid_projectile == null:
		push_error(
			"Projectile scene root must inherit ProjectileBase "
			+ "or WeaponProjectileBase."
		)
		if node != null:
			pool_service.release(node)
		result.error = ProjectileCreationResult.ErrorCode.INVALID_PROJECTILE_ROOT
		return result
	if projectile != null:
		if not projectile.configure(data, battle_services):
			pool_service.release(projectile)
			result.error = ProjectileCreationResult.ErrorCode.CONFIGURE_FAILED
			return result
		if not projectile.launch(context):
			result.error = ProjectileCreationResult.ErrorCode.LAUNCH_FAILED
			return result
		battle_services.events.emit_projectile_spawned(projectile)
		result.projectile = projectile
		return result
	if not rigid_projectile.configure(data, battle_services):
		pool_service.release(rigid_projectile)
		result.error = ProjectileCreationResult.ErrorCode.CONFIGURE_FAILED
		return result
	if not rigid_projectile.launch(context):
		result.error = ProjectileCreationResult.ErrorCode.LAUNCH_FAILED
		return result
	battle_services.events.emit_projectile_spawned(rigid_projectile)
	result.projectile = rigid_projectile
	return result

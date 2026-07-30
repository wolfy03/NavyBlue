extends RefCounted
class_name ProjectileFactory

var pool_service: ProjectilePoolService
var battle_services: BattleServices


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


func create(
		scene: PackedScene,
		parent: Node,
		data: ProjectileData,
		context: ProjectileLaunchContext
) -> Node3D:
	if scene == null or parent == null or not is_instance_valid(parent) \
			or data == null or context == null \
			or pool_service == null or battle_services == null:
		return null
	var node := pool_service.acquire(scene, parent)
	var projectile := node as ProjectileBase
	var rigid_projectile := node as WeaponProjectileBase
	if projectile == null and rigid_projectile == null:
		push_error(
			"Projectile scene root must inherit ProjectileBase "
			+ "or WeaponProjectileBase."
		)
		if node != null:
			pool_service.release(node)
		return null
	if projectile != null:
		projectile.configure(data, battle_services)
		projectile.launch(context)
		battle_services.events.emit_projectile_spawned(projectile)
		return projectile
	rigid_projectile.configure(data, battle_services)
	rigid_projectile.launch(context)
	battle_services.events.emit_projectile_spawned(rigid_projectile)
	return rigid_projectile

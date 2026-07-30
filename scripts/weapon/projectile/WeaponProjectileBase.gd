extends RigidBody3D
class_name WeaponProjectileBase

signal impact_resolved(result: ProjectileImpactResult)

var projectile_data: ProjectileData
var launch_context: ProjectileLaunchContext
var battle_services: BattleServices
var runtime_state := ProjectileRuntimeState.new()

var projectile_runtime_stats := WeaponRuntimeStats.new()
var source_team: StringName = FactionRelations.NEUTRAL
var source_ship_instance_id := 0
var source_weapon_id: StringName

var _source_actor_ref: WeakRef
var _base_despawn_requested := false
var _default_collision_layer := 1
var _default_collision_mask := 1


func _ready() -> void:
	_default_collision_layer = collision_layer
	_default_collision_mask = collision_mask


func configure(
		data: ProjectileData,
		services: BattleServices
) -> void:
	if data == null or services == null:
		push_error(
			"WeaponProjectileBase.configure requires data and BattleServices."
		)
		return
	projectile_data = data
	battle_services = services
	runtime_state = ProjectileRuntimeState.new()
	_on_configured()


func launch(context: ProjectileLaunchContext) -> void:
	if projectile_data == null or battle_services == null or context == null:
		push_error(
			"WeaponProjectileBase.launch called before valid configuration."
		)
		recycle_projectile()
		return
	launch_context = context
	projectile_runtime_stats = context.runtime_stats.duplicate_stats() \
		if context.runtime_stats != null else WeaponRuntimeStats.new()
	_apply_launch_source(
		context.source_actor,
		context.source_team,
		context.source_weapon_id
	)
	global_transform = context.initial_transform
	runtime_state.active = true
	_on_launched(context)


func reset_for_pool() -> void:
	_on_reset_for_pool()
	projectile_data = null
	launch_context = null
	battle_services = null
	runtime_state = ProjectileRuntimeState.new()
	projectile_runtime_stats = WeaponRuntimeStats.new()
	source_team = FactionRelations.NEUTRAL
	source_ship_instance_id = 0
	source_weapon_id = StringName()
	_source_actor_ref = null
	_base_despawn_requested = true


func recycle_projectile() -> void:
	if _base_despawn_requested:
		return
	_base_despawn_requested = true
	runtime_state.active = false
	var pool := battle_services.projectile_pool \
		if battle_services != null else null
	if pool != null and pool.release(self):
		return
	queue_free()


func emit_impact(result: ProjectileImpactResult) -> void:
	if result == null or runtime_state.impact_resolved:
		return
	runtime_state.impact_resolved = true
	result.projectile = self
	impact_resolved.emit(result)
	if battle_services != null:
		battle_services.events.emit_projectile_impact(result)


func get_source_actor() -> Node:
	return _source_actor_ref.get_ref() as Node \
		if _source_actor_ref != null else null


func get_source_ship() -> Node:
	return get_source_actor()


func on_spawned_from_pool() -> void:
	_base_despawn_requested = false
	projectile_data = null
	launch_context = null
	battle_services = null
	runtime_state = ProjectileRuntimeState.new()
	projectile_runtime_stats = WeaponRuntimeStats.new()
	source_team = FactionRelations.NEUTRAL
	source_ship_instance_id = 0
	source_weapon_id = StringName()
	_source_actor_ref = null
	collision_layer = _default_collision_layer
	collision_mask = _default_collision_mask
	show()
	set_process(true)
	set_physics_process(true)


func on_recycled_to_pool() -> void:
	reset_for_pool()
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = true
	collision_layer = 0
	collision_mask = 0
	hide()
	set_process(false)
	set_physics_process(false)


func _apply_launch_source(
		actor: Node,
		team: StringName,
		weapon_id: StringName
) -> void:
	source_team = team
	source_weapon_id = weapon_id
	_source_actor_ref = null
	source_ship_instance_id = 0
	if actor != null and is_instance_valid(actor):
		_source_actor_ref = weakref(actor)
		source_ship_instance_id = actor.get_instance_id()


func _on_configured() -> void:
	pass


func _on_launched(_context: ProjectileLaunchContext) -> void:
	push_error("WeaponProjectileBase._on_launched must be overridden.")


func _on_reset_for_pool() -> void:
	pass

func despawn() -> void:
	recycle_projectile()

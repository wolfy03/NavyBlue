extends RigidBody3D
class_name WeaponProjectileBase

signal impact_resolved(result: ProjectileImpactResult)

var lifecycle := ProjectileLifecycle.new()
var projectile_data: ProjectileData:
	get:
		return lifecycle.projectile_data
var launch_context: ProjectileLaunchContext:
	get:
		return lifecycle.launch_context
var battle_services: BattleServices:
	get:
		return lifecycle.battle_services
var runtime_state: ProjectileRuntimeState:
	get:
		return lifecycle.runtime_state

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
) -> bool:
	if not lifecycle.configure(data, services):
		push_error(
			"WeaponProjectileBase.configure requires data and BattleServices."
		)
		return false
	_on_configured()
	return true


func launch(context: ProjectileLaunchContext) -> bool:
	if not lifecycle.begin_launch(context):
		push_error(
			"WeaponProjectileBase.launch called before valid configuration."
		)
		recycle_projectile()
		return false
	projectile_runtime_stats = context.runtime_stats.duplicate_stats() \
		if context.runtime_stats != null else WeaponRuntimeStats.new()
	_apply_launch_source(
		context.source_actor,
		context.source_team,
		context.source_weapon_id
	)
	global_transform = context.initial_transform
	_on_launched(context)
	return true


func reset_for_pool() -> void:
	_on_reset_for_pool()
	lifecycle.reset()
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
	if result == null or not lifecycle.mark_impact_once():
		return
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
	lifecycle.reset()
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

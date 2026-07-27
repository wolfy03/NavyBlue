extends RigidBody3D
class_name WeaponProjectileBase

# Shared source attribution and pool lifecycle only. Concrete projectiles own
# gravity, depth, guidance, collision interpretation, and damage behavior.
# TODO: extract this lifecycle contract before adding CharacterBody3D missiles
# or Area3D mines; those types must not be forced to inherit RigidBody3D.

var projectile_data: ProjectileData
var projectile_runtime_stats := WeaponRuntimeStats.new()
var source_team: StringName = &"neutral"
var source_ship_instance_id := 0
var source_weapon_id: StringName
var _source_ship_ref: WeakRef
var _despawn_requested := false
var _default_collision_layer := 1
var _default_collision_mask := 1


func _ready() -> void:
	_default_collision_layer = collision_layer
	_default_collision_mask = collision_mask


func setup_projectile_data(data: ProjectileData) -> void:
	projectile_data = data


func launch_with_context(context: ProjectileLaunchContext) -> void:
	if context == null:
		return
	if projectile_data == null and context.source_projectile_data != null:
		setup_projectile_data(context.source_projectile_data)
	global_transform = context.initial_transform
	projectile_runtime_stats = context.runtime_stats.duplicate_stats() \
		if context.runtime_stats != null else WeaponRuntimeStats.new()
	_apply_launch_source(
		context.source_actor,
		context.source_team,
		context.source_weapon_id
	)


func _apply_launch_source(
		ship: Node,
		team: StringName,
		weapon_id: StringName
) -> void:
	source_team = team
	source_weapon_id = weapon_id
	_source_ship_ref = null
	source_ship_instance_id = 0
	if ship != null and is_instance_valid(ship):
		_source_ship_ref = weakref(ship)
		source_ship_instance_id = ship.get_instance_id()


func get_source_ship() -> Node:
	return _source_ship_ref.get_ref() as Node if _source_ship_ref != null else null


func despawn() -> void:
	if _despawn_requested:
		return
	_despawn_requested = true
	if has_node("/root/ObjectPool"):
		var recycled: bool = get_node("/root/ObjectPool").recycle(self)
		if recycled:
			return
	queue_free()


func on_spawned_from_pool() -> void:
	_despawn_requested = false
	projectile_data = null
	projectile_runtime_stats = WeaponRuntimeStats.new()
	source_team = &"neutral"
	source_ship_instance_id = 0
	source_weapon_id = StringName()
	_source_ship_ref = null
	collision_layer = _default_collision_layer
	collision_mask = _default_collision_mask
	freeze = false
	sleeping = false
	show()
	set_process(true)
	set_physics_process(true)


func on_recycled_to_pool() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = true
	collision_layer = 0
	collision_mask = 0
	source_team = &"neutral"
	source_ship_instance_id = 0
	source_weapon_id = StringName()
	_source_ship_ref = null
	projectile_data = null
	projectile_runtime_stats = WeaponRuntimeStats.new()
	hide()
	set_process(false)
	set_physics_process(false)

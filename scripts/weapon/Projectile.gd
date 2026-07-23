extends RigidBody3D
class_name Projectile

const LIFETIME_SECONDS := 30.0
const DEFAULT_AP_SHELL: ShellStats = preload("res://scripts/combat/default_ap_shell.tres")

signal ship_hit_resolved(result: DamageResult)

@export var water_height := 0.0
@export var base_water_splash_strength := 1.0
@export var min_water_splash_strength := 0.35
@export var max_water_splash_strength := 4.0
@export var velocity_strength_reference := 800.0
@export var shell_stats: ShellStats = DEFAULT_AP_SHELL
@export_range(0.0, 1.0, 0.01) var deck_normal_threshold: float = 0.65
@export_range(0.1, 1.0, 0.01) var end_section_ratio: float = 0.68
@export_range(0.1, 3.0, 0.05) var superstructure_height_ratio: float = 1.05

var team: StringName = &"neutral"
var age := 0.0
var previous_position := Vector3.ZERO
var previous_position_initialized := false
var water_impact_processed := false
var ship_impact_processed: bool = false
var last_travel_direction: Vector3 = Vector3.FORWARD
var _despawn_requested := false

func _ready() -> void:
	gravity_scale = 1.0
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	previous_position = global_position
	previous_position_initialized = true

func launch(start_velocity: Vector3, owner_team: StringName, fired_shell_stats: ShellStats = null) -> void:
	team = owner_team
	linear_velocity = start_velocity
	if start_velocity.length_squared() > 0.000001:
		last_travel_direction = start_velocity.normalized()
	if fired_shell_stats != null:
		shell_stats = fired_shell_stats
	age = 0.0
	water_impact_processed = false
	ship_impact_processed = false
	_despawn_requested = false
	previous_position = global_position
	previous_position_initialized = true


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if ship_impact_processed:
		return
	for contact_index: int in state.get_contact_count():
		var collider: Object = state.get_contact_collider_object(contact_index)
		var target_ship: Node3D = _find_ship_damage_target(collider)
		if target_ship == null:
			continue
		_process_ship_contact(state, contact_index, target_ship)
		return

func _physics_process(delta: float) -> void:
	if ship_impact_processed:
		return
	if linear_velocity.length_squared() > 0.000001:
		last_travel_direction = linear_velocity.normalized()
	age += delta
	var current_position := global_position
	if not previous_position_initialized:
		previous_position = current_position
		previous_position_initialized = true

	if not water_impact_processed and _try_process_water_impact(previous_position, current_position):
		despawn()
		return

	var ocean_manager := _get_ocean_manager()
	if ocean_manager != null and ocean_manager.has_method(&"is_underwater"):
		if bool(ocean_manager.call(&"is_underwater", current_position)):
			_emit_water_impact(current_position, _calculate_water_impact_strength())
			despawn()
			return
	elif current_position.y <= water_height:
		_emit_water_impact(current_position, _calculate_water_impact_strength())
		despawn()
		return

	if age >= LIFETIME_SECONDS:
		despawn()
		return

	previous_position = current_position


func _process_ship_contact(
		state: PhysicsDirectBodyState3D,
		contact_index: int,
		target_ship: Node3D
) -> void:
	ship_impact_processed = true
	var direction: Vector3 = last_travel_direction
	if direction.length_squared() <= 0.000001:
		direction = state.linear_velocity.normalized()
	if direction.length_squared() <= 0.000001:
		direction = -global_transform.basis.z.normalized()
	var hit_position: Vector3 = state.get_contact_local_position(contact_index)
	var hit_normal: Vector3 = state.get_contact_local_normal(contact_index).normalized()
	if hit_normal.length_squared() <= 0.000001:
		hit_normal = -direction
	elif hit_normal.dot(direction) > 0.0:
		hit_normal = -hit_normal

	var hit_info := HitInfo.new().setup(
		shell_stats,
		target_ship,
		hit_position,
		hit_normal,
		direction,
		_determine_armor_part(target_ship, hit_position, hit_normal)
	)
	var damage_result: DamageResult = DamageResolver.resolve_hit(hit_info)
	ship_hit_resolved.emit(damage_result)
	call_deferred(&"despawn")

func despawn() -> void:
	if _despawn_requested:
		return
	_despawn_requested = true
	_recycle_self()

func _recycle_self() -> void:
	if has_node("/root/ObjectPool"):
		var recycled: bool = get_node("/root/ObjectPool").recycle(self)
		if recycled:
			return
	queue_free()

func on_spawned_from_pool() -> void:
	_despawn_requested = false
	age = 0.0
	water_impact_processed = false
	ship_impact_processed = false
	previous_position = global_position
	previous_position_initialized = true
	freeze = false
	sleeping = false
	contact_monitor = true
	max_contacts_reported = 4

func on_recycled_to_pool() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = true


func _find_ship_damage_target(collider: Object) -> Node3D:
	if not collider is Node:
		return null
	var candidate: Node = collider as Node
	while candidate != null:
		if candidate is Node3D \
				and candidate.has_method(&"get_defense_stats") \
				and candidate.has_method(&"apply_damage"):
			return candidate as Node3D
		candidate = candidate.get_parent()
	return null


func _determine_armor_part(
		target_ship: Node3D,
		hit_position: Vector3,
		hit_normal: Vector3
) -> ArmorPart.Type:
	var local_position: Vector3 = target_ship.to_local(hit_position)
	var local_normal: Vector3 = (target_ship.global_transform.basis.inverse() * hit_normal).normalized()
	if local_normal.y >= deck_normal_threshold:
		return ArmorPart.Type.DECK

	var hull_size := Vector3(2.0, 1.0, 6.0)
	var ship_data: Variant = target_ship.get(&"ship_data")
	if ship_data != null:
		var configured_hull_size: Variant = ship_data.get(&"hull_size")
		if configured_hull_size is Vector3:
			hull_size = configured_hull_size
	if local_position.y >= hull_size.y * superstructure_height_ratio:
		return ArmorPart.Type.SUPERSTRUCTURE

	var end_threshold: float = hull_size.z * 0.5 * end_section_ratio
	if local_position.z <= -end_threshold:
		return ArmorPart.Type.BOW
	if local_position.z >= end_threshold:
		return ArmorPart.Type.STERN
	return ArmorPart.Type.BELT


func _try_process_water_impact(from_position: Vector3, to_position: Vector3) -> bool:
	var ocean_manager := _get_ocean_manager()
	if ocean_manager == null:
		return false
	if not ocean_manager.has_method(&"did_cross_water_surface"):
		return false
	if not bool(ocean_manager.call(&"did_cross_water_surface", from_position, to_position)):
		return false

	var hit: RefCounted = ocean_manager.call(&"get_surface_intersection_hit", from_position, to_position)
	if hit == null or not bool(hit.get(&"hit")):
		return false

	water_impact_processed = true
	var interaction := _get_ocean_interaction()
	if interaction != null and interaction.has_method(&"register_impact_at"):
		interaction.call(
			&"register_impact_at",
			hit.get(&"position") as Vector3,
			_calculate_water_impact_strength(),
			linear_velocity,
			hit.get(&"normal") as Vector3,
			self
		)
	_emit_water_impact(hit.get(&"position") as Vector3, _calculate_water_impact_strength())
	return true

func _emit_water_impact(position: Vector3, strength: float) -> void:
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").projectile_water_impact.emit(position, strength)


func _calculate_water_impact_strength() -> float:
	var speed_factor := clampf(linear_velocity.length() / maxf(velocity_strength_reference, 0.001), 0.25, 3.0)
	var mass_factor := sqrt(maxf(mass, 0.1))
	var strength := base_water_splash_strength * mass_factor * speed_factor
	return clampf(strength, min_water_splash_strength, max_water_splash_strength)


func _get_ocean_manager() -> Node:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group("ocean_manager")


func _get_ocean_interaction() -> Node:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group("ocean_interaction")

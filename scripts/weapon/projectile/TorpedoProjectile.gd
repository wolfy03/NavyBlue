extends "res://scripts/weapon/projectile/WeaponProjectileBase.gd"
class_name TorpedoProjectile

signal hit_resolved(result: DamageResult)

var torpedo_data: TorpedoProjectileData
var speed_mps := 0.0
var travelled_distance_m := 0.0
var age_seconds := 0.0
var armed := false
var launch_position := Vector3.ZERO
var water_height_m := 0.0
var impact_processed := false
var target_ref: WeakRef
var previous_position := Vector3.ZERO


func _ready() -> void:
	super._ready()
	gravity_scale = 0.0
	contact_monitor = true
	max_contacts_reported = 8
	continuous_cd = true
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func setup_projectile_data(data: ProjectileData) -> void:
	super.setup_projectile_data(data)
	torpedo_data = data as TorpedoProjectileData


func launch_with_context(context: ProjectileLaunchContext) -> void:
	super.launch_with_context(context)
	if torpedo_data == null or context == null:
		push_warning("Torpedo launch requires TorpedoProjectileData and context.")
		despawn()
		return
	target_ref = weakref(context.target) \
		if context.target != null and is_instance_valid(context.target) else null
	launch_position = global_position
	water_height_m = _resolve_water_height()
	global_position.y = water_height_m - torpedo_data.running_depth_m
	speed_mps = torpedo_data.launch_speed_mps
	travelled_distance_m = 0.0
	age_seconds = 0.0
	armed = false
	impact_processed = false
	previous_position = global_position
	linear_velocity = -global_transform.basis.z.normalized() * speed_mps


func _physics_process(delta: float) -> void:
	if impact_processed or torpedo_data == null:
		return
	if armed and _try_process_ship_proximity(previous_position, global_position):
		return
	age_seconds += delta
	speed_mps = move_toward(
		speed_mps,
		torpedo_data.max_speed_mps,
		torpedo_data.acceleration_mps2 * delta
	)
	_update_guidance(delta)
	var direction := -global_transform.basis.z.normalized()
	linear_velocity = direction * speed_mps
	var next_position := global_position
	next_position.y = water_height_m - torpedo_data.running_depth_m
	global_position = next_position
	previous_position = global_position
	travelled_distance_m += speed_mps * delta
	if not armed and travelled_distance_m >= torpedo_data.arming_distance_m:
		armed = true
	var maximum_range := torpedo_data.maximum_range_m
	if age_seconds >= torpedo_data.lifetime_seconds \
			or (maximum_range > 0.0 and travelled_distance_m >= maximum_range):
		despawn()


func _update_guidance(delta: float) -> void:
	if torpedo_data.max_turn_rate_deg_sec <= 0.0 or target_ref == null:
		return
	var target := target_ref.get_ref() as Node3D
	if target == null or not is_instance_valid(target):
		target_ref = null
		return
	var direction := target.global_position - global_position
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		return
	var desired_yaw := atan2(-direction.x, -direction.z)
	rotation.y = rotate_toward(
		rotation.y,
		desired_yaw,
		deg_to_rad(torpedo_data.max_turn_rate_deg_sec) * delta
	)


func _on_body_entered(body: Node) -> void:
	if impact_processed or not armed:
		return
	var target_ship := _find_ship_target(body)
	if target_ship == null or target_ship == get_source_ship() \
			or not FactionRelations.are_hostile(source_team, target_ship.team):
		return
	_resolve_ship_hit(target_ship)


func _try_process_ship_proximity(
		segment_start: Vector3,
		segment_end: Vector3
) -> bool:
	if get_tree() == null:
		return false
	for value in get_tree().get_nodes_in_group(&"ships"):
		var target_ship := value as ShipUnit
		if target_ship == null or target_ship == get_source_ship() \
				or not target_ship.is_alive() \
				or not FactionRelations.are_hostile(source_team, target_ship.team):
			continue
		var start_local := target_ship.to_local(segment_start)
		var end_local := target_ship.to_local(segment_end)
		var half_extents := target_ship.ship_data.hull_size * 0.5
		if _segment_intersects_hull_xz(
			start_local,
			end_local,
			Vector2(half_extents.x + 0.75, half_extents.z + 0.75)
		):
			_resolve_ship_hit(target_ship)
			return true
	return false


func _resolve_ship_hit(target_ship: ShipUnit) -> void:
	if impact_processed or target_ship == null:
		return
	impact_processed = true
	var direction := -global_transform.basis.z.normalized()
	var hit_info := HitInfo.new()
	hit_info.target_ship = target_ship
	hit_info.hit_position = global_position
	hit_info.hit_normal = -direction
	hit_info.shell_direction = direction
	hit_info.armor_part = _determine_underwater_section(
		target_ship,
		global_position
	)
	hit_info.damage_type = DamageType.Type.TORPEDO
	hit_info.torpedo_data = torpedo_data
	hit_info.projectile_info = {
		"projectile_id": torpedo_data.id,
		"projectile_type": "torpedo",
		"damage": torpedo_data.direct_damage + torpedo_data.explosion_damage,
		"source_ship_instance_id": source_ship_instance_id,
		"weapon_id": source_weapon_id,
	}
	hit_info.set_damage_source(
		get_source_ship(),
		source_ship_instance_id,
		source_weapon_id
	)
	var result := DamageResolver.resolve_hit(hit_info)
	hit_resolved.emit(result)
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").torpedo_hit.emit(self, target_ship, result)
	call_deferred(&"despawn")


func _segment_intersects_hull_xz(
		start_local: Vector3,
		end_local: Vector3,
		half_extents: Vector2
) -> bool:
	var start := Vector2(start_local.x, start_local.z)
	var end := Vector2(end_local.x, end_local.z)
	var direction := end - start
	var minimum_time := 0.0
	var maximum_time := 1.0
	for axis in 2:
		var start_axis := start[axis]
		var direction_axis := direction[axis]
		var extent := half_extents[axis]
		if absf(direction_axis) <= 0.00001:
			if start_axis < -extent or start_axis > extent:
				return false
			continue
		var inverse_direction := 1.0 / direction_axis
		var first_time := (-extent - start_axis) * inverse_direction
		var second_time := (extent - start_axis) * inverse_direction
		if first_time > second_time:
			var swap := first_time
			first_time = second_time
			second_time = swap
		minimum_time = maxf(minimum_time, first_time)
		maximum_time = minf(maximum_time, second_time)
		if minimum_time > maximum_time:
			return false
	return true


func _find_ship_target(body: Node) -> ShipUnit:
	var candidate := body
	while candidate != null:
		if candidate is ShipUnit:
			return candidate as ShipUnit
		candidate = candidate.get_parent()
	return null


func _determine_underwater_section(
		target_ship: ShipUnit,
		hit_position: Vector3
) -> ArmorPart.Type:
	var local_position := target_ship.to_local(hit_position)
	var hull_length := target_ship.ship_data.hull_size.z
	var section_threshold := hull_length * 0.3
	if local_position.z < -section_threshold:
		return ArmorPart.Type.BOW
	if local_position.z > section_threshold:
		return ArmorPart.Type.STERN
	return ArmorPart.Type.BELT


func _resolve_water_height() -> float:
	if get_tree() == null:
		return 0.0
	var bounds := get_tree().get_first_node_in_group(&"battlefield_bounds") \
		as BattlefieldBounds
	return bounds.get_sea_level_m() if bounds != null else 0.0


func on_spawned_from_pool() -> void:
	super.on_spawned_from_pool()
	torpedo_data = null
	speed_mps = 0.0
	travelled_distance_m = 0.0
	age_seconds = 0.0
	armed = false
	impact_processed = false
	target_ref = null
	previous_position = global_position
	gravity_scale = 0.0
	contact_monitor = true
	max_contacts_reported = 8


func on_recycled_to_pool() -> void:
	super.on_recycled_to_pool()
	torpedo_data = null
	target_ref = null

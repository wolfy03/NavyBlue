extends Node
class_name ShipCombat

enum AimMode {
	FORWARD,
	MANUAL_RELATIVE_BEARING,
	TRACK_WORLD_TARGET,
}

## Who authored the current aim command. AI predictive fire-control and its
## difficulty error model apply ONLY to AimSource.AI; player manual aim always
## uses the exact point or bearing the player set.
enum AimSource {
	PLAYER_MANUAL,
	PLAYER_AUTO,
	AI,
}

var target
var aim_point := Vector3.ZERO
var has_aim_point := false
var aim_mode: AimMode = AimMode.FORWARD
var aim_source: AimSource = AimSource.PLAYER_MANUAL
var manual_azimuth_rad := 0.0
var manual_elevation_rad := 0.0
var _manual_aim_command: ShipManualAimCommand
var _ai_fire_control: ShipGunneryFireControl
var _ai_fire_control_hooks_active := false
var weapon_mounts: Array[WeaponMount] = []
# Deprecated: compatibility only. Do not use in new code.
var turrets: Array = []
var owner_ship: ShipUnit


func setup(next_owner_ship: ShipUnit, next_weapon_mounts: Array) -> void:
	var replaces_existing_groups := not weapon_mounts.is_empty()
	if replaces_existing_groups:
		_release_ai_fire_control_hooks()
		if _ai_fire_control != null:
			_ai_fire_control.clear_tracking_target(&"weapon_groups_replaced")
	owner_ship = next_owner_ship
	weapon_mounts.clear()
	for mount_value: Variant in next_weapon_mounts:
		if mount_value == null or not is_instance_valid(mount_value):
			continue
		var mount := mount_value as WeaponMount
		if mount != null:
			weapon_mounts.append(mount)
	turrets.assign(get_weapons_by_type(WeaponTypes.Type.CANNON))


func set_target(next_target) -> void:
	target = next_target
	if next_target != null:
		aim_mode = AimMode.TRACK_WORLD_TARGET


func clear_target() -> void:
	target = null
	has_aim_point = false
	aim_mode = AimMode.FORWARD
	aim_source = AimSource.PLAYER_MANUAL
	_manual_aim_command = null
	_release_ai_fire_control_hooks()
	if _ai_fire_control != null:
		_ai_fire_control.clear_tracking_target(&"combat_clear_target")
	for mount_value: Variant in weapon_mounts:
		var mount := _as_valid_weapon_mount(mount_value)
		if mount != null:
			mount.clear_aim()


## AI engagement entry point: tracks the target through the predictive
## fire-control pipeline instead of aiming at its current position.
func set_ai_engagement_target(target_ship: ShipUnit) -> void:
	if target_ship == null or not is_instance_valid(target_ship):
		return
	var same_target: bool = aim_source == AimSource.AI \
		and aim_mode == AimMode.TRACK_WORLD_TARGET \
		and target != null \
		and is_instance_valid(target) \
		and target == target_ship \
		and (_ai_fire_control == null \
			or _ai_fire_control.is_tracking_target(target_ship))
	target = target_ship
	aim_mode = AimMode.TRACK_WORLD_TARGET
	aim_source = AimSource.AI
	_manual_aim_command = null
	aim_point = target_ship.global_position
	has_aim_point = true
	if same_target:
		return
	_release_ai_fire_control_hooks()
	_ensure_ai_fire_control()
	_ai_fire_control.begin_tracking_target(target_ship)


func set_aim_point(world_point: Vector3) -> void:
	_release_ai_fire_control_hooks()
	if _ai_fire_control != null:
		_ai_fire_control.clear_tracking_target(&"player_world_aim")
	aim_point = world_point
	has_aim_point = true
	aim_mode = AimMode.TRACK_WORLD_TARGET
	aim_source = AimSource.PLAYER_MANUAL
	_manual_aim_command = null
	for mount_value: Variant in weapon_mounts:
		var mount := _as_valid_weapon_mount(mount_value)
		if mount != null:
			mount.aim_at(world_point)


func apply_manual_aim_command(command: ShipManualAimCommand) -> void:
	if command == null:
		return
	_manual_aim_command = command.duplicate_command()
	manual_azimuth_rad = command.local_azimuth_rad
	manual_elevation_rad = command.elevation_rad
	target = null
	aim_mode = AimMode.MANUAL_RELATIVE_BEARING
	aim_source = AimSource.PLAYER_MANUAL
	has_aim_point = true
	_release_ai_fire_control_hooks()
	if _ai_fire_control != null:
		_ai_fire_control.clear_tracking_target(&"player_manual_aim")
	_update_manual_relative_aim_point()


func get_manual_aim_command() -> ShipManualAimCommand:
	return _manual_aim_command.duplicate_command() \
		if aim_mode == AimMode.MANUAL_RELATIVE_BEARING \
		and _manual_aim_command != null else null


func is_manual_relative_aim_active() -> bool:
	return aim_mode == AimMode.MANUAL_RELATIVE_BEARING \
		and _manual_aim_command != null


func get_manual_aim_world_direction() -> Vector3:
	if owner_ship == null or not is_instance_valid(owner_ship):
		return Vector3.ZERO
	var local_direction := Vector3(
		sin(manual_azimuth_rad) * cos(manual_elevation_rad),
		sin(manual_elevation_rad),
		-cos(manual_azimuth_rad) * cos(manual_elevation_rad)
	).normalized()
	return (owner_ship.global_transform.basis * local_direction) \
		.normalized()


func adjust_turret_pitch(delta_degrees: float) -> void:
	for mount in get_weapons_by_type(WeaponTypes.Type.CANNON):
		mount.adjust_pitch(delta_degrees)


func fire_weapon_type(weapon_type: WeaponTypes.Type) -> int:
	var fired_count := 0
	if weapon_type == WeaponTypes.Type.CANNON \
			and aim_source == AimSource.AI:
		var ai_target := _get_ai_fire_control_target()
		if ai_target == null:
			return 0
		_ensure_ai_fire_control()
		var cannon_mounts := get_weapons_by_type(WeaponTypes.Type.CANNON)
		_ai_fire_control.begin_salvo_for_mounts(cannon_mounts)
	for mount_value: Variant in weapon_mounts:
		var mount := _as_valid_weapon_mount(mount_value)
		if mount == null or mount.get_weapon_type() != weapon_type:
			continue
		if weapon_type == WeaponTypes.Type.CANNON \
				and aim_source == AimSource.AI \
				and not _ai_fire_control.has_solution_for_mount(mount):
			continue
		if mount.fire():
			fired_count += 1
	return fired_count


func fire_cannons() -> int:
	return fire_weapon_type(WeaponTypes.Type.CANNON)


func fire_torpedoes() -> int:
	return fire_weapon_type(WeaponTypes.Type.TORPEDO)


func fire_torpedoes_at(
		target_ship: ShipUnit,
		bounds: BattlefieldBounds = null,
		minimum_hit_probability: float = 0.35
) -> int:
	if owner_ship == null or target_ship == null or not target_ship.is_alive():
		return 0
	var fired_count := 0
	for mount in get_weapons_by_type(WeaponTypes.Type.TORPEDO):
		var data := mount.weapon_data.projectile_data as TorpedoProjectileData
		if data == null:
			continue
		var torpedo_speed := mount.get_modified_projectile_speed(
			data.max_speed_mps
		)
		var lead_point_value: Variant = calculate_intercept_point(
			mount.global_position,
			target_ship.global_position,
			target_ship.velocity,
			torpedo_speed
		)
		if lead_point_value == null:
			continue
		var lead_point := lead_point_value as Vector3
		lead_point.y = owner_ship.global_position.y
		var effective_range := mount.get_range_m()
		if data.maximum_range_m > 0.0:
			effective_range = minf(
				effective_range,
				data.maximum_range_m * maxf(
					mount.runtime_stats.range_multiplier,
					0.0
				)
			)
		if effective_range <= 0.0 \
				or CombatGeometryXZ.distance_xz(
					mount.global_position,
					lead_point
				) > effective_range:
			continue
		if bounds != null and not bounds.is_inside_bounds(lead_point):
			continue
		if _estimate_torpedo_hit_probability(
			mount.global_position,
			target_ship,
			torpedo_speed
		) < minimum_hit_probability:
			continue
		mount.aim_at(lead_point)
		if mount.fire():
			fired_count += 1
	return fired_count


func fire_all() -> void:
	fire_cannons()


func update_weapon_mounts(next_owner_ship: Node3D, use_default_aim: bool) -> void:
	if aim_mode == AimMode.MANUAL_RELATIVE_BEARING:
		_update_manual_relative_aim_point()
	elif aim_mode == AimMode.TRACK_WORLD_TARGET \
			and target != null \
			and is_instance_valid(target) \
			and target is Node3D:
		aim_point = (target as Node3D).global_position
	if not has_aim_point and use_default_aim and next_owner_ship != null:
		aim_mode = AimMode.FORWARD
		aim_point = next_owner_ship.global_position \
			+ -next_owner_ship.global_transform.basis.z * 60.0
		has_aim_point = true
	if not has_aim_point:
		return
	var ai_target := _get_ai_fire_control_target()
	if ai_target != null:
		_update_ai_fire_control(ai_target)
		for mount_value: Variant in weapon_mounts:
			var mount := _as_valid_weapon_mount(mount_value)
			if mount == null:
				continue
			if mount is CannonMount:
				# Cannons track their weapon group's predictive, salvo-biased
				# solution; torpedo mounts keep their own lead inside
				# fire_torpedoes_at and other types keep the raw aim point.
				mount.aim_at(
					_ai_fire_control.get_aim_point_for_mount(mount, aim_point)
				)
			else:
				mount.aim_at(aim_point)
		return
	_release_ai_fire_control_hooks()
	for mount_value: Variant in weapon_mounts:
		var mount := _as_valid_weapon_mount(mount_value)
		if mount != null:
			# All aim modes fire at the shared aim point: for manual bearing it
			# already reflects the clicked distance (clamped to range), so mounts
			# no longer force their own maximum range here.
			mount.aim_at(aim_point)


func _get_ai_fire_control_target() -> ShipUnit:
	if aim_source != AimSource.AI \
			or aim_mode != AimMode.TRACK_WORLD_TARGET:
		return null
	# Validate before casting: `target` is untyped and a freed instance is not
	# null, so casting it first raises "Trying to cast a freed object".
	if target == null or not is_instance_valid(target):
		return null
	return target as ShipUnit


func _update_ai_fire_control(target_ship: ShipUnit) -> void:
	_ensure_ai_fire_control()
	var cannons := get_weapons_by_type(WeaponTypes.Type.CANNON)
	_ai_fire_control.update(owner_ship, target_ship, cannons)
	for cannon in cannons:
		var cannon_mount := cannon as CannonMount
		if cannon_mount != null:
			_ai_fire_control.bind_mount_provider(cannon_mount)
	_ai_fire_control_hooks_active = true


func _ensure_ai_fire_control() -> void:
	if _ai_fire_control != null:
		return
	_ai_fire_control = ShipGunneryFireControl.new()
	var services := owner_ship.battle_services \
		if owner_ship != null and is_instance_valid(owner_ship) else null
	_ai_fire_control.configure(
		services.ai_gunnery_difficulty if services != null else null,
		owner_ship.ship_data.gunnery_crew_stats \
			if owner_ship != null \
			and is_instance_valid(owner_ship) \
			and owner_ship.ship_data != null else null,
		services.debug_settings if services != null else null
	)


func _release_ai_fire_control_hooks() -> void:
	if _ai_fire_control == null:
		return
	_ai_fire_control_hooks_active = false
	_ai_fire_control.release_provider_bindings()
	for mount_value: Variant in weapon_mounts:
		var cannon_mount := _as_valid_weapon_mount(mount_value) as CannonMount
		if cannon_mount != null \
				and cannon_mount.shell_deviation_provider == _ai_fire_control:
			cannon_mount.shell_deviation_provider = null


func get_ai_fire_control() -> ShipGunneryFireControl:
	return _ai_fire_control


func get_gunnery_debug_snapshots() -> Array[GunneryDebugSnapshot]:
	if _ai_fire_control == null:
		return []
	return _ai_fire_control.get_debug_snapshots()


func _update_manual_relative_aim_point() -> void:
	var direction := get_manual_aim_world_direction()
	if direction.length_squared() <= 0.0001 \
			or owner_ship == null \
			or not is_instance_valid(owner_ship):
		has_aim_point = false
		return
	var range_m := 0.0
	if _manual_aim_command != null and _manual_aim_command.range_m > 0.0:
		range_m = _manual_aim_command.range_m
	else:
		range_m = get_selected_cannon_maximum_range_m()
		if range_m <= 0.0 and _manual_aim_command != null:
			range_m = _manual_aim_command.maximum_range_m
	aim_point = owner_ship.global_position \
		+ direction * maxf(range_m, 60.0)
	has_aim_point = true


func update_turrets(next_owner_ship: Node3D, use_default_aim: bool) -> void:
	# Deprecated: compatibility only. Use update_weapon_mounts().
	update_weapon_mounts(next_owner_ship, use_default_aim)


func get_weapons_by_type(
		weapon_type: WeaponTypes.Type
) -> Array[WeaponMount]:
	var result: Array[WeaponMount] = []
	for mount_value: Variant in weapon_mounts:
		var mount := _as_valid_weapon_mount(mount_value)
		if mount != null and mount.get_weapon_type() == weapon_type:
			result.append(mount)
	return result


func can_fire_weapon_type_at(
		weapon_type: WeaponTypes.Type,
		world_point: Vector3
) -> bool:
	for mount_value: Variant in weapon_mounts:
		var mount := _as_valid_weapon_mount(mount_value)
		if mount != null \
				and mount.get_weapon_type() == weapon_type \
				and mount.can_fire_at(world_point):
			return true
	return false


func is_target_within_any_weapon_range(target_ship: ShipUnit) -> bool:
	if not _is_valid_target(target_ship):
		return false
	for mount_value: Variant in weapon_mounts:
		var mount := _as_valid_weapon_mount(mount_value)
		if mount == null:
			continue
		var distance: float = mount.get_distance_to_world_point(
			target_ship.global_position
		)
		if distance >= mount.get_minimum_range_m() \
				and distance <= mount.get_range_m():
			return true
	return false


func can_attack_target_now(target_ship: ShipUnit) -> bool:
	if not _is_valid_target(target_ship):
		return false
	for mount_value: Variant in weapon_mounts:
		var mount := _as_valid_weapon_mount(mount_value)
		if mount != null \
				and mount.get_fire_readiness_at(target_ship.global_position) \
					== WeaponFireReadiness.State.READY:
			return true
	return false


func can_attack_target_with_type(
		target_ship: ShipUnit,
		weapon_type: WeaponTypes.Type
) -> bool:
	return get_best_fire_readiness_for_type(target_ship, weapon_type) \
		== WeaponFireReadiness.State.READY


func get_best_fire_readiness_for_type(
		target_ship: ShipUnit,
		weapon_type: WeaponTypes.Type
) -> WeaponFireReadiness.State:
	if not _is_valid_target(target_ship):
		return WeaponFireReadiness.State.INVALID_TARGET
	var best_state := WeaponFireReadiness.State.NO_WEAPON_DATA
	var best_priority := -1
	var found_mount := false
	for mount_value: Variant in weapon_mounts:
		var mount := _as_valid_weapon_mount(mount_value)
		if mount == null \
				or mount.get_weapon_type() != weapon_type:
			continue
		found_mount = true
		var state: WeaponFireReadiness.State = mount.get_fire_readiness_at(
			target_ship.global_position
		)
		if state == WeaponFireReadiness.State.READY:
			return state
		var priority := _get_readiness_priority(state)
		if priority > best_priority:
			best_state = state
			best_priority = priority
	return best_state if found_mount \
		else WeaponFireReadiness.State.NO_WEAPON_DATA


func get_primary_weapon_range_m() -> float:
	var cannons := get_weapons_by_type(WeaponTypes.Type.CANNON)
	if not cannons.is_empty():
		return cannons[0].get_range_m()
	for mount_value: Variant in weapon_mounts:
		if mount_value == null or not is_instance_valid(mount_value):
			continue
		var mount := mount_value as WeaponMount
		if mount != null:
			return mount.get_range_m()
	return 0.0


func get_selected_cannon_maximum_range_m() -> float:
	return get_player_cannon_preview_range_m()


func get_player_cannon_preview_range_m() -> float:
	var maximum_range_m := 0.0
	for mount in get_weapons_by_type(WeaponTypes.Type.CANNON):
		if not mount.is_operational():
			continue
		maximum_range_m = maxf(
			maximum_range_m,
			mount.get_runtime_maximum_range_m()
		)
	return maximum_range_m


func get_player_cannon_preview_mounts() -> Array[WeaponMount]:
	var result: Array[WeaponMount] = []
	for mount in get_weapons_by_type(WeaponTypes.Type.CANNON):
		if mount.is_available_for_range_preview():
			result.append(mount)
	return result


func get_max_weapon_range_m(type_filter: Variant = null) -> float:
	var maximum_range_m := 0.0
	for mount_value: Variant in weapon_mounts:
		var mount := _as_valid_weapon_mount(mount_value)
		if mount == null:
			continue
		if type_filter != null and mount.get_weapon_type() != int(type_filter):
			continue
		maximum_range_m = maxf(maximum_range_m, mount.get_range_m())
	return maximum_range_m


func has_usable_weapon() -> bool:
	for mount_value: Variant in weapon_mounts:
		var mount := _as_valid_weapon_mount(mount_value)
		if mount != null and mount.get_range_m() > 0.0:
			return true
	return false


func is_target_in_range(target_ship: ShipUnit) -> bool:
	return is_target_within_any_weapon_range(target_ship)


func get_estimated_damage_per_second() -> float:
	return get_total_sustained_dps()


func get_total_salvo_damage(type_filter: Variant = null) -> float:
	var total_damage := 0.0
	for mount_value: Variant in weapon_mounts:
		var mount := _as_valid_weapon_mount(mount_value)
		if mount == null \
				or not _matches_weapon_type(mount, type_filter):
			continue
		total_damage += mount.get_salvo_damage()
	return total_damage


func get_total_sustained_dps(type_filter: Variant = null) -> float:
	var total_damage_per_second := 0.0
	for mount_value: Variant in weapon_mounts:
		var mount := _as_valid_weapon_mount(mount_value)
		if mount == null \
				or not _matches_weapon_type(mount, type_filter):
			continue
		total_damage_per_second += mount.get_sustained_dps()
	return total_damage_per_second


func get_total_ready_salvo_damage(type_filter: Variant = null) -> float:
	var total_damage := 0.0
	for mount_value: Variant in weapon_mounts:
		var mount := _as_valid_weapon_mount(mount_value)
		if mount == null \
				or not _matches_weapon_type(mount, type_filter):
			continue
		total_damage += mount.get_ready_salvo_damage()
	return total_damage


func estimate_available_turret_ratio(target_direction: Vector3) -> float:
	var cannons := get_weapons_by_type(WeaponTypes.Type.CANNON)
	if cannons.is_empty() or target_direction.length_squared() < 0.01:
		return 0.0
	if owner_ship == null:
		return 1.0
	target_direction.y = 0.0
	var forward := -owner_ship.global_transform.basis.z
	forward.y = 0.0
	var angle_deg := rad_to_deg(absf(forward.angle_to(target_direction.normalized())))
	var broadside_angle_deg := owner_ship.ai.get_preferred_broadside_angle_deg() \
		if owner_ship.ai != null else 70.0
	if broadside_angle_deg <= 0.0:
		return 0.5
	return clampf(
		1.0 - absf(angle_deg - broadside_angle_deg) / 100.0,
		0.25,
		1.0
	)


func get_primary_impact_point(gravity: float) -> Variant:
	var cannons := get_weapons_by_type(WeaponTypes.Type.CANNON)
	if cannons.is_empty():
		return null
	var cannon := cannons[0]
	var origin := cannon.get_muzzle_position()
	var velocity_vector := cannon.get_muzzle_velocity_vector()
	var effective_gravity: float = gravity
	if cannon is CannonMount:
		effective_gravity = (cannon as CannonMount).get_effective_gravity_mps2()
	var a: float = -0.5 * effective_gravity
	var b: float = velocity_vector.y
	var c: float = origin.y
	var discriminant: float = b * b - 4.0 * a * c
	if discriminant < 0.0:
		return null
	var sqrt_discriminant: float = sqrt(discriminant)
	var t1: float = (-b + sqrt_discriminant) / (2.0 * a)
	var t2: float = (-b - sqrt_discriminant) / (2.0 * a)
	var time: float = maxf(t1, t2)
	if time <= 0.0:
		return null
	var point := origin + velocity_vector * time \
		+ Vector3(0.0, -0.5 * gravity * time * time, 0.0)
	point.y = 0.035
	return point


func calculate_torpedo_lead_point(
		launcher_position: Vector3,
		target_ship: ShipUnit,
		torpedo_speed_mps: float
) -> Vector3:
	if target_ship == null:
		return launcher_position
	var result: Variant = calculate_intercept_point(
		launcher_position,
		target_ship.global_position,
		target_ship.velocity,
		torpedo_speed_mps
	)
	return result as Vector3 if result != null else launcher_position


func calculate_intercept_point(
		origin: Vector3,
		target_position: Vector3,
		target_velocity: Vector3,
		projectile_speed: float
) -> Variant:
	if not origin.is_finite() or not target_position.is_finite() \
			or not target_velocity.is_finite() \
			or projectile_speed <= 0.01:
		return null
	var distance := CombatGeometryXZ.distance_xz(origin, target_position)
	var travel_time := distance / projectile_speed
	var horizontal_velocity := target_velocity
	horizontal_velocity.y = 0.0
	var intercept_point := target_position + horizontal_velocity * travel_time
	if not intercept_point.is_finite():
		return null
	return intercept_point


func _estimate_torpedo_hit_probability(
		launcher_position: Vector3,
		target_ship: ShipUnit,
		torpedo_speed_mps: float
) -> float:
	var distance := CombatGeometryXZ.distance_xz(
		launcher_position,
		target_ship.global_position
	)
	var travel_time := distance / maxf(torpedo_speed_mps, 0.01)
	var target_velocity := target_ship.velocity
	target_velocity.y = 0.0
	var target_speed := target_velocity.length()
	var maneuver_penalty := clampf(
		target_speed / maxf(torpedo_speed_mps, 0.01),
		0.0,
		1.0
	) * 0.3
	var time_penalty := clampf(travel_time / 120.0, 0.0, 0.45)
	return clampf(0.92 - maneuver_penalty - time_penalty, 0.05, 0.95)


func _matches_weapon_type(
		mount: WeaponMount,
		type_filter: Variant
) -> bool:
	return type_filter == null or mount.get_weapon_type() == int(type_filter)


func _as_valid_weapon_mount(value: Variant) -> WeaponMount:
	if value == null or not is_instance_valid(value):
		return null
	return value as WeaponMount


func _is_valid_target(target_ship: ShipUnit) -> bool:
	return owner_ship != null \
		and target_ship != null \
		and is_instance_valid(target_ship) \
		and not target_ship.is_queued_for_deletion() \
		and target_ship.is_alive()


func _get_readiness_priority(
		state: WeaponFireReadiness.State
) -> int:
	match state:
		WeaponFireReadiness.State.READY:
			return 100
		WeaponFireReadiness.State.RELOADING:
			return 90
		WeaponFireReadiness.State.NOT_ALIGNED:
			return 80
		WeaponFireReadiness.State.NOT_ELEVATION_ALIGNED:
			return 78
		WeaponFireReadiness.State.NO_BALLISTIC_SOLUTION:
			return 58
		WeaponFireReadiness.State.FRIENDLY_BLOCKED:
			return 70
		WeaponFireReadiness.State.OUTSIDE_TRAVERSE:
			return 60
		WeaponFireReadiness.State.INSIDE_MINIMUM_RANGE:
			return 55
		WeaponFireReadiness.State.OUT_OF_RANGE:
			return 50
		WeaponFireReadiness.State.NO_AIM_POINT:
			return 40
		WeaponFireReadiness.State.NO_AMMUNITION:
			return 35
		WeaponFireReadiness.State.NO_MUZZLE:
			return 32
		WeaponFireReadiness.State.NO_PROJECTILE_SCENE:
			return 30
		WeaponFireReadiness.State.NO_PROJECTILE:
			return 30
		WeaponFireReadiness.State.INVALID_TARGET:
			return 20
		WeaponFireReadiness.State.NO_WEAPON_DATA:
			return 10
	return 0

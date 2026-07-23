extends Node
class_name ShipAI

enum BehaviorState {
	IDLE,
	CHASE,
	ATTACK,
	RETREAT,
}

@export_category("Pursuit")
@export_range(0.1, 10.0, 0.1) var pursuit_update_interval_sec := 1.0
@export var pursuit_target_movement_threshold_m := 250.0
@export var emergency_path_deviation_m := 500.0
@export_range(0.05, 2.0, 0.05) var emergency_path_update_cooldown_sec := 0.3

@export_category("Carrier Separation")
@export_range(1.0, 5.0, 0.1) var carrier_separation_update_interval_sec := 2.5
@export var carrier_target_movement_threshold_m := 300.0
@export var carrier_separation_buffer_m := 600.0

@export_category("Combat Fallbacks")
@export var fallback_engagement_range_m := 8000.0
@export var fallback_minimum_separation_m := 350.0
@export var fallback_target_safety_radius_m := 90.0
@export_range(0.0, 10.0, 0.1) var minimum_state_hold_sec := 2.0

var target: ShipUnit
var behavior_state: BehaviorState = BehaviorState.IDLE
var engagement_range_m := 8000.0
var minimum_separation_m := 350.0

var last_pursuit_position := Vector3.ZERO
var pursuit_update_elapsed_sec := 0.0
var pursuit_target_instance_id := 0
var pursuit_navigation_update_count := 0

var carrier_separation_update_count := 0
var _carrier_separation_elapsed_sec := 0.0
var _last_carrier_target_position := Vector3.ZERO
var _carrier_target_instance_id := 0

var _owner_ship: ShipUnit
var _ship_data: ShipData
var _role_profile: ShipAIRoleProfile
var _weapon_database := WeaponDatabase.new()
var _behavior_state_elapsed_sec := 0.0


func setup(owner_ship: ShipUnit, data: ShipData) -> void:
	_owner_ship = owner_ship
	_ship_data = data
	_role_profile = data.ai_role_profile if data != null else null
	if _role_profile == null:
		_role_profile = ShipAIRoleProfile.new()
	_refresh_tactical_ranges(null, data)


func set_target(next_target) -> void:
	var resolved_target := next_target as ShipUnit
	if target == resolved_target:
		return
	target = resolved_target
	_reset_pursuit()
	_reset_carrier_separation()


func clear_target() -> void:
	set_target(null)


func update_ai(
		owner_ship: Node3D,
		movement,
		navigation,
		combat,
		ship_data: Resource,
		delta: float
) -> void:
	if owner_ship == null or movement == null or navigation == null or combat == null:
		return
	if _owner_ship != owner_ship:
		setup(owner_ship as ShipUnit, ship_data as ShipData)
	pursuit_update_elapsed_sec += delta
	_carrier_separation_elapsed_sec += delta
	_behavior_state_elapsed_sec += delta

	if navigation.battlefield_bounds != null \
			and not navigation.battlefield_bounds.is_inside_bounds(owner_ship.global_position):
		_set_behavior_state(BehaviorState.CHASE, true)
		return
	if not _is_target_valid():
		_stop_without_target(movement, navigation)
		return

	var active_ship_data := ship_data as ShipData
	_refresh_tactical_ranges(combat, active_ship_data)
	var to_target := target.global_position - owner_ship.global_position
	to_target.y = 0.0
	var distance_m := to_target.length()
	combat.set_aim_point(target.global_position)

	if distance_m <= minimum_separation_m:
		_set_behavior_state(BehaviorState.RETREAT)
		navigation.clear_navigation_target()
		movement.set_movement_command(0.65, movement.get_rudder_to_direction(-to_target))
		return

	if behavior_state == BehaviorState.RETREAT \
			and _behavior_state_elapsed_sec < minimum_state_hold_sec \
			and not _is_aircraft_carrier(active_ship_data):
		navigation.clear_navigation_target()
		movement.set_movement_command(0.5, movement.get_rudder_to_direction(-to_target))
		return

	if _is_aircraft_carrier(active_ship_data):
		_update_carrier_behavior(owner_ship, movement, navigation, combat, distance_m, to_target)
		return

	if distance_m <= engagement_range_m and combat.has_usable_weapon():
		var distance_ratio := distance_m / maxf(engagement_range_m, 1.0)
		if distance_ratio < 0.65:
			_set_behavior_state(BehaviorState.RETREAT)
			navigation.clear_navigation_target()
			movement.set_movement_command(0.45, movement.get_rudder_to_direction(-to_target))
			return
		_set_behavior_state(BehaviorState.ATTACK)
		navigation.clear_navigation_target()
		var attack_engine_output := 0.12 if distance_ratio > 0.9 else 0.0
		movement.set_movement_command(
			attack_engine_output,
			movement.get_rudder_to_direction(to_target)
		)
		combat.fire_all()
		return

	_set_behavior_state(BehaviorState.CHASE)
	_update_pursuit(owner_ship, target, navigation)


func should_fire(distance_to_target: float) -> bool:
	return distance_to_target <= engagement_range_m


func get_effective_engagement_range_m(combat, ship_data: ShipData) -> float:
	var weapon_range_m := 0.0
	if combat != null and combat.has_method(&"get_primary_weapon_range_m"):
		weapon_range_m = float(combat.call(&"get_primary_weapon_range_m"))
	if weapon_range_m <= 0.0 and ship_data != null and not ship_data.default_weapon_id.is_empty():
		var default_weapon := _weapon_database.get_weapon(ship_data.default_weapon_id)
		if default_weapon != null:
			weapon_range_m = default_weapon.range_meters
	if weapon_range_m <= 0.0:
		weapon_range_m = fallback_engagement_range_m
	return weapon_range_m * _get_preferred_range_ratio()


func get_minimum_separation_m(owner_data: ShipData, target_ship: Node3D) -> float:
	var owner_radius := 0.0
	if owner_data != null:
		owner_radius = maxf(owner_data.navigation_safety_radius_m, 0.0)
	var target_radius := fallback_target_safety_radius_m
	if target_ship != null and target_ship.has_method(&"get_navigation_safety_radius_m"):
		target_radius = maxf(
			float(target_ship.call(&"get_navigation_safety_radius_m")),
			fallback_target_safety_radius_m
		)
	elif target_ship != null:
		var target_data := target_ship.get(&"ship_data") as ShipData
		if target_data != null:
			target_radius = maxf(
				target_data.navigation_safety_radius_m,
				fallback_target_safety_radius_m
			)
	var tactical_clearance_m := _role_profile.tactical_clearance_m \
		if _role_profile != null else 300.0
	return maxf(
		fallback_minimum_separation_m,
		owner_radius + target_radius + tactical_clearance_m
	)


func get_debug_data() -> Dictionary:
	return {
		"state": BehaviorState.keys()[behavior_state],
		"target": target,
		"engagement_range_m": engagement_range_m,
		"minimum_separation_m": minimum_separation_m,
		"pursuit_navigation_update_count": pursuit_navigation_update_count,
		"last_pursuit_position": last_pursuit_position,
		"carrier_separation_update_count": carrier_separation_update_count,
	}


func _update_pursuit(
		owner_ship: Node3D,
		pursuit_target: Node3D,
		navigation
) -> void:
	var target_instance_id := pursuit_target.get_instance_id()
	var target_changed := pursuit_target_instance_id != target_instance_id
	var movement_threshold_squared := pursuit_target_movement_threshold_m \
		* pursuit_target_movement_threshold_m
	var target_moved := not target_changed \
		and last_pursuit_position.distance_squared_to(pursuit_target.global_position) \
			>= movement_threshold_squared
	var timer_due := pursuit_update_elapsed_sec >= pursuit_update_interval_sec
	var path_missing: bool = not bool(navigation.has_navigation_target) \
		or (not navigation.has_valid_path() and not bool(navigation.path_calculation_failed_state))
	var emergency_deviation: bool = navigation.has_method(&"is_path_deviated") \
		and bool(navigation.call(&"is_path_deviated", emergency_path_deviation_m))
	var emergency_update_due := emergency_deviation \
		and pursuit_update_elapsed_sec >= emergency_path_update_cooldown_sec
	var should_update := target_changed \
		or path_missing \
		or (timer_due and target_moved) \
		or emergency_update_due
	if not should_update:
		return

	navigation.set_navigation_target(_calculate_standoff_point(owner_ship, pursuit_target))
	last_pursuit_position = pursuit_target.global_position
	pursuit_target_instance_id = target_instance_id
	pursuit_update_elapsed_sec = 0.0
	pursuit_navigation_update_count += 1


func _update_carrier_behavior(
		owner_ship: Node3D,
		movement,
		navigation,
		combat,
		distance_m: float,
		to_target: Vector3
) -> void:
	var weapon_range_m: float = float(combat.get_primary_weapon_range_m())
	var preferred_separation_m: float = weapon_range_m * _get_preferred_range_ratio()
	if distance_m <= weapon_range_m and combat.has_usable_weapon():
		combat.fire_all()
	if distance_m >= preferred_separation_m:
		_set_behavior_state(BehaviorState.ATTACK)
		navigation.clear_navigation_target()
		movement.set_movement_command(0.0, movement.get_rudder_to_direction(to_target))
		return

	_set_behavior_state(BehaviorState.RETREAT)
	var target_id := target.get_instance_id()
	var target_changed := target_id != _carrier_target_instance_id
	var target_moved := not target_changed \
		and _last_carrier_target_position.distance_squared_to(target.global_position) \
			>= carrier_target_movement_threshold_m * carrier_target_movement_threshold_m
	var timer_due := _carrier_separation_elapsed_sec >= carrier_separation_update_interval_sec
	var path_missing: bool = not bool(navigation.has_navigation_target) \
		or (not navigation.has_valid_path() and not bool(navigation.path_calculation_failed_state))
	if target_changed or path_missing or (timer_due and target_moved):
		var away_direction := -to_target.normalized()
		var separation_gain: float = preferred_separation_m - distance_m \
			+ carrier_separation_buffer_m
		var separation_target := owner_ship.global_position \
			+ away_direction * maxf(separation_gain, carrier_separation_buffer_m)
		navigation.set_navigation_target(separation_target)
		_last_carrier_target_position = target.global_position
		_carrier_target_instance_id = target_id
		_carrier_separation_elapsed_sec = 0.0
		carrier_separation_update_count += 1
	if not navigation.has_navigation_target:
		movement.set_movement_command(0.45, movement.get_rudder_to_direction(-to_target))


func _calculate_standoff_point(owner_ship: Node3D, pursuit_target: Node3D) -> Vector3:
	var away_from_target := owner_ship.global_position - pursuit_target.global_position
	away_from_target.y = 0.0
	if away_from_target.length_squared() < 0.01:
		away_from_target = owner_ship.global_transform.basis.z
		away_from_target.y = 0.0
	var standoff_distance_m := maxf(
		engagement_range_m * 0.92,
		minimum_separation_m * 1.25
	)
	var pursuit_point := pursuit_target.global_position \
		+ away_from_target.normalized() * standoff_distance_m
	pursuit_point.y = owner_ship.global_position.y
	return pursuit_point


func _refresh_tactical_ranges(combat, ship_data: ShipData) -> void:
	engagement_range_m = get_effective_engagement_range_m(combat, ship_data)
	minimum_separation_m = get_minimum_separation_m(ship_data, target)


func _get_preferred_range_ratio() -> float:
	return _role_profile.preferred_range_ratio if _role_profile != null else 0.75


func _is_aircraft_carrier(ship_data: ShipData) -> bool:
	return ship_data != null \
		and ship_data.ship_class == ShipData.ShipClass.AIRCRAFT_CARRIER


func _is_target_valid() -> bool:
	return target != null and is_instance_valid(target) and target.is_inside_tree() \
		and not target.is_queued_for_deletion() and target.is_alive() \
		and _owner_ship != null and _owner_ship.is_hostile_to(target)


func _stop_without_target(movement, navigation) -> void:
	_set_behavior_state(BehaviorState.IDLE, true)
	if navigation.has_navigation_target:
		navigation.clear_navigation_target()
	movement.set_movement_command(0.0, 0.0)


func _set_behavior_state(next_state: BehaviorState, force := false) -> void:
	if behavior_state == next_state:
		return
	if not force and behavior_state == BehaviorState.RETREAT \
		and _behavior_state_elapsed_sec < minimum_state_hold_sec:
		return
	behavior_state = next_state
	_behavior_state_elapsed_sec = 0.0


func _reset_pursuit() -> void:
	last_pursuit_position = Vector3.ZERO
	pursuit_update_elapsed_sec = pursuit_update_interval_sec
	pursuit_target_instance_id = 0


func _reset_carrier_separation() -> void:
	_carrier_separation_elapsed_sec = carrier_separation_update_interval_sec
	_last_carrier_target_position = Vector3.ZERO
	_carrier_target_instance_id = 0

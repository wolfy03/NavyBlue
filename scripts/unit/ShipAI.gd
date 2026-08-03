extends Node
class_name ShipAI

enum BehaviorState {
	IDLE,
	CHASE,
	ATTACK,
	RETREAT,
	ACQUIRE_TARGET,
	APPROACH,
	ENGAGE,
	REPOSITION,
	ESCORT,
	INTERCEPT,
	FLANK,
	DISENGAGE,
	SUPPORT,
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
@export_range(0.0, 1.0, 0.05) var torpedo_minimum_hit_probability := 0.35

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
var _fleet_controller_ref: WeakRef
var _fleet_context: FleetMemberContext
var _tactical_navigation_elapsed_sec := 0.0
var _last_tactical_position := Vector3.ZERO
var _last_tactical_heading := Vector3.FORWARD
var _tactical_path_failure_elapsed_sec := 0.0
var _tactical_path_failure_count := 0
var tactical_navigation_update_count := 0


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


func set_fleet_controller(controller: FleetAIController) -> void:
	_fleet_controller_ref = weakref(controller) if controller != null else null


func set_fleet_tactical_context(context: FleetMemberContext) -> void:
	if _fleet_context != context:
		_fleet_context = context
		_tactical_navigation_elapsed_sec = 2.0
		_last_tactical_position = Vector3.ZERO


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
	_tactical_navigation_elapsed_sec += delta
	_tactical_path_failure_elapsed_sec += delta

	if navigation.battlefield_bounds != null \
			and not navigation.battlefield_bounds.is_inside_bounds(owner_ship.global_position):
		_set_behavior_state(BehaviorState.REPOSITION, true)
		return
	if _is_tactical_position_temporarily_invalid():
		if navigation.has_navigation_target:
			navigation.clear_navigation_target()
		movement.set_movement_command(0.0, 0.0)
		return
	if _fleet_context != null \
			and _fleet_context.tactical_role == FleetMemberContext.TacticalRole.DISENGAGE:
		_follow_fleet_tactical_position(
			owner_ship,
			movement,
			navigation,
			BehaviorState.DISENGAGE
		)
		return
	if not _is_target_valid():
		if _fleet_context != null and _fleet_context.tactical_position_valid:
			var no_target_state := _get_state_for_tactical_role(_fleet_context.tactical_role)
			_follow_fleet_tactical_position(
				owner_ship,
				movement,
				navigation,
				no_target_state
			)
			return
		_stop_without_target(movement, navigation)
		return

	var active_ship_data := ship_data as ShipData
	_refresh_tactical_ranges(combat, active_ship_data)
	var to_target := target.global_position - owner_ship.global_position
	to_target.y = 0.0
	var distance_m := to_target.length()
	# Predictive fire control: the combat component leads the moving target
	# with difficulty/crew accuracy error instead of aiming at its current
	# position (legacy behavior was set_aim_point(target.global_position)).
	combat.set_ai_engagement_target(target)
	combat.fire_torpedoes_at(
		target,
		navigation.battlefield_bounds,
		torpedo_minimum_hit_probability
	)

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

	if _fleet_context != null and _fleet_context.tactical_position_valid:
		if _update_fleet_tactical_behavior(
			owner_ship,
			movement,
			navigation,
			combat,
			distance_m
		):
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
		_set_behavior_state(BehaviorState.ENGAGE)
		navigation.clear_navigation_target()
		var attack_engine_output := 0.12 if distance_ratio > 0.9 else 0.0
		movement.set_movement_command(
			attack_engine_output,
			movement.get_rudder_to_direction(to_target)
		)
		combat.fire_all()
		return

	_set_behavior_state(BehaviorState.APPROACH)
	_update_pursuit(owner_ship, target, navigation)


func should_fire(distance_to_target: float) -> bool:
	return distance_to_target <= engagement_range_m


func get_effective_engagement_range_m(combat, ship_data: ShipData) -> float:
	var weapon_range_m := 0.0
	if combat != null and combat.has_method(&"get_primary_weapon_range_m"):
		weapon_range_m = float(combat.call(&"get_primary_weapon_range_m"))
	# Deprecated fallback for pre-slot ShipData. New AI reads ShipCombat mounts.
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
		"tactical_navigation_update_count": tactical_navigation_update_count,
		"tactical_role": _fleet_context.get_role_name() \
			if _fleet_context != null else &"none",
		"tactical_position": _fleet_context.tactical_position \
			if _fleet_context != null else Vector3.ZERO,
		"tactical_side_sign": _fleet_context.tactical_side_sign \
			if _fleet_context != null else 0.0,
		"disengaging": behavior_state == BehaviorState.DISENGAGE,
		"tactical_path_failure_count": _tactical_path_failure_count,
	}


func get_preferred_broadside_angle_deg() -> float:
	if _ship_data == null:
		return 70.0
	match _ship_data.ship_class:
		ShipData.ShipClass.BATTLESHIP, ShipData.ShipClass.CRUISER:
			return 80.0
		ShipData.ShipClass.DESTROYER:
			return 60.0
		ShipData.ShipClass.AIRCRAFT_CARRIER:
			return 0.0
	return 70.0


func _update_fleet_tactical_behavior(
		owner_ship: Node3D,
		movement,
		navigation,
		combat,
		distance_m: float
) -> bool:
	var role := _fleet_context.tactical_role
	if distance_m <= engagement_range_m and combat.has_usable_weapon():
		combat.fire_all()
	match role:
		FleetMemberContext.TacticalRole.LINE_COMBATANT:
			_follow_fleet_tactical_position(
				owner_ship,
				movement,
				navigation,
				BehaviorState.ENGAGE if distance_m <= engagement_range_m \
					else BehaviorState.APPROACH
			)
			return true
		FleetMemberContext.TacticalRole.ESCORT:
			_follow_fleet_tactical_position(
				owner_ship,
				movement,
				navigation,
				BehaviorState.ESCORT
			)
			return true
		FleetMemberContext.TacticalRole.SCREEN:
			_follow_fleet_tactical_position(
				owner_ship,
				movement,
				navigation,
				BehaviorState.REPOSITION
			)
			return true
		FleetMemberContext.TacticalRole.INTERCEPT:
			_follow_fleet_tactical_position(
				owner_ship,
				movement,
				navigation,
				BehaviorState.INTERCEPT
			)
			return true
		FleetMemberContext.TacticalRole.FLANKER:
			_follow_fleet_tactical_position(
				owner_ship,
				movement,
				navigation,
				BehaviorState.FLANK
			)
			return true
		FleetMemberContext.TacticalRole.SUPPORT:
			_follow_fleet_tactical_position(
				owner_ship,
				movement,
				navigation,
				BehaviorState.SUPPORT
			)
			return true
		FleetMemberContext.TacticalRole.DISENGAGE:
			_follow_fleet_tactical_position(
				owner_ship,
				movement,
				navigation,
				BehaviorState.DISENGAGE
			)
			return true
	return false


func _follow_fleet_tactical_position(
		owner_ship: Node3D,
		movement,
		navigation,
		state: BehaviorState
) -> void:
	_set_behavior_state(state)
	if _is_tactical_position_temporarily_invalid():
		if navigation.has_navigation_target:
			navigation.clear_navigation_target()
		movement.set_movement_command(0.0, 0.0)
		return
	if _fleet_context == null or not _fleet_context.tactical_position_valid:
		movement.set_movement_command(0.0, 0.0)
		return
	var tactical_position := _fleet_context.tactical_position
	var offset := tactical_position - owner_ship.global_position
	offset.y = 0.0
	if offset.length_squared() <= 180.0 * 180.0:
		if navigation.has_navigation_target:
			navigation.clear_navigation_target()
		var desired_heading := _fleet_context.tactical_heading \
			if _fleet_context.tactical_heading_valid else Vector3.ZERO
		var cruise_output := 0.0
		if _fleet_context.tactical_role == FleetMemberContext.TacticalRole.LINE_COMBATANT:
			cruise_output = _role_profile.broadside_cruise_output if _role_profile != null else 0.12
		movement.set_movement_command(
			cruise_output,
			movement.get_rudder_to_direction(desired_heading)
		)
		_last_tactical_heading = desired_heading
		return
	var position_changed := _last_tactical_position.distance_squared_to(tactical_position) \
		>= 180.0 * 180.0
	var path_missing: bool = not bool(navigation.has_navigation_target) \
		or (not navigation.has_valid_path() and not bool(navigation.path_calculation_failed_state))
	if navigation.path_calculation_failed_state:
		if _tactical_path_failure_elapsed_sec < maxf(navigation.failed_path_retry_interval_sec, 1.5):
			movement.set_movement_command(0.0, 0.0)
			return
		_tactical_path_failure_elapsed_sec = 0.0
		_tactical_path_failure_count += 1
		var fleet_controller := _get_fleet_controller()
		if fleet_controller != null and fleet_controller.has_method(&"report_tactical_path_failure"):
			fleet_controller.call(&"report_tactical_path_failure", _owner_ship)
		return
	if path_missing or (
		_tactical_navigation_elapsed_sec >= 2.0 and position_changed
	):
		navigation.set_navigation_target(tactical_position)
		_last_tactical_position = tactical_position
		_tactical_navigation_elapsed_sec = 0.0
		tactical_navigation_update_count += 1


func _get_fleet_controller() -> FleetAIController:
	return _fleet_controller_ref.get_ref() as FleetAIController \
		if _fleet_controller_ref != null else null


func _is_tactical_position_temporarily_invalid() -> bool:
	if _fleet_context == null:
		return false
	var now_sec := float(Time.get_ticks_msec()) * 0.001
	return now_sec < _fleet_context.tactical_position_invalid_until_sec


func _get_state_for_tactical_role(
		role: FleetMemberContext.TacticalRole
) -> BehaviorState:
	match role:
		FleetMemberContext.TacticalRole.ESCORT:
			return BehaviorState.ESCORT
		FleetMemberContext.TacticalRole.SCREEN:
			return BehaviorState.REPOSITION
		FleetMemberContext.TacticalRole.FLANKER:
			return BehaviorState.FLANK
		FleetMemberContext.TacticalRole.SUPPORT:
			return BehaviorState.SUPPORT
		FleetMemberContext.TacticalRole.INTERCEPT:
			return BehaviorState.INTERCEPT
		FleetMemberContext.TacticalRole.DISENGAGE:
			return BehaviorState.DISENGAGE
	return BehaviorState.REPOSITION


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

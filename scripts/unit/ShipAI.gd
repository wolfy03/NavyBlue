extends Node
class_name ShipAI

enum BehaviorState {
	IDLE,
	CHASE,
	ATTACK,
	RETREAT,
}

@export_category("Target Evaluation")
@export_range(0.1, 10.0, 0.1) var target_evaluation_interval_sec := 1.0
@export_range(0.0, 2.0, 0.05) var initial_evaluation_offset_max_sec := 0.5

@export_category("Pursuit")
@export_range(0.1, 10.0, 0.1) var pursuit_update_interval_sec := 1.0
@export var pursuit_target_movement_threshold_m := 250.0
@export var emergency_path_deviation_m := 500.0

@export_category("Combat Fallbacks")
@export var fallback_engagement_range_m := 8000.0
@export var fallback_minimum_separation_m := 350.0
@export_range(0.0, 10.0, 0.1) var minimum_state_hold_sec := 2.0

var target: Node3D
var behavior_state: BehaviorState = BehaviorState.IDLE
var engagement_range_m := 8000.0
var minimum_separation_m := 350.0

var last_pursuit_position := Vector3.ZERO
var pursuit_update_elapsed_sec := 0.0
var pursuit_target_instance_id := 0
var pursuit_navigation_update_count := 0
var target_evaluation_count := 0

var _owner_ship: Node3D
var _ship_data: ShipData
var _candidate_provider := Callable()
var _target_selector := ShipTargetSelector.new()
var _weapon_database := WeaponDatabase.new()
var _target_evaluation_elapsed_sec := 0.0
var _has_completed_initial_evaluation := false
var _target_evaluation_requested := false
var _behavior_state_elapsed_sec := 0.0


func setup(owner_ship: Node3D, data: ShipData) -> void:
	_owner_ship = owner_ship
	_ship_data = data
	var random_offset := RandomNumberGenerator.new()
	random_offset.seed = owner_ship.get_instance_id() * 1664525 + 1013904223
	_target_evaluation_elapsed_sec = -random_offset.randf_range(
		0.0,
		maxf(initial_evaluation_offset_max_sec, 0.0)
	)
	_has_completed_initial_evaluation = false
	_refresh_tactical_ranges(null, data)


func set_candidate_provider(provider: Callable) -> void:
	_candidate_provider = provider


func set_target(next_target) -> void:
	var resolved_target := next_target as Node3D
	if target == resolved_target:
		return
	target = resolved_target
	_reset_pursuit()
	if target == null:
		request_target_evaluation()


func clear_target() -> void:
	target = null
	_reset_pursuit()


func request_target_evaluation() -> void:
	_target_evaluation_requested = true
	_target_evaluation_elapsed_sec = maxf(_target_evaluation_elapsed_sec, 0.0)


func is_target_valid(owner_ship: ShipUnit) -> bool:
	if owner_ship == null or target == null or not is_instance_valid(target):
		return false
	if target.is_queued_for_deletion() or not target.is_inside_tree():
		return false
	if target.has_method(&"is_alive") and not bool(target.call(&"is_alive")):
		return false
	return owner_ship.is_hostile_to(target)


func find_fallback_target(owner_ship: ShipUnit) -> ShipUnit:
	if owner_ship == null or not _candidate_provider.is_valid():
		return null
	var candidate_values: Variant = _candidate_provider.call()
	if not candidate_values is Array:
		return null
	return _target_selector.find_target(owner_ship, candidate_values as Array) as ShipUnit


func select_target(owner_ship: Node3D, candidates: Array) -> void:
	# Compatibility entry point; selection policy remains replaceable via ShipTargetSelector.
	set_target(_target_selector.find_target(owner_ship, candidates))


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
		setup(owner_ship, ship_data as ShipData)
	_target_evaluation_elapsed_sec += delta
	pursuit_update_elapsed_sec += delta
	_behavior_state_elapsed_sec += delta

	if navigation.battlefield_bounds != null \
			and not navigation.battlefield_bounds.is_inside_bounds(owner_ship.global_position):
		_set_behavior_state(BehaviorState.CHASE, true)
		return

	var typed_owner := owner_ship as ShipUnit
	if not _maintain_or_acquire_target(typed_owner):
		_stop_without_target(movement, navigation, combat)
		return

	var active_ship_data := ship_data as ShipData
	_refresh_tactical_ranges(combat, active_ship_data)
	var to_target := target.global_position - owner_ship.global_position
	to_target.y = 0.0
	var distance_m := to_target.length()
	combat.set_target(target)
	combat.set_aim_point(target.global_position)

	if distance_m <= minimum_separation_m:
		_set_behavior_state(BehaviorState.RETREAT)
		navigation.clear_navigation_target()
		var retreat_direction := -to_target
		movement.set_movement_command(0.65, movement.get_rudder_to_direction(retreat_direction))
		return

	if behavior_state == BehaviorState.RETREAT \
			and _behavior_state_elapsed_sec < minimum_state_hold_sec:
		navigation.clear_navigation_target()
		movement.set_movement_command(0.5, movement.get_rudder_to_direction(-to_target))
		return

	if distance_m <= engagement_range_m and combat.has_usable_weapon():
		_set_behavior_state(BehaviorState.ATTACK)
		navigation.clear_navigation_target()
		var attack_engine_output := 0.0 if _is_aircraft_carrier(active_ship_data) else 0.18
		movement.set_movement_command(
			attack_engine_output,
			movement.get_rudder_to_direction(to_target)
		)
		combat.fire_all()
		return

	_set_behavior_state(BehaviorState.CHASE)
	_update_pursuit(owner_ship, target, navigation, active_ship_data)


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
	return weapon_range_m * _get_preferred_range_ratio(ship_data)


func get_minimum_separation_m(owner_data: ShipData, target_ship: Node3D) -> float:
	if owner_data == null:
		return fallback_minimum_separation_m
	var target_safety_radius_m := 0.0
	if target_ship != null and target_ship.has_method(&"get_navigation_safety_radius_m"):
		target_safety_radius_m = float(target_ship.call(&"get_navigation_safety_radius_m"))
	elif target_ship != null:
		var target_data := target_ship.get(&"ship_data") as ShipData
		if target_data != null:
			target_safety_radius_m = target_data.navigation_safety_radius_m
	if target_safety_radius_m <= 0.0:
		return fallback_minimum_separation_m
	return owner_data.navigation_safety_radius_m \
		+ target_safety_radius_m \
		+ _get_tactical_clearance_m(owner_data)


func _maintain_or_acquire_target(owner_ship: ShipUnit) -> bool:
	if owner_ship == null:
		clear_target()
		return false
	if is_target_valid(owner_ship):
		if _target_evaluation_elapsed_sec >= target_evaluation_interval_sec:
			_target_evaluation_elapsed_sec = 0.0
			_target_evaluation_requested = false
		return true

	if target != null:
		clear_target()
	var evaluation_due := _target_evaluation_requested \
		or (not _has_completed_initial_evaluation and _target_evaluation_elapsed_sec >= 0.0) \
		or (_has_completed_initial_evaluation \
			and _target_evaluation_elapsed_sec >= target_evaluation_interval_sec)
	if not evaluation_due:
		return false

	target_evaluation_count += 1
	target = find_fallback_target(owner_ship)
	_target_evaluation_elapsed_sec = 0.0
	_target_evaluation_requested = false
	_has_completed_initial_evaluation = true
	_reset_pursuit()
	return is_target_valid(owner_ship)


func _stop_without_target(movement, navigation, combat) -> void:
	_set_behavior_state(BehaviorState.IDLE, true)
	if navigation.has_navigation_target:
		navigation.clear_navigation_target()
	movement.set_movement_command(0.0, 0.0)
	if combat.has_method(&"clear_target"):
		combat.call(&"clear_target")


func _update_pursuit(
		owner_ship: Node3D,
		pursuit_target: Node3D,
		navigation,
		ship_data: ShipData
) -> void:
	var target_instance_id := pursuit_target.get_instance_id()
	var target_changed := pursuit_target_instance_id != target_instance_id
	var movement_threshold_squared := pursuit_target_movement_threshold_m \
		* pursuit_target_movement_threshold_m
	var target_moved := not target_changed \
		and last_pursuit_position.distance_squared_to(pursuit_target.global_position) \
			>= movement_threshold_squared
	var timer_due := pursuit_update_elapsed_sec >= pursuit_update_interval_sec
	var path_unavailable: bool = (not bool(navigation.has_navigation_target) \
		or not navigation.has_valid_path() \
		or bool(navigation.path_calculation_failed_state)) and timer_due
	var emergency_deviation: bool = navigation.has_method(&"is_path_deviated") \
		and bool(navigation.call(&"is_path_deviated", emergency_path_deviation_m))
	if not (target_changed or target_moved or timer_due or path_unavailable or emergency_deviation):
		return

	var pursuit_point := _calculate_standoff_point(
		owner_ship,
		pursuit_target,
		ship_data
	)
	navigation.set_navigation_target(pursuit_point)
	last_pursuit_position = pursuit_target.global_position
	pursuit_target_instance_id = target_instance_id
	pursuit_update_elapsed_sec = 0.0
	pursuit_navigation_update_count += 1


func _calculate_standoff_point(
		owner_ship: Node3D,
		pursuit_target: Node3D,
		_ship_data_for_pursuit: ShipData
) -> Vector3:
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


func _get_preferred_range_ratio(ship_data: ShipData) -> float:
	if ship_data == null:
		return 1.0
	match ship_data.ship_class:
		ShipData.ShipClass.DESTROYER:
			return 0.65
		ShipData.ShipClass.CRUISER:
			return 0.75
		ShipData.ShipClass.BATTLESHIP:
			return 0.85
		ShipData.ShipClass.AIRCRAFT_CARRIER:
			return 0.90
	return 1.0


func _get_tactical_clearance_m(ship_data: ShipData) -> float:
	match ship_data.ship_class:
		ShipData.ShipClass.DESTROYER:
			return 200.0
		ShipData.ShipClass.CRUISER:
			return 325.0
		ShipData.ShipClass.BATTLESHIP:
			return 475.0
		ShipData.ShipClass.AIRCRAFT_CARRIER:
			return 600.0
	return 300.0


func _is_aircraft_carrier(ship_data: ShipData) -> bool:
	return ship_data != null \
		and ship_data.ship_class == ShipData.ShipClass.AIRCRAFT_CARRIER


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

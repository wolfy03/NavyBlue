extends Node
class_name ShipMovement

var owner_ship: CharacterBody3D
var ship_data: Resource
var engine_output := 0.0
var rudder_input := 0.0
var engine_output_change_rate := 0.55
var current_speed_mps := 0.0
var current_turn_rate_rad_sec := 0.0
var movement_plane_y_m := 0.0

var _throttle_axis := 0.0
var _uses_direct_engine_command := false
var _target_engine_output := 0.0

func setup(ship: CharacterBody3D, data: Resource, output_change_rate: float, sea_level_m: float = 0.0) -> void:
	owner_ship = ship
	ship_data = data
	engine_output_change_rate = output_change_rate
	movement_plane_y_m = sea_level_m

func set_input(throttle_axis: float, next_rudder_input: float) -> void:
	_uses_direct_engine_command = false
	_throttle_axis = clampf(throttle_axis, -1.0, 1.0)
	rudder_input = clampf(next_rudder_input, -1.0, 1.0)

func set_movement_command(target_engine_output: float, next_rudder_input: float) -> void:
	_uses_direct_engine_command = true
	_target_engine_output = clampf(target_engine_output, -1.0, 1.0)
	rudder_input = clampf(next_rudder_input, -1.0, 1.0)

func set_navigation_command(world_direction: Vector3, remaining_distance_m: float, steering_offset: float = 0.0, speed_scale: float = 1.0) -> void:
	if owner_ship == null or ship_data == null:
		return
	var base_rudder: float = get_rudder_to_direction(world_direction)
	var heading_error: float = absf(_get_signed_heading_error(world_direction))
	var turn_speed_scale: float = lerpf(1.0, 0.38, clampf(heading_error / PI, 0.0, 1.0))
	var arrival_scale: float = clampf(remaining_distance_m / maxf(ship_data.arrival_slowdown_distance_m, 1.0), 0.0, 1.0)
	var desired_speed: float = ship_data.cruise_speed_mps * minf(turn_speed_scale, maxf(arrival_scale, 0.08)) * clampf(speed_scale, 0.0, 1.0)
	_uses_direct_engine_command = true
	_target_engine_output = clampf(desired_speed / maxf(ship_data.max_speed_mps, 0.01), 0.0, 1.0)
	rudder_input = clampf(base_rudder + steering_offset, -1.0, 1.0)

func apply_movement(delta: float) -> void:
	if owner_ship == null or ship_data == null:
		return

	if _uses_direct_engine_command:
		# Engine output response is presentation/control state. Physical acceleration uses SI fields below.
		engine_output = move_toward(engine_output, _target_engine_output, engine_output_change_rate * delta)
	else:
		engine_output = clampf(engine_output + _throttle_axis * engine_output_change_rate * delta, -1.0, 1.0)

	var speed_limit: float = ship_data.max_speed_mps if engine_output >= 0.0 else ship_data.max_reverse_speed_mps
	var desired_speed_mps := engine_output * speed_limit
	var speed_change_rate: float = ship_data.acceleration_mps2 if absf(desired_speed_mps) > absf(current_speed_mps) else ship_data.deceleration_mps2
	current_speed_mps = move_toward(current_speed_mps, desired_speed_mps, speed_change_rate * delta)

	var turning_speed_ratio := clampf(absf(current_speed_mps) / maxf(ship_data.minimum_turning_speed_mps, 0.1), 0.08, 1.0)
	var reverse_factor := -1.0 if current_speed_mps < 0.0 else 1.0
	var desired_turn_rate := rudder_input * deg_to_rad(ship_data.max_turn_rate_deg_sec) * turning_speed_ratio * reverse_factor
	current_turn_rate_rad_sec = move_toward(
		current_turn_rate_rad_sec,
		desired_turn_rate,
		deg_to_rad(ship_data.turn_acceleration_deg_sec2) * delta
	)
	owner_ship.rotate_y(current_turn_rate_rad_sec * delta)

	var forward: Vector3 = -owner_ship.global_transform.basis.z.normalized()
	owner_ship.velocity = forward * current_speed_mps
	owner_ship.velocity.y = 0.0
	owner_ship.move_and_slide()
	owner_ship.global_position.y = movement_plane_y_m

func get_speed() -> float:
	if owner_ship == null:
		return 0.0
	return absf(current_speed_mps)

func get_rudder_to_direction(world_direction: Vector3) -> float:
	if owner_ship == null:
		return 0.0
	world_direction.y = 0.0
	if world_direction.length_squared() < 0.01:
		return 0.0
	var signed_angle := _get_signed_heading_error(world_direction)
	return clampf(signed_angle / deg_to_rad(35.0), -1.0, 1.0)

func get_velocity_xz() -> Vector3:
	if owner_ship == null:
		return Vector3.ZERO
	return Vector3(owner_ship.velocity.x, 0.0, owner_ship.velocity.z)

func stop() -> void:
	_uses_direct_engine_command = true
	_target_engine_output = 0.0
	rudder_input = 0.0

func apply_avoidance(steering_offset: float, speed_scale: float) -> void:
	rudder_input = clampf(rudder_input + steering_offset, -1.0, 1.0)
	if _uses_direct_engine_command and _target_engine_output > 0.0:
		_target_engine_output *= clampf(speed_scale, 0.0, 1.0)

func _get_signed_heading_error(world_direction: Vector3) -> float:
	world_direction.y = 0.0
	if owner_ship == null or world_direction.length_squared() < 0.01:
		return 0.0
	var forward: Vector3 = -owner_ship.global_transform.basis.z.normalized()
	return forward.signed_angle_to(world_direction.normalized(), Vector3.UP)

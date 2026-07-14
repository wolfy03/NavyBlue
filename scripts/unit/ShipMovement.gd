extends Node
class_name ShipMovement

var owner_ship: CharacterBody3D
var ship_data: Resource
var engine_output := 0.0
var rudder_input := 0.0
var engine_output_change_rate := 0.55

var _throttle_axis := 0.0
var _uses_direct_engine_command := false
var _target_engine_output := 0.0

func setup(ship: CharacterBody3D, data: Resource, output_change_rate: float) -> void:
	owner_ship = ship
	ship_data = data
	engine_output_change_rate = output_change_rate

func set_input(throttle_axis: float, next_rudder_input: float) -> void:
	_uses_direct_engine_command = false
	_throttle_axis = clampf(throttle_axis, -1.0, 1.0)
	rudder_input = clampf(next_rudder_input, -1.0, 1.0)

func set_movement_command(target_engine_output: float, next_rudder_input: float) -> void:
	_uses_direct_engine_command = true
	_target_engine_output = clampf(target_engine_output, -1.0, 1.0)
	rudder_input = clampf(next_rudder_input, -1.0, 1.0)

func apply_movement(delta: float) -> void:
	if owner_ship == null or ship_data == null:
		return

	if _uses_direct_engine_command:
		engine_output = move_toward(engine_output, _target_engine_output, ship_data.engine_response * delta)
	else:
		engine_output = clampf(engine_output + _throttle_axis * engine_output_change_rate * delta, -1.0, 1.0)

	var speed_limit: float = ship_data.max_forward_speed if engine_output >= 0.0 else ship_data.max_reverse_speed
	var forward: Vector3 = -owner_ship.global_transform.basis.z.normalized()
	owner_ship.velocity = forward * engine_output * speed_limit
	owner_ship.velocity.y = 0.0
	owner_ship.move_and_slide()
	owner_ship.global_position.y = 0.0

	var speed_factor: float = maxf(absf(engine_output), 0.12)
	var reverse_factor: float = -1.0 if engine_output < 0.0 else 1.0
	owner_ship.rotate_y(rudder_input * deg_to_rad(ship_data.turn_rate_degrees) * speed_factor * reverse_factor * delta)

func get_speed() -> float:
	if owner_ship == null:
		return 0.0
	return owner_ship.velocity.length()

func get_rudder_to_direction(world_direction: Vector3) -> float:
	if owner_ship == null:
		return 0.0
	world_direction.y = 0.0
	if world_direction.length_squared() < 0.01:
		return 0.0
	var forward: Vector3 = -owner_ship.global_transform.basis.z.normalized()
	var signed_angle: float = forward.signed_angle_to(world_direction.normalized(), Vector3.UP)
	return clampf(signed_angle / deg_to_rad(35.0), -1.0, 1.0)

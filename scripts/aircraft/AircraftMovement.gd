extends Node
class_name AircraftMovement

const EPSILON := 0.0001

enum FlightMode {
	FORMATION,
	DIRECT_FLIGHT,
}

var owner_aircraft: CharacterBody3D
var aircraft_data: AircraftData
var target_position: Vector3
var has_target := false
var flight_mode: FlightMode = FlightMode.FORMATION
var direct_flight_direction := Vector3.ZERO
var direct_flight_speed_mps := 0.0
var _arrived := false


func setup(next_owner_aircraft: Node3D, data: AircraftData) -> void:
	owner_aircraft = next_owner_aircraft as CharacterBody3D
	aircraft_data = data
	has_target = false
	set_formation_mode()
	_arrived = false


func set_target_position(position: Vector3) -> void:
	target_position = position
	has_target = true
	_arrived = false


func update_movement(delta: float) -> void:
	match flight_mode:
		FlightMode.FORMATION:
			_update_formation_movement(delta)
		FlightMode.DIRECT_FLIGHT:
			_update_direct_flight(delta)


func set_formation_mode() -> void:
	flight_mode = FlightMode.FORMATION
	direct_flight_direction = Vector3.ZERO
	direct_flight_speed_mps = 0.0


func set_direct_flight(
		direction: Vector3,
		speed_mps: float
) -> void:
	if direction.length_squared() <= EPSILON:
		return
	flight_mode = FlightMode.DIRECT_FLIGHT
	direct_flight_direction = direction.normalized()
	direct_flight_speed_mps = maxf(speed_mps, 0.0)
	_arrived = false


func _update_formation_movement(delta: float) -> void:
	if owner_aircraft == null \
			or not is_instance_valid(owner_aircraft) \
			or aircraft_data == null \
			or not has_target:
		return
	var to_target := target_position - owner_aircraft.global_position
	var horizontal_offset := Vector3(to_target.x, 0.0, to_target.z)
	var arrival_distance := maxf(aircraft_data.arrival_distance_m, 1.0)
	if horizontal_offset.length() <= arrival_distance \
			and absf(to_target.y) <= arrival_distance:
		owner_aircraft.velocity = Vector3.ZERO
		_arrived = true
		return

	var current_forward := -owner_aircraft.global_transform.basis.z
	current_forward.y = 0.0
	if current_forward.length_squared() <= EPSILON:
		current_forward = Vector3.FORWARD
	else:
		current_forward = current_forward.normalized()
	var desired_forward := current_forward
	if horizontal_offset.length_squared() > EPSILON:
		desired_forward = horizontal_offset.normalized()
	var turn_radians := deg_to_rad(maxf(aircraft_data.turn_rate_deg_sec, 0.0)) \
		* maxf(delta, 0.0)
	var angle := current_forward.angle_to(desired_forward)
	var turn_weight := minf(1.0, turn_radians / maxf(angle, EPSILON))
	var next_forward := current_forward.slerp(desired_forward, turn_weight)
	if next_forward.length_squared() <= EPSILON:
		next_forward = desired_forward
	next_forward = next_forward.normalized()

	var horizontal_speed := minf(
		maxf(aircraft_data.cruise_speed_mps, 0.0),
		maxf(aircraft_data.maximum_speed_mps, 0.0)
	)
	if horizontal_offset.length() < arrival_distance * 3.0:
		horizontal_speed *= clampf(
			horizontal_offset.length() / (arrival_distance * 3.0),
			0.2,
			1.0
		)
	var maximum_vertical_speed := maxf(horizontal_speed * 0.35, 5.0)
	var vertical_speed := clampf(
		to_target.y * 0.8,
		-maximum_vertical_speed,
		maximum_vertical_speed
	)
	owner_aircraft.velocity = next_forward * horizontal_speed
	owner_aircraft.velocity.y = vertical_speed
	owner_aircraft.move_and_slide()
	var flight_direction := owner_aircraft.velocity.normalized()
	if flight_direction.length_squared() > EPSILON:
		owner_aircraft.global_transform.basis = Basis.looking_at(
			flight_direction,
			Vector3.UP
		)
	_arrived = false


func _update_direct_flight(delta: float) -> void:
	if owner_aircraft == null \
			or not is_instance_valid(owner_aircraft):
		return
	if direct_flight_direction.length_squared() <= EPSILON:
		owner_aircraft.velocity = Vector3.ZERO
		return
	var direction := direct_flight_direction.normalized()
	owner_aircraft.velocity = direction * direct_flight_speed_mps
	owner_aircraft.move_and_slide()
	owner_aircraft.global_transform.basis = Basis.looking_at(
		direction,
		Vector3.UP
	)
	_arrived = false


func has_arrived() -> bool:
	return _arrived

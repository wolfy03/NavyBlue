extends RefCounted
class_name SquadronMovementController

const EPSILON := 0.0001

var owner_squadron: AircraftSquadron
var destination_tracker: SquadronDestinationTracker

var _speed_overrides: Dictionary = {}


func setup(
		squadron: AircraftSquadron,
		tracker: SquadronDestinationTracker
) -> void:
	shutdown()
	owner_squadron = squadron
	destination_tracker = tracker


func shutdown() -> void:
	owner_squadron = null
	destination_tracker = null
	_speed_overrides.clear()


func set_speed_override(key: StringName, speed_mps: float) -> void:
	_speed_overrides[key] = maxf(speed_mps, 0.0)


func clear_speed_override(key: StringName) -> void:
	_speed_overrides.erase(key)


func has_speed_override(key: StringName) -> bool:
	return _speed_overrides.has(key)


func get_speed_override(key: StringName, fallback: float = 0.0) -> float:
	return float(_speed_overrides.get(key, fallback))


func get_effective_speed() -> float:
	# Formation stepping speed. Active named overrides (e.g. the torpedo attack
	# run) cap the squadron below its cruise speed; the smallest override wins.
	var base_speed := owner_squadron._get_aircraft_speed()
	if _speed_overrides.is_empty():
		return base_speed
	var capped := base_speed
	for value in _speed_overrides.values():
		capped = minf(capped, float(value))
	return capped


func set_destination(
		world_position: Vector3,
		force_new_command: bool = false,
		command_type: StringName = &"mission"
) -> int:
	if owner_squadron.state in [
		AircraftSquadron.State.RETURNING,
		AircraftSquadron.State.RECOVERING,
		AircraftSquadron.State.DESTROYED,
	]:
		return destination_tracker.command_serial
	var next_destination := owner_squadron \
		._clamp_destination_horizontal(world_position)
	if not force_new_command \
			and owner_squadron.destination.distance_to(next_destination) \
			<= maxf(owner_squadron.destination_change_epsilon_m, 0.0) \
			and owner_squadron.state in [
				AircraftSquadron.State.EN_ROUTE,
				AircraftSquadron.State.HOLDING,
			]:
		return destination_tracker.command_serial
	var command_serial := destination_tracker.begin_command(
		command_type,
		next_destination.y
	)
	owner_squadron._loiter_initialized = false
	owner_squadron.destination = next_destination
	owner_squadron.state = AircraftSquadron.State.EN_ROUTE
	owner_squadron.set_physics_process(true)
	owner_squadron._on_destination_command_changed()
	return command_serial


func update_standard_movement(delta: float) -> void:
	match owner_squadron.state:
		AircraftSquadron.State.EN_ROUTE:
			advance_formation_center(owner_squadron.destination, delta)
			if has_formation_arrived(owner_squadron.destination):
				destination_tracker.mark_reached(
					destination_tracker.command_serial
				)
				begin_loiter()
				owner_squadron._on_destination_command_reached()
		AircraftSquadron.State.HOLDING:
			update_loiter(delta)
		AircraftSquadron.State.RETURNING:
			var carrier := owner_squadron.get_owner_carrier()
			if carrier == null:
				owner_squadron._mark_destroyed()
				return
			var recovery_position := owner_squadron \
				._get_carrier_recovery_position()
			advance_formation_center(recovery_position, delta)
			if has_formation_arrived(recovery_position):
				owner_squadron._complete_recovery()
				return
		AircraftSquadron.State.RECOVERING, \
		AircraftSquadron.State.DESTROYED:
			return
	update_formation_targets()


func advance_formation_center(target: Vector3, delta: float) -> void:
	var horizontal_offset := Vector3(
		target.x - owner_squadron.formation_center.x,
		0.0,
		target.z - owner_squadron.formation_center.z
	)
	if horizontal_offset.length_squared() > EPSILON:
		var desired_forward := horizontal_offset.normalized()
		var turn_step := deg_to_rad(maxf(
			owner_squadron.squadron_data.aircraft_data.turn_rate_deg_sec,
			0.0
		)) * delta
		var angle := owner_squadron._formation_forward.angle_to(
			desired_forward
		)
		var rotation_axis := owner_squadron._formation_forward.cross(
			desired_forward
		)
		if rotation_axis.length_squared() <= EPSILON and angle > PI * 0.5:
			# Antiparallel headings give slerp no rotation axis (Godot falls
			# back to lerp, which normalizes back to the start vector and the
			# squadron never turns around). Yaw a fixed step to break the tie.
			owner_squadron._formation_forward = owner_squadron \
				._formation_forward.rotated(
					Vector3.UP, minf(turn_step, angle)
				).normalized()
		else:
			var weight := minf(1.0, turn_step / maxf(angle, EPSILON))
			owner_squadron._formation_forward = owner_squadron \
				._formation_forward.slerp(desired_forward, weight).normalized()
		var travel_distance := minf(
			get_effective_speed() * delta,
			horizontal_offset.length()
		)
		owner_squadron.formation_center += owner_squadron \
			._formation_forward * travel_distance
	owner_squadron.formation_center.y = move_toward(
		owner_squadron.formation_center.y,
		target.y,
		get_effective_speed() * 0.35 * delta
	)


func apply_direct_flight(
		direction: Vector3,
		speed_mps: float,
		delta: float,
		minimum_world_y: float
) -> void:
	if direction.length_squared() <= EPSILON:
		return
	owner_squadron._loiter_initialized = false
	destination_tracker.reached_serial = -1
	owner_squadron._formation_forward = direction.normalized()
	owner_squadron.formation_center += owner_squadron \
		._formation_forward * maxf(speed_mps, 0.0) * maxf(delta, 0.0)
	owner_squadron.formation_center.y = maxf(
		owner_squadron.formation_center.y,
		minimum_world_y
	)
	for aircraft in owner_squadron.get_alive_aircraft():
		aircraft.set_direct_flight(
			owner_squadron._formation_forward,
			speed_mps
		)


func finish_direct_flight_holding(world_altitude: float) -> void:
	owner_squadron.formation_center.y = world_altitude
	owner_squadron.destination = owner_squadron.formation_center
	destination_tracker.mark_reached(destination_tracker.command_serial)
	begin_loiter()
	restore_formation_flight()


func restore_formation_flight() -> void:
	for aircraft in owner_squadron.get_alive_aircraft():
		aircraft.set_formation_flight()
	update_formation_targets()


func begin_loiter() -> void:
	owner_squadron._loiter_center = owner_squadron.destination
	var offset := owner_squadron.formation_center \
		- owner_squadron._loiter_center
	offset.y = 0.0
	if offset.length_squared() <= EPSILON:
		offset = -owner_squadron._formation_forward * maxf(
			owner_squadron.squadron_data.loiter_radius_m,
			1.0
		)
	owner_squadron._loiter_angle_rad = atan2(offset.z, offset.x)
	owner_squadron._loiter_initialized = true
	owner_squadron.state = AircraftSquadron.State.HOLDING


func update_loiter(delta: float) -> void:
	if not owner_squadron._loiter_initialized:
		begin_loiter()
	var data := owner_squadron.squadron_data
	var radius := maxf(data.loiter_radius_m, 1.0)
	var angular_speed := deg_to_rad(maxf(
		data.loiter_angular_speed_deg_sec,
		0.0
	))
	var direction_sign := -1.0 if data.loiter_clockwise else 1.0
	owner_squadron._loiter_angle_rad = wrapf(
		owner_squadron._loiter_angle_rad
			+ angular_speed * direction_sign * maxf(delta, 0.0),
		-PI,
		PI
	)
	var loiter_target := owner_squadron._loiter_center + Vector3(
		cos(owner_squadron._loiter_angle_rad),
		0.0,
		sin(owner_squadron._loiter_angle_rad)
	) * radius
	loiter_target.y = owner_squadron.destination.y
	advance_formation_center(loiter_target, delta)


func update_formation_targets() -> void:
	var right := owner_squadron._formation_forward \
		.cross(Vector3.UP).normalized()
	if right.length_squared() <= EPSILON:
		right = Vector3.RIGHT
	for aircraft in owner_squadron.aircraft_units:
		if not is_instance_valid(aircraft) or not aircraft.active:
			continue
		var offset_multiplier := 0.8 \
			if owner_squadron._combat_formation_enabled else 1.0
		var offset := aircraft.formation_offset * offset_multiplier
		var world_offset := right * offset.x \
			+ Vector3.UP * offset.y \
			+ owner_squadron._formation_forward * offset.z
		aircraft.set_formation_target(
			owner_squadron.formation_center + world_offset
		)


func has_formation_arrived(target: Vector3) -> bool:
	var data := owner_squadron.squadron_data.aircraft_data
	var horizontal_distance := Vector2(
		target.x - owner_squadron.formation_center.x,
		target.z - owner_squadron.formation_center.z
	).length()
	return horizontal_distance <= maxf(data.arrival_distance_m, 1.0) \
		and absf(target.y - owner_squadron.formation_center.y) \
			<= maxf(data.arrival_distance_m, 1.0)

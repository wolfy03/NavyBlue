extends RefCounted
class_name DiveBombMissionBehavior
## AI mission lifecycle around the same coordinator used by player commands.

enum State {
	APPROACHING,
	DIVE_ENTRY,
	DIVING,
	PULLING_OUT,
	EGRESS,
	RETURNING,
	COMPLETED,
	FAILED,
}

const EPSILON := 0.0001

var owner_squadron: AircraftSquadron
var mission_data: AirMissionData
var state := State.FAILED
var successful := false

var _finished := true
var _target_request: DiveBombTargetRequest
var _coordinator: SquadronDiveBombCoordinator
var _active_destination_serial := -1
var _last_coordinator_snapshot := {}


func setup(
		next_owner_squadron: AircraftSquadron,
		target_ship: Node3D,
		next_mission_data: AirMissionData
) -> bool:
	if target_ship == null or not is_instance_valid(target_ship) \
			or not target_ship is ShipUnit:
		return false
	owner_squadron = next_owner_squadron
	mission_data = next_mission_data
	return setup_with_request(
		next_owner_squadron,
		_build_request_for_ship(target_ship as ShipUnit),
		next_mission_data
	)


func setup_with_request(
		next_owner_squadron: AircraftSquadron,
		request: DiveBombTargetRequest,
		next_mission_data: AirMissionData
) -> bool:
	cancel_without_return()
	owner_squadron = next_owner_squadron
	mission_data = next_mission_data
	if request == null or not _is_valid_squadron_setup():
		return false
	_target_request = request
	_coordinator = SquadronDiveBombCoordinator.new()
	if not _coordinator.setup(
		owner_squadron,
		request,
		DiveBombAttackMode.Type.NORMAL_APPROACH,
		1
	):
		_coordinator = null
		return false
	state = State.APPROACHING
	successful = false
	_finished = false
	return true


func update(delta: float) -> void:
	if _finished or _coordinator == null:
		return
	_coordinator.update(delta)
	_last_coordinator_snapshot = _coordinator.get_debug_snapshot()
	match _coordinator.state:
		SquadronDiveBombCoordinator.State.APPROACHING:
			state = State.APPROACHING
		SquadronDiveBombCoordinator.State.ATTACK_SPLIT, \
				SquadronDiveBombCoordinator.State.ALIGNING:
			state = State.DIVE_ENTRY
		SquadronDiveBombCoordinator.State.DIVING:
			state = State.DIVING
		SquadronDiveBombCoordinator.State.PULLING_OUT, \
				SquadronDiveBombCoordinator.State.REGROUPING:
			state = State.PULLING_OUT
		SquadronDiveBombCoordinator.State.COMPLETED:
			_begin_egress()
		SquadronDiveBombCoordinator.State.FAILED:
			_finish_and_return(false)
		_:
			pass
	if state == State.EGRESS:
		_update_egress()


func cancel_and_return() -> void:
	if _finished:
		return
	_finish_and_return(false)


func cancel_without_return() -> void:
	if _coordinator != null:
		_coordinator.cancel()
	_coordinator = null
	_finished = true
	successful = false
	state = State.FAILED
	_target_request = null


func get_state() -> int:
	return int(state)


func is_finished() -> bool:
	return _finished


func get_target_ship() -> Node3D:
	var resolved := get_resolved_target()
	return resolved.get_ship() if resolved != null else null


func get_resolved_target() -> DiveBombResolvedTarget:
	return _coordinator.get_resolved_target() \
		if _coordinator != null else null


func get_coordinator() -> SquadronDiveBombCoordinator:
	return _coordinator


func get_debug_snapshot() -> Dictionary:
	var result := {
		"state": State.keys()[int(state)],
		"successful": successful,
	}
	if _coordinator != null:
		result.merge(_coordinator.get_debug_snapshot(), true)
	elif not _last_coordinator_snapshot.is_empty():
		result.merge(_last_coordinator_snapshot, true)
	return result


func _build_request_for_ship(target_ship: ShipUnit) -> DiveBombTargetRequest:
	var request := DiveBombTargetRequest.new()
	request.source = DiveBombTargetRequest.Source.AI
	request.set_explicit_target(target_ship)
	request.designated_world_position = target_ship.global_position \
		if target_ship != null and is_instance_valid(target_ship) \
		else Vector3.ZERO
	request.acquisition_radius_m = owner_squadron \
		.get_dive_bomber_combat_data().get_target_acquisition_radius_m() \
		if owner_squadron != null \
		and owner_squadron.get_dive_bomber_combat_data() != null else 0.0
	request.requesting_team = owner_squadron.get_team() \
		if owner_squadron != null else &"neutral"
	request.allow_position_fallback = false
	return request


func _begin_egress() -> void:
	if state == State.EGRESS or _finished:
		return
	var direction := owner_squadron.get_formation_forward()
	direction.y = 0.0
	var resolved := get_resolved_target()
	if direction.length_squared() <= EPSILON and resolved != null:
		direction = resolved.get_aim_position() \
			- owner_squadron.formation_center
		direction.y = 0.0
	direction = direction.normalized() \
		if direction.length_squared() > EPSILON else Vector3.FORWARD
	var weapon_data := owner_squadron.get_aircraft_weapon_data()
	var distance := weapon_data.attack_egress_distance_m \
		if weapon_data != null else 700.0
	var destination := owner_squadron.formation_center \
		+ direction * maxf(distance, 0.0)
	destination.y = _get_operating_world_altitude()
	_active_destination_serial = owner_squadron.set_mission_destination(
		destination,
		true,
		&"dive_bomb_egress"
	)
	state = State.EGRESS


func _update_egress() -> void:
	if not owner_squadron.has_reached_mission_destination(
		_active_destination_serial
	):
		return
	successful = true
	_finished = true
	state = State.COMPLETED
	if mission_data == null or mission_data.return_after_attack:
		state = State.RETURNING
		owner_squadron.request_return()


func _finish_and_return(was_successful: bool) -> void:
	if _coordinator != null:
		_last_coordinator_snapshot = _coordinator.get_debug_snapshot()
		_coordinator.cancel()
	_coordinator = null
	successful = was_successful
	_finished = true
	state = State.COMPLETED if was_successful else State.FAILED
	if owner_squadron != null and is_instance_valid(owner_squadron):
		state = State.RETURNING
		owner_squadron.request_return()


func _get_operating_world_altitude() -> float:
	var carrier := owner_squadron.get_owner_carrier()
	var base_height := carrier.global_position.y if carrier != null else 0.0
	return base_height \
		+ owner_squadron.squadron_data.aircraft_data.operating_altitude_m


func _is_valid_squadron_setup() -> bool:
	return owner_squadron != null \
		and is_instance_valid(owner_squadron) \
		and owner_squadron.get_aircraft_role() \
			== AircraftData.AircraftRole.DIVE_BOMBER \
		and owner_squadron.get_dive_bomber_combat_data() != null \
		and owner_squadron.get_dive_bomber_combat_data().validate().is_empty() \
		and mission_data != null \
		and mission_data.validate().is_empty() \
		and mission_data.mission_type \
			== AirMissionData.MissionType.STRIKE_SHIP

extends RefCounted
class_name PlayerDiveBombRun
## Thin player-command adapter around the shared squadron coordinator.

enum State {
	MOVING_TO_ENTRY,
	DIVING,
	DONE,
}

var state := State.DONE
var successful := false

var _squadron: AircraftSquadron
var _target_request: DiveBombTargetRequest
var _coordinator: SquadronDiveBombCoordinator


func setup(
		squadron: AircraftSquadron,
		target_point: Vector3,
		_dispersion_radius_m: float,
		explicit_target: ShipUnit = null,
		attack_mode: int = DiveBombAttackMode.Type.NORMAL_APPROACH
) -> bool:
	cancel(&"replaced")
	if squadron == null or not is_instance_valid(squadron):
		return false
	var dive_data := squadron.get_dive_bomber_combat_data()
	if dive_data == null:
		return false
	_squadron = squadron
	_target_request = DiveBombTargetRequest.new()
	_target_request.source = DiveBombTargetRequest.Source.PLAYER
	_target_request.set_explicit_target(explicit_target)
	_target_request.designated_world_position = target_point
	_target_request.acquisition_radius_m = \
		dive_data.get_target_acquisition_radius_m()
	_target_request.requesting_team = squadron.get_team()
	_target_request.allow_position_fallback = true
	_coordinator = SquadronDiveBombCoordinator.new()
	if not _coordinator.setup(
		squadron,
		_target_request,
		attack_mode,
		1
	):
		_coordinator = null
		_squadron = null
		state = State.DONE
		return false
	state = State.MOVING_TO_ENTRY \
		if attack_mode == DiveBombAttackMode.Type.NORMAL_APPROACH \
		else State.DIVING
	successful = false
	return true


func update(delta: float) -> void:
	if _coordinator == null or is_finished():
		return
	_coordinator.update(delta)
	if _coordinator.is_completed():
		successful = true
		state = State.DONE
	elif _coordinator.is_failed():
		successful = false
		state = State.DONE
	elif _coordinator.state != SquadronDiveBombCoordinator.State.APPROACHING:
		state = State.DIVING


func is_finished() -> bool:
	return state == State.DONE


func cancel(_reason: StringName = &"") -> void:
	if _coordinator != null:
		_coordinator.cancel()
	_coordinator = null
	_squadron = null
	state = State.DONE
	successful = false


func get_resolved_target() -> DiveBombResolvedTarget:
	return _coordinator.get_resolved_target() \
		if _coordinator != null else null


func get_coordinator() -> SquadronDiveBombCoordinator:
	return _coordinator


func get_debug_snapshot() -> Dictionary:
	var result := {
		"state": State.keys()[int(state)],
		"successful": successful,
		"designated_world_position": _target_request.designated_world_position \
			if _target_request != null else Vector3.ZERO,
	}
	if _coordinator != null:
		result.merge(_coordinator.get_debug_snapshot(), true)
	return result

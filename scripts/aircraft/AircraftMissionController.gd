extends Node
class_name AircraftMissionController

signal mission_completed
signal mission_failed

enum MissionState {
	IDLE,
	APPROACHING,
	ATTACK_RUN,
	RELEASING,
	EGRESS,
	RETURNING,
	COMPLETED,
	FAILED,
}

const EPSILON := 0.0001

var owner_squadron: AircraftSquadron
var mission_data: AirMissionData
var state: MissionState = MissionState.IDLE

var _target_ref: WeakRef
var _event_finished := false
var _approach_initialized := false
var _move_destination := Vector3.ZERO
var intercept_behavior: InterceptMissionBehavior
var dive_bomb_behavior: DiveBombMissionBehavior
var battle_services: BattleServices


func setup(
		next_owner_squadron: AircraftSquadron,
		next_battle_services: BattleServices = null
) -> void:
	owner_squadron = next_owner_squadron
	battle_services = next_battle_services
	mission_data = null
	state = MissionState.IDLE
	_target_ref = null
	_event_finished = false
	_approach_initialized = false
	_move_destination = Vector3.ZERO
	intercept_behavior = null
	dive_bomb_behavior = null


func assign_ship_strike(
		target_ship: Node3D,
		next_mission_data: AirMissionData
) -> bool:
	if owner_squadron == null \
			or not is_instance_valid(owner_squadron) \
			or not _is_valid_target(target_ship) \
			or next_mission_data == null \
			or next_mission_data.mission_type \
				!= AirMissionData.MissionType.STRIKE_SHIP:
		return false
	var behavior := DiveBombMissionBehavior.new()
	if not behavior.setup(
		owner_squadron,
		target_ship,
		next_mission_data
	):
		return false
	mission_data = next_mission_data
	_target_ref = weakref(target_ship)
	dive_bomb_behavior = behavior
	state = MissionState.APPROACHING
	_event_finished = false
	_approach_initialized = false
	_publish_mission_event(&"air_mission_started", target_ship)
	return true


func assign_move(
		world_position: Vector3,
		next_mission_data: AirMissionData
) -> bool:
	if owner_squadron == null \
			or not is_instance_valid(owner_squadron) \
			or next_mission_data == null \
			or next_mission_data.mission_type \
				!= AirMissionData.MissionType.MOVE:
		return false
	mission_data = next_mission_data
	_target_ref = null
	_move_destination = world_position
	state = MissionState.APPROACHING
	_event_finished = false
	_approach_initialized = false
	_emit_mission_started(null)
	return true


func assign_return(next_mission_data: AirMissionData) -> bool:
	if owner_squadron == null \
			or not is_instance_valid(owner_squadron) \
			or next_mission_data == null \
			or next_mission_data.mission_type \
				!= AirMissionData.MissionType.RETURN_TO_CARRIER:
		return false
	mission_data = next_mission_data
	_target_ref = null
	state = MissionState.RETURNING
	_event_finished = false
	_emit_mission_started(null)
	owner_squadron.request_return()
	return true


func assign_aircraft_intercept(
		target_squadron: AircraftSquadron,
		next_mission_data: AirMissionData,
		rng_seed: int = 0
) -> bool:
	if owner_squadron == null \
			or not is_instance_valid(owner_squadron) \
			or target_squadron == null \
			or not is_instance_valid(target_squadron) \
			or target_squadron == owner_squadron \
			or next_mission_data == null \
			or next_mission_data.mission_type \
				!= AirMissionData.MissionType.INTERCEPT_AIRCRAFT \
			or owner_squadron.get_aircraft_role() \
				!= AircraftData.AircraftRole.FIGHTER \
			or owner_squadron.get_fighter_combat_data() == null \
			or not FactionRelations.are_hostile(
				owner_squadron.get_team(),
				target_squadron.get_team()
			):
		return false
	var weapon_data := owner_squadron.get_aircraft_weapon_data()
	if weapon_data == null \
			or weapon_data.weapon_type \
				!= AircraftWeaponData.WeaponType.AIR_TO_AIR_GUN:
		return false
	var behavior := InterceptMissionBehavior.new()
	if not behavior.setup(
		owner_squadron,
		target_squadron,
		next_mission_data,
		rng_seed
	):
		return false
	mission_data = next_mission_data
	_target_ref = null
	intercept_behavior = behavior
	state = MissionState.APPROACHING
	_event_finished = false
	_approach_initialized = false
	_emit_mission_started(target_squadron)
	return true


func update_mission(_delta: float) -> void:
	if state == MissionState.IDLE \
			or state == MissionState.COMPLETED \
			or state == MissionState.FAILED:
		return
	if mission_data != null \
			and mission_data.mission_type \
				== AirMissionData.MissionType.INTERCEPT_AIRCRAFT:
		if intercept_behavior == null:
			fail_without_return()
			return
		intercept_behavior.update(_delta)
		if intercept_behavior.is_finished():
			_finish_intercept_event(intercept_behavior.successful)
		return
	if mission_data != null \
			and mission_data.mission_type \
				== AirMissionData.MissionType.STRIKE_SHIP:
		if dive_bomb_behavior == null:
			fail_without_return()
			return
		dive_bomb_behavior.update(_delta)
		if dive_bomb_behavior.is_finished():
			_finish_dive_bomb_event(dive_bomb_behavior.successful)
		return
	if mission_data != null \
			and mission_data.mission_type == AirMissionData.MissionType.MOVE:
		_update_move_mission()
		return
	if mission_data != null \
			and mission_data.mission_type \
				== AirMissionData.MissionType.RETURN_TO_CARRIER:
		return
	fail_without_return()


func cancel_and_return() -> void:
	if state == MissionState.COMPLETED or state == MissionState.FAILED:
		return
	if intercept_behavior != null \
			and mission_data != null \
			and mission_data.mission_type \
				== AirMissionData.MissionType.INTERCEPT_AIRCRAFT:
		intercept_behavior.cancel_and_return()
		_finish_intercept_event(false)
		return
	if dive_bomb_behavior != null \
			and mission_data != null \
			and mission_data.mission_type \
				== AirMissionData.MissionType.STRIKE_SHIP:
		dive_bomb_behavior.cancel_and_return()
		_finish_dive_bomb_event(false)
		return
	_fail_and_return()


func fail_without_return() -> void:
	if _event_finished:
		return
	if intercept_behavior != null:
		intercept_behavior.cancel_without_return()
	if dive_bomb_behavior != null:
		dive_bomb_behavior.cancel_without_return()
	_event_finished = true
	state = MissionState.FAILED
	mission_failed.emit()
	_publish_mission_event(&"air_mission_failed")


func cancel_mission_due_to_carrier_loss() -> void:
	fail_without_return()


func cancel_current_mission_for_player_command() -> void:
	if state in [
		MissionState.IDLE,
		MissionState.COMPLETED,
		MissionState.FAILED,
		MissionState.RETURNING,
	]:
		return
	if intercept_behavior != null:
		intercept_behavior.cancel_without_return()
	if dive_bomb_behavior != null:
		dive_bomb_behavior.cancel_without_return()
	intercept_behavior = null
	dive_bomb_behavior = null
	mission_data = null
	_target_ref = null
	_event_finished = true
	_approach_initialized = false
	state = MissionState.IDLE


func has_valid_target() -> bool:
	return get_target_ship() != null or get_target_squadron() != null


func get_target_ship() -> Node3D:
	if _target_ref == null:
		return null
	var value: Variant = _target_ref.get_ref()
	var target := value as Node3D
	return target if _is_valid_target(target) else null


func get_target_squadron() -> AircraftSquadron:
	return intercept_behavior.get_target_squadron() \
		if intercept_behavior != null else null


func _finish_dive_bomb_event(success: bool) -> void:
	if _event_finished:
		return
	_event_finished = true
	state = MissionState.RETURNING \
		if owner_squadron != null \
		and is_instance_valid(owner_squadron) \
		and owner_squadron.state == AircraftSquadron.State.RETURNING \
		else (
			MissionState.COMPLETED if success else MissionState.FAILED
		)
	if success:
		mission_completed.emit()
		_publish_mission_event(&"air_mission_completed")
	else:
		mission_failed.emit()
		_publish_mission_event(&"air_mission_failed")


func _update_move_mission() -> void:
	if not _approach_initialized:
		owner_squadron.set_mission_destination(_move_destination)
		_approach_initialized = true
	if owner_squadron.state != AircraftSquadron.State.HOLDING \
			or _event_finished:
		return
	_event_finished = true
	state = MissionState.COMPLETED
	mission_completed.emit()
	_publish_mission_event(&"air_mission_completed")


func _fail_and_return() -> void:
	if _event_finished:
		return
	_event_finished = true
	state = MissionState.FAILED
	mission_failed.emit()
	_publish_mission_event(&"air_mission_failed")
	if owner_squadron != null and is_instance_valid(owner_squadron):
		owner_squadron.request_return()


func _emit_mission_started(target: Node3D) -> void:
	_publish_mission_event(&"air_mission_started", target)


func _finish_intercept_event(success: bool) -> void:
	if _event_finished:
		return
	_event_finished = true
	state = MissionState.RETURNING \
		if owner_squadron != null \
		and is_instance_valid(owner_squadron) \
		and owner_squadron.state == AircraftSquadron.State.RETURNING \
		else (
			MissionState.COMPLETED if success else MissionState.FAILED
		)
	if success:
		mission_completed.emit()
		_publish_mission_event(&"air_mission_completed")
	else:
		mission_failed.emit()
		_publish_mission_event(&"air_mission_failed")


func _publish_mission_event(
		event_name: StringName,
		target: Node3D = null
) -> void:
	if battle_services == null:
		return
	var arguments: Array = [owner_squadron]
	if target != null:
		arguments.append(target)
	battle_services.publish(event_name, arguments)


func _is_valid_target(target: Node3D) -> bool:
	if target == null or not is_instance_valid(target) \
			or target.is_queued_for_deletion():
		return false
	if target.has_method(&"is_alive"):
		return bool(target.call(&"is_alive"))
	return true

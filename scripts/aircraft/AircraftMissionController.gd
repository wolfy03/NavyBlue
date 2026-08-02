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
var torpedo_attack_planner := TorpedoAttackPlanner.new()
var battle_services: BattleServices

# AI torpedo approach re-tracking state.
var _torpedo_repath_timer := 0.0
var _torpedo_tracking_id := 0
var _torpedo_solution_revision := 0
var _torpedo_last_plan_failure_reason: StringName
var _torpedo_last_plan_failure_disposition := \
	TorpedoAttackResolveResult.FailureDisposition.RETRYABLE


func setup(
		next_owner_squadron: AircraftSquadron,
		next_battle_services: BattleServices = null
) -> void:
	shutdown()
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
	torpedo_attack_planner = TorpedoAttackPlanner.new()
	_reset_torpedo_repath_state()


func shutdown() -> void:
	owner_squadron = null
	battle_services = null
	mission_data = null
	state = MissionState.IDLE
	_target_ref = null
	_event_finished = false
	_approach_initialized = false
	_move_destination = Vector3.ZERO
	intercept_behavior = null
	dive_bomb_behavior = null
	torpedo_attack_planner = TorpedoAttackPlanner.new()
	_reset_torpedo_repath_state()


func assign_ship_strike(
		target_ship: Node3D,
		next_mission_data: AirMissionData
) -> bool:
	if owner_squadron == null \
			or not is_instance_valid(owner_squadron) \
			or not _is_valid_target(target_ship) \
			or next_mission_data == null \
			or next_mission_data.mission_type not in [
				AirMissionData.MissionType.STRIKE_SHIP,
				AirMissionData.MissionType.TORPEDO_ATTACK,
			]:
		return false
	if next_mission_data.mission_type \
			== AirMissionData.MissionType.TORPEDO_ATTACK:
		return _assign_torpedo_strike(
			target_ship as ShipUnit,
			next_mission_data
		)
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
			and mission_data.mission_type \
				== AirMissionData.MissionType.TORPEDO_ATTACK:
		_update_torpedo_attack_mission(_delta)
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
	if mission_data != null \
			and mission_data.mission_type \
				== AirMissionData.MissionType.TORPEDO_ATTACK:
		if owner_squadron != null \
				and owner_squadron.torpedo_attack_controller != null:
			owner_squadron.torpedo_attack_controller.abort(
				&"mission_cancelled"
			)
		_fail_and_return()
		return
	_fail_and_return()


func fail_without_return() -> void:
	if _event_finished:
		return
	if intercept_behavior != null:
		intercept_behavior.cancel_without_return()
	if dive_bomb_behavior != null:
		dive_bomb_behavior.cancel_without_return()
	if owner_squadron != null \
			and owner_squadron.torpedo_attack_controller != null \
			and owner_squadron.torpedo_attack_controller.is_active():
		owner_squadron.torpedo_attack_controller.abort(
			&"mission_failed",
			false
		)
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
	if owner_squadron != null \
			and owner_squadron.torpedo_attack_controller != null \
			and owner_squadron.torpedo_attack_controller.is_active():
		owner_squadron.torpedo_attack_controller.abort(
			&"player_override",
			false
		)
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


func _assign_torpedo_strike(
		target_ship: ShipUnit,
		next_mission_data: AirMissionData
) -> bool:
	if owner_squadron.get_aircraft_role() \
			!= AircraftData.AircraftRole.TORPEDO_BOMBER \
			or owner_squadron.torpedo_attack_controller == null:
		return false
	var plan := torpedo_attack_planner.plan_attack(
		owner_squadron,
		target_ship,
		null,
		next_mission_data.target_prediction_enabled,
		next_mission_data.approach_repath_interval_sec
	)
	if not plan.success:
		_record_torpedo_plan_failure(plan)
		return false
	owner_squadron.set_command_authority(
		AircraftSquadron.CommandAuthority.AI
	)
	if not owner_squadron.torpedo_attack_controller.begin_attack(
		plan.command
	):
		return false
	mission_data = next_mission_data
	_target_ref = weakref(target_ship)
	state = MissionState.ATTACK_RUN
	_event_finished = false
	_approach_initialized = true
	_reset_torpedo_repath_state()
	# The controller allocated its own tracking id inside begin_attack; mirror it
	# so re-aims stay part of the same tracked attack rather than looking new.
	var live_command := owner_squadron.torpedo_attack_controller.get_command()
	if live_command != null:
		_torpedo_tracking_id = live_command.tracking_id
		_torpedo_solution_revision = live_command.solution_revision
	# Give the controller a way to fetch one last fresh solution before it locks.
	owner_squadron.torpedo_attack_controller.solution_refresher = \
		Callable(self, "_refresh_torpedo_solution")
	_publish_mission_event(&"air_mission_started", target_ship)
	return true


func _update_torpedo_attack_mission(delta: float = 0.0) -> void:
	if _event_finished or owner_squadron == null \
			or owner_squadron.torpedo_attack_controller == null:
		return
	var controller := owner_squadron.torpedo_attack_controller
	if controller.is_active():
		_tick_torpedo_repath(controller, delta)
		return
	var finish_result := controller.get_finish_result()
	var success := finish_result in [
		TorpedoAttackController.FinishResult.SUCCESS,
		TorpedoAttackController.FinishResult.PARTIAL_RELEASE,
	]
	_event_finished = true
	state = MissionState.COMPLETED if success else MissionState.FAILED
	if success:
		mission_completed.emit()
		_publish_mission_event(&"air_mission_completed")
	else:
		mission_failed.emit()
		_publish_mission_event(&"air_mission_failed")
	if mission_data != null and mission_data.return_after_attack:
		owner_squadron.request_return()
		state = MissionState.RETURNING


func _tick_torpedo_repath(
		controller: TorpedoAttackController,
		delta: float
) -> void:
	# Re-aim the AI torpedo run at the moving target during the approach, at most
	# once per repath interval, and only when the solution meaningfully changed.
	if mission_data == null or not mission_data.target_prediction_enabled:
		return
	if not controller.can_update_attack_solution():
		return
	_torpedo_repath_timer += delta
	if _torpedo_repath_timer < mission_data.approach_repath_interval_sec:
		return
	_torpedo_repath_timer = 0.0
	var target := get_target_ship() as ShipUnit
	if target == null:
		return
	var current := controller.get_command()
	if current == null:
		return
	var plan := torpedo_attack_planner.plan_attack(
		owner_squadron,
		target,
		null,
		true,
		mission_data.approach_repath_interval_sec
	)
	if not plan.success or plan.command == null:
		_record_torpedo_plan_failure(plan)
		if plan.failure_disposition \
				== TorpedoAttackResolveResult.FailureDisposition.FATAL:
			controller.abort_before_attack(plan.failure_reason)
		return
	if not _torpedo_solution_changed(current, plan.command):
		return
	# Preserve the tracked-attack identity and advance the revision so the
	# controller accepts this as a newer solution for the same run.
	plan.command.tracking_id = _torpedo_tracking_id
	_torpedo_solution_revision += 1
	plan.command.solution_revision = _torpedo_solution_revision
	if controller.update_attack_solution(plan.command):
		_torpedo_solution_revision = controller.get_command().solution_revision


func _torpedo_solution_changed(
		current: TorpedoAttackCommand,
		candidate: TorpedoAttackCommand
) -> bool:
	var impact_shift := candidate.predicted_impact_position.distance_to(
		current.predicted_impact_position
	)
	if impact_shift >= mission_data.approach_repath_threshold_m:
		return true
	var profile := owner_squadron.get_torpedo_attack_profile()
	if profile == null:
		return false
	var current_dir := current.attack_direction
	var candidate_dir := candidate.attack_direction
	if current_dir.length_squared() <= EPSILON \
			or candidate_dir.length_squared() <= EPSILON:
		return false
	var angle := rad_to_deg(current_dir.angle_to(candidate_dir))
	return angle >= profile.attack_direction_repath_threshold_deg


func _refresh_torpedo_solution() -> TorpedoAttackCommand:
	# Invoked by the controller just before it locks. Returns a fresh solution
	# for the current target, or null to keep the existing one.
	if owner_squadron == null or not is_instance_valid(owner_squadron):
		return null
	if mission_data == null:
		return null
	var target := get_target_ship() as ShipUnit
	if target == null:
		return null
	var plan := torpedo_attack_planner.plan_attack(
		owner_squadron,
		target,
		null,
		mission_data.target_prediction_enabled,
		mission_data.approach_repath_interval_sec
	)
	if not plan.success or plan.command == null:
		_record_torpedo_plan_failure(plan)
		return null
	plan.command.tracking_id = _torpedo_tracking_id
	_torpedo_solution_revision += 1
	plan.command.solution_revision = _torpedo_solution_revision
	return plan.command


func _reset_torpedo_repath_state() -> void:
	_torpedo_repath_timer = 0.0
	_torpedo_tracking_id = 0
	_torpedo_solution_revision = 0
	_torpedo_last_plan_failure_reason = StringName()
	_torpedo_last_plan_failure_disposition = \
		TorpedoAttackResolveResult.FailureDisposition.RETRYABLE


func get_torpedo_last_plan_failure_reason() -> StringName:
	return _torpedo_last_plan_failure_reason


func _record_torpedo_plan_failure(
		plan: TorpedoAttackResolveResult
) -> void:
	if plan == null:
		_torpedo_last_plan_failure_reason = &"missing_plan_result"
		_torpedo_last_plan_failure_disposition = \
			TorpedoAttackResolveResult.FailureDisposition.FATAL
	else:
		_torpedo_last_plan_failure_reason = plan.failure_reason
		_torpedo_last_plan_failure_disposition = plan.failure_disposition
	if owner_squadron != null \
			and owner_squadron.torpedo_attack_controller != null:
		owner_squadron.torpedo_attack_controller.record_solution_failure(
			_torpedo_last_plan_failure_reason
		)


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
	match event_name:
		&"air_mission_started":
			battle_services.events.emit_air_mission_started(
				owner_squadron,
				target
			)
		&"air_mission_completed":
			battle_services.events.emit_air_mission_completed(owner_squadron)
		&"air_mission_failed":
			battle_services.events.emit_air_mission_failed(owner_squadron)


func _is_valid_target(target: Node3D) -> bool:
	if target == null or not is_instance_valid(target) \
			or target.is_queued_for_deletion():
		return false
	if target.has_method(&"is_alive"):
		return bool(target.call(&"is_alive"))
	return true

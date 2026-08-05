extends Node3D
class_name AircraftSquadron

signal recovery_completed(squadron)
signal squadron_lost(squadron)
signal aircraft_lost(squadron, aircraft: AircraftUnit)
signal formation_activated(squadron)
signal return_requested(squadron)
signal player_selection_changed(selected: bool)
signal player_destination_changed(snapshot: SquadronDestinationSnapshot)
signal player_destination_reached
signal aircraft_weapon_release_finished(
	aircraft_id: int,
	aircraft: AircraftUnit,
	success: bool,
	cancelled: bool,
	reason: int
)
signal dive_release_pass_finished(
	released_count: int,
	failed_count: int,
	skipped_count: int,
	cancelled: bool
)

enum State {
	FORMING,
	EN_ROUTE,
	HOLDING,
	RETURNING,
	RECOVERING,
	DESTROYED,
}

enum CommandAuthority {
	AI,
	PLAYER,
}

enum DiveControlSource {
	NONE,
	PLAYER,
	AI,
}

const EPSILON := 0.0001
@onready var mission_controller: AircraftMissionController = get_node_or_null(
	"AircraftMissionController"
) as AircraftMissionController
@onready var torpedo_attack_controller: TorpedoAttackController = \
	get_node_or_null("TorpedoAttackController") as TorpedoAttackController

@export var manual_return_after_release := false
@export var destination_change_epsilon_m := 5.0
var squadron_data: SquadronData
var aircraft_units: Array[AircraftUnit] = []
var state: State = State.FORMING
var destination: Vector3 = Vector3.ZERO
var formation_center: Vector3 = Vector3.ZERO
var command_authority: CommandAuthority = CommandAuthority.AI
var player_selected := false
var dive_control_source: DiveControlSource = DiveControlSource.NONE

var _owner_carrier_ref: WeakRef
var _formation_forward: Vector3 = Vector3.FORWARD
var _launch_elapsed_sec := 0.0
var _next_aircraft_to_activate := 0
var _completion_emitted := false
var payload_release_coordinator := AircraftPayloadReleaseCoordinator.new()
var destination_tracker := SquadronDestinationTracker.new()
var movement_controller := SquadronMovementController.new()
var lifecycle_controller := SquadronLifecycleController.new()
var _carrier_unavailable_cleanup_left := -1.0
var _requested_aircraft_count := -1
var _formation_activated_emitted := false
var _team: StringName = &"neutral"
var _combat_formation_enabled := false
var _fighter_target_squadron_ref: WeakRef
var _manual_move_target := Vector3.ZERO
var _has_manual_move_target := false
var _manual_attack_target_ref: WeakRef
var _player_dive_run: PlayerDiveBombRun
var _loiter_center := Vector3.ZERO
var _loiter_angle_rad := 0.0
var _loiter_initialized := false
var battle_services: BattleServices


func setup(
		carrier: ShipUnit,
		data: SquadronData,
		aircraft_parent: Node,
		launch_aircraft_count: int = -1,
		next_battle_services: BattleServices = null
) -> void:
	shutdown()
	state = State.FORMING
	_completion_emitted = false
	_formation_activated_emitted = false
	_owner_carrier_ref = weakref(carrier) \
		if carrier != null and is_instance_valid(carrier) else null
	squadron_data = data
	battle_services = next_battle_services
	_requested_aircraft_count = launch_aircraft_count
	if get_parent() == null and aircraft_parent != null:
		aircraft_parent.add_child(self)
	var owner_carrier := get_owner_carrier()
	if owner_carrier == null or squadron_data == null \
			or squadron_data.aircraft_data == null:
		state = State.DESTROYED
		return
	_team = owner_carrier.team
	payload_release_coordinator.setup(
		self,
		squadron_data.payload_release_settings
	)
	movement_controller.setup(self, destination_tracker)
	lifecycle_controller.setup(self)
	if not payload_release_coordinator.aircraft_release_finished.is_connected(
		_on_aircraft_payload_release_finished
	):
		payload_release_coordinator.aircraft_release_finished.connect(
			_on_aircraft_payload_release_finished
		)
	if not payload_release_coordinator.pass_finished.is_connected(
		_on_payload_release_pass_finished
	):
		payload_release_coordinator.pass_finished.connect(
			_on_payload_release_pass_finished
		)
	add_to_group(&"aircraft_squadrons")
	formation_center = _get_carrier_launch_position()
	destination_tracker.reset()
	_formation_forward = -owner_carrier.global_transform.basis.z.normalized()
	if _formation_forward.length_squared() <= EPSILON:
		_formation_forward = Vector3.FORWARD
	_spawn_aircraft()
	if mission_controller != null:
		mission_controller.setup(self, battle_services)
	if torpedo_attack_controller != null:
		torpedo_attack_controller.setup(
			self,
			movement_controller,
			battle_services
		)
	var coordinator := get_combat_coordinator()
	if coordinator != null:
		coordinator.register_squadron(self)
	set_physics_process(false)


func shutdown() -> void:
	set_physics_process(false)
	var coordinator := get_combat_coordinator() if is_inside_tree() else null
	if coordinator != null:
		coordinator.unregister_intercept_assignment(self)
		coordinator.unregister_squadron(self)
	_cancel_player_dive_run(&"shutdown")
	if torpedo_attack_controller != null:
		torpedo_attack_controller.shutdown()
	if mission_controller != null:
		mission_controller.shutdown()
	if lifecycle_controller.owner_squadron != null:
		lifecycle_controller.release_aircraft()
	if payload_release_coordinator.aircraft_release_finished.is_connected(
		_on_aircraft_payload_release_finished
	):
		payload_release_coordinator.aircraft_release_finished.disconnect(
			_on_aircraft_payload_release_finished
		)
	if payload_release_coordinator.pass_finished.is_connected(
		_on_payload_release_pass_finished
	):
		payload_release_coordinator.pass_finished.disconnect(
			_on_payload_release_pass_finished
		)
	payload_release_coordinator.shutdown()
	movement_controller.shutdown()
	lifecycle_controller.shutdown()
	destination_tracker.shutdown()
	clear_fighter_targets()
	_owner_carrier_ref = null
	_manual_attack_target_ref = null
	_fighter_target_squadron_ref = null
	_player_dive_run = null
	aircraft_units.clear()
	battle_services = null
	if is_in_group(&"aircraft_squadrons"):
		remove_from_group(&"aircraft_squadrons")


func launch_to(world_position: Vector3) -> void:
	if state == State.DESTROYED or squadron_data == null:
		return
	destination = _clamp_destination_to_combat_radius(world_position)
	_loiter_initialized = false
	destination_tracker.begin_command(&"mission", destination.y)
	state = State.EN_ROUTE
	_launch_elapsed_sec = 0.0
	_next_aircraft_to_activate = 0
	_activate_next_aircraft()
	set_physics_process(true)


func request_return() -> void:
	if state == State.RECOVERING or state == State.DESTROYED:
		return
	if get_owner_carrier() == null:
		_mark_destroyed()
		return
	clear_fighter_targets()
	cancel_pending_weapon_release()
	_loiter_initialized = false
	destination_tracker.clear_active_command()
	_on_destination_command_changed()
	set_combat_formation_enabled(false)
	set_player_selected(false)
	dive_control_source = DiveControlSource.NONE
	_has_manual_move_target = false
	_manual_attack_target_ref = null
	_cancel_player_dive_run(&"return_requested")
	if torpedo_attack_controller != null \
			and torpedo_attack_controller.is_active():
		torpedo_attack_controller.abort(&"return_requested", false)
	var coordinator := get_combat_coordinator()
	if coordinator != null:
		coordinator.unregister_intercept_assignment(self)
	state = State.RETURNING
	return_requested.emit(self)
	set_physics_process(true)


func get_alive_aircraft_count() -> int:
	_prune_aircraft()
	var count := 0
	for aircraft in aircraft_units:
		if is_instance_valid(aircraft) \
				and aircraft.health != null \
				and aircraft.health.is_alive():
			count += 1
	return count


func get_alive_aircraft() -> Array[AircraftUnit]:
	_prune_aircraft()
	var result: Array[AircraftUnit] = []
	for aircraft in aircraft_units:
		if is_instance_valid(aircraft) and aircraft.is_alive():
			result.append(aircraft)
	return result


## Candidate ships for dive-bomb target resolution. Primary source is the
## battle-wide ship registry (maintained on spawn/despawn); the group lookup
## is a fallback for harnesses that build ships without BattleServices. Only
## called at resolve events (command, pass start, repath, target loss) —
## never per physics frame.
func get_dive_bomb_candidate_ships() -> Array[ShipUnit]:
	if battle_services == null or battle_services.ship_registry == null:
		return []
	return battle_services.ship_registry.get_alive_ships()


func assign_strike_mission(
		target_ship: Node3D,
		mission_data: AirMissionData
) -> bool:
	return mission_controller != null \
		and mission_controller.assign_ship_strike(target_ship, mission_data)


func assign_move_mission(
		world_position: Vector3,
		mission_data: AirMissionData
) -> bool:
	return mission_controller != null \
		and mission_controller.assign_move(world_position, mission_data)


func assign_return_mission(mission_data: AirMissionData) -> bool:
	return mission_controller != null \
		and mission_controller.assign_return(mission_data)


func assign_intercept_mission(
		target_squadron: AircraftSquadron,
		mission_data: AirMissionData,
		rng_seed: int = 0
) -> bool:
	return mission_controller != null \
		and mission_controller.assign_aircraft_intercept(
			target_squadron,
			mission_data,
			rng_seed
		)


func get_aircraft_role() -> AircraftData.AircraftRole:
	return squadron_data.aircraft_data.role \
		if squadron_data != null \
		and squadron_data.aircraft_data != null \
		else AircraftData.AircraftRole.RECON


func get_team() -> StringName:
	return _team


func get_fighter_combat_data() -> FighterCombatData:
	return squadron_data.aircraft_data.fighter_combat_data \
		if squadron_data != null \
		and squadron_data.aircraft_data != null else null


func set_command_authority(authority: CommandAuthority) -> void:
	command_authority = authority
	if authority == CommandAuthority.PLAYER:
		clear_fighter_targets()
		for aircraft in aircraft_units:
			if is_instance_valid(aircraft) \
					and aircraft.fighter_combat_controller != null:
				aircraft.fighter_combat_controller.disable_combat()


func is_player_commanded() -> bool:
	return command_authority == CommandAuthority.PLAYER


func set_player_selected(selected: bool) -> void:
	if player_selected == selected:
		return
	player_selected = selected
	player_selection_changed.emit(selected)


func cancel_current_mission_for_player_command() -> void:
	if state in [State.RETURNING, State.RECOVERING, State.DESTROYED]:
		return
	_cancel_player_dive_run(&"player_command")
	cancel_pending_weapon_release()
	clear_fighter_targets()
	var coordinator := get_combat_coordinator()
	if coordinator != null:
		coordinator.unregister_intercept_assignment(self)
	if mission_controller != null:
		mission_controller.cancel_current_mission_for_player_command()


func issue_player_move_command(
		world_position: Vector3,
		attack_target: ShipUnit = null
) -> bool:
	if not _can_accept_player_command():
		return false
	if torpedo_attack_controller != null \
			and torpedo_attack_controller.is_active():
		torpedo_attack_controller.abort(&"player_override", false)
	cancel_current_mission_for_player_command()
	set_command_authority(CommandAuthority.PLAYER)
	dive_control_source = DiveControlSource.NONE
	_manual_attack_target_ref = weakref(attack_target) \
		if _is_valid_manual_attack_target(attack_target) else null
	var carrier := get_owner_carrier()
	var data := squadron_data.aircraft_data
	_manual_move_target = world_position
	_manual_move_target.y = carrier.global_position.y \
		+ data.operating_altitude_m
	_manual_move_target = _clamp_destination_to_combat_radius(
		_manual_move_target
	)
	_has_manual_move_target = true
	set_mission_destination(
		_manual_move_target,
		true,
		&"player_move"
	)
	return true


func can_begin_manual_dive() -> bool:
	return _can_accept_player_command() \
		and is_player_commanded() \
		and get_aircraft_role() \
			== AircraftData.AircraftRole.DIVE_BOMBER \
		and (_player_dive_run == null or _player_dive_run.is_finished()) \
		and has_any_ammunition()


## Shared target selection for player dive orders: the same resolver and the
## same rules the AI mission uses. The explicit ship (clicked or manually
## targeted) wins, then the nearest hostile ship inside the acquisition
## radius around the designation, then the designated position itself.
func resolve_player_dive_target(
		designated_position: Vector3,
		explicit_target: ShipUnit = null
) -> DiveBombResolvedTarget:
	var dive_data := get_dive_bomber_combat_data()
	var request := DiveBombTargetRequest.new()
	request.source = DiveBombTargetRequest.Source.PLAYER
	request.set_explicit_target(explicit_target)
	request.designated_world_position = designated_position
	request.acquisition_radius_m = \
		dive_data.get_target_acquisition_radius_m() \
		if dive_data != null else 0.0
	request.requesting_team = get_team()
	request.allow_position_fallback = true
	return DiveBombTargetResolver.resolve(
		request,
		get_dive_bomb_candidate_ships()
	)


func begin_manual_dive() -> bool:
	var designation := _manual_move_target if _has_manual_move_target \
		else formation_center + get_formation_forward() * 600.0
	designation.y = 0.0
	return issue_manual_dive_bomb_command(
		designation,
		get_manual_attack_target(),
		DiveBombAttackMode.Type.QUICK_ATTACK
	)


func issue_manual_dive_bomb_command(
		designated_position: Vector3,
		explicit_target: ShipUnit = null,
		attack_mode: int = DiveBombAttackMode.Type.QUICK_ATTACK
) -> bool:
	if not can_begin_manual_dive():
		return false
	cancel_current_mission_for_player_command()
	var run := PlayerDiveBombRun.new()
	if not run.setup(
		self,
		designated_position,
		0.0,
		explicit_target,
		attack_mode
	):
		return false
	_player_dive_run = run
	dive_control_source = DiveControlSource.PLAYER
	set_physics_process(true)
	destination_tracker.clear_active_command()
	_on_destination_command_changed()
	return true


func begin_manual_dive_at(
		target_point: Vector3,
		_dispersion_radius_m: float = 0.0,
		explicit_target: ShipUnit = null
) -> bool:
	return issue_manual_dive_bomb_command(
		target_point,
		explicit_target,
		DiveBombAttackMode.Type.NORMAL_APPROACH
	)


func get_dive_bomber_combat_data() -> DiveBomberCombatData:
	return squadron_data.aircraft_data.dive_bomber_combat_data \
		if squadron_data != null \
		and squadron_data.aircraft_data != null else null


func _cancel_player_dive_run(reason: StringName) -> void:
	if _player_dive_run != null:
		_player_dive_run.cancel(reason)
		_player_dive_run = null
	if dive_control_source == DiveControlSource.PLAYER:
		dive_control_source = DiveControlSource.NONE


func get_dive_attack_state() -> int:
	if _player_dive_run != null \
			and _player_dive_run.get_coordinator() != null:
		return _player_dive_run.get_coordinator().state
	if mission_controller != null \
			and mission_controller.dive_bomb_behavior != null \
			and mission_controller.dive_bomb_behavior.get_coordinator() != null:
		return mission_controller.dive_bomb_behavior.get_coordinator().state
	return SquadronDiveBombCoordinator.State.IDLE


func is_dive_bomb_attack_active() -> bool:
	if _player_dive_run != null and not _player_dive_run.is_finished():
		return true
	return mission_controller != null \
		and mission_controller.dive_bomb_behavior != null \
		and not mission_controller.dive_bomb_behavior.is_finished()


func get_torpedo_attack_profile() -> TorpedoAttackProfile:
	return squadron_data.aircraft_data.torpedo_attack_profile \
		if squadron_data != null \
		and squadron_data.aircraft_data != null else null


func has_torpedo_payload() -> bool:
	var weapon_data := get_aircraft_weapon_data()
	return weapon_data != null \
		and weapon_data.weapon_type == AircraftWeaponData.WeaponType.TORPEDO \
		and has_any_ammunition()


func can_begin_manual_torpedo_attack() -> bool:
	return _can_accept_player_command() \
		and is_player_commanded() \
		and get_aircraft_role() \
			== AircraftData.AircraftRole.TORPEDO_BOMBER \
		and torpedo_attack_controller != null \
		and not torpedo_attack_controller.is_active() \
		and get_torpedo_attack_profile() != null \
		and get_torpedo_attack_profile().validate().is_empty() \
		and has_torpedo_payload()


func issue_player_torpedo_attack(command: TorpedoAttackCommand) -> bool:
	if not can_begin_manual_torpedo_attack() \
			or not torpedo_attack_controller.can_begin_attack(command):
		return false
	cancel_current_mission_for_player_command()
	set_command_authority(CommandAuthority.PLAYER)
	dive_control_source = DiveControlSource.NONE
	_has_manual_move_target = false
	_manual_attack_target_ref = weakref(command.target_ship) \
		if command.target_ship != null \
		and is_instance_valid(command.target_ship) else null
	return torpedo_attack_controller.begin_attack(command)


func abort_player_torpedo_attack(reason: StringName) -> void:
	# Roll back an applied player torpedo order (used when a multi-squadron
	# atomic apply fails partway). abort() does not consume ammunition, so any
	# payload that has not been released yet is preserved.
	if torpedo_attack_controller != null \
			and torpedo_attack_controller.is_active():
		torpedo_attack_controller.abort(reason, false)


func can_apply_torpedo_attack(command: TorpedoAttackCommand) -> bool:
	# Non-mutating pre-check used to apply multi-squadron torpedo orders
	# atomically: it must not change squadron or controller state.
	return can_begin_manual_torpedo_attack() \
		and torpedo_attack_controller != null \
		and torpedo_attack_controller.can_begin_attack(command)


func get_manual_attack_target() -> ShipUnit:
	if _manual_attack_target_ref == null:
		return null
	var target := _manual_attack_target_ref.get_ref() as ShipUnit
	return target if _is_valid_manual_attack_target(target) else null


func assign_fighter_targets(
		target_squadron: AircraftSquadron
) -> void:
	if target_squadron == null or not is_instance_valid(target_squadron):
		clear_fighter_targets()
		return
	var targets := target_squadron.get_alive_aircraft()
	if targets.is_empty():
		clear_fighter_targets()
		return
	var current_target_squadron := _fighter_target_squadron_ref.get_ref() \
		as AircraftSquadron \
		if _fighter_target_squadron_ref != null else null
	var needs_assignment := current_target_squadron != target_squadron
	if not needs_assignment:
		for attacker in get_alive_aircraft():
			if attacker.fighter_combat_controller == null \
					or attacker.fighter_combat_controller.get_target() == null:
				needs_assignment = true
				break
	if not needs_assignment:
		return
	_fighter_target_squadron_ref = weakref(target_squadron)
	var attackers := get_alive_aircraft()
	for index in range(attackers.size()):
		var controller := attackers[index].fighter_combat_controller
		if controller != null:
			controller.set_target(targets[index % targets.size()])


func clear_fighter_targets() -> void:
	_fighter_target_squadron_ref = null
	for aircraft in get_alive_aircraft():
		if aircraft.fighter_combat_controller != null:
			aircraft.fighter_combat_controller.clear_target()


func update_fighter_combat(
		delta: float,
		rng: RandomNumberGenerator
) -> Array[FighterShotResult]:
	var results: Array[FighterShotResult] = []
	for aircraft in get_alive_aircraft():
		if aircraft.fighter_combat_controller == null:
			continue
		var result := aircraft.fighter_combat_controller.update_combat(
			delta,
			rng
		)
		if result != null:
			results.append(result)
	return results


func set_combat_formation_enabled(enabled: bool) -> void:
	_combat_formation_enabled = enabled


func get_combat_coordinator() -> AircraftCombatCoordinator:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group(
		&"aircraft_combat_coordinator"
	) as AircraftCombatCoordinator


func request_aircraft_payload_release(
		aircraft: AircraftUnit,
		context: AircraftPayloadReleaseContext
) -> AircraftPayloadReleaseRequestResult:
	return payload_release_coordinator.request_release(aircraft, context)


func cancel_pending_weapon_release() -> void:
	payload_release_coordinator.cancel_all_requests()
	for aircraft in get_alive_aircraft():
		if aircraft.weapon_controller != null \
				and aircraft.weapon_controller.is_release_in_progress():
			aircraft.weapon_controller.cancel_pending_release()


func can_release_payload() -> bool:
	if is_weapon_release_in_progress():
		return false
	for aircraft in get_alive_aircraft():
		if aircraft.weapon_controller != null \
				and aircraft.weapon_controller.can_release():
			return true
	return false


func get_total_remaining_ammunition() -> int:
	var result := 0
	for aircraft in get_alive_aircraft():
		if aircraft.weapon_controller != null:
			result += aircraft.weapon_controller.get_remaining_ammunition()
	return result


func get_sortie_aircraft_count() -> int:
	if _requested_aircraft_count >= 0:
		return _requested_aircraft_count
	if squadron_data != null:
		return squadron_data.aircraft_count
	return aircraft_units.size()


func has_any_ammunition() -> bool:
	for aircraft in get_alive_aircraft():
		if aircraft.weapon_controller != null \
				and aircraft.weapon_controller.has_ammunition():
			return true
	return false


func is_weapon_release_in_progress() -> bool:
	return payload_release_coordinator.is_release_in_progress()


func begin_dive_release_pass() -> void:
	payload_release_coordinator.begin_pass()


func finish_dive_release_pass(
		controller_failed_count: int,
		skipped_count: int,
		cancelled: bool
) -> AircraftPayloadReleasePassResult:
	return payload_release_coordinator.finish_pass(
		controller_failed_count,
		skipped_count,
		cancelled
	)


func get_last_payload_release_result() -> AircraftPayloadReleasePassResult:
	return payload_release_coordinator.get_last_result()


func cancel_aircraft_weapon_release(aircraft_id: int) -> bool:
	var before: int = payload_release_coordinator.get_debug_snapshot() \
		.get("active_request_ids", []).size()
	payload_release_coordinator.cancel_aircraft_requests(aircraft_id)
	var after: int = payload_release_coordinator.get_debug_snapshot() \
		.get("active_request_ids", []).size()
	return after < before


func get_aircraft_weapon_data() -> AircraftWeaponData:
	return squadron_data.aircraft_data.weapon_data \
		if squadron_data != null \
			and squadron_data.aircraft_data != null else null


func get_formation_forward() -> Vector3:
	return _formation_forward


func get_formation_velocity() -> Vector3:
	return _formation_forward * _get_aircraft_speed()


func get_current_mission_state() -> int:
	return int(mission_controller.state) \
		if mission_controller != null else -1


func get_current_mission_id() -> String:
	return mission_controller.mission_data.id \
		if mission_controller != null \
		and mission_controller.mission_data != null else ""


func get_current_target() -> Node3D:
	if mission_controller != null:
		var target_squadron := mission_controller.get_target_squadron()
		if target_squadron != null:
			return target_squadron
	return mission_controller.get_target_ship() \
		if mission_controller != null else null


func get_release_debug_snapshot() -> Dictionary:
	var snapshot := payload_release_coordinator.get_debug_snapshot()
	snapshot["destination_serial"] = destination_tracker.command_serial
	snapshot["reached_destination_serial"] = \
		destination_tracker.reached_serial
	snapshot["mission_destination_reached"] = \
		destination_tracker.is_reached()
	return snapshot


func set_mission_destination(
		world_position: Vector3,
		force_new_command: bool = false,
		command_type: StringName = &"mission"
) -> int:
	return movement_controller.set_destination(
		world_position,
		force_new_command,
		command_type
	)


func has_reached_mission_destination(command_serial: int = -1) -> bool:
	return destination_tracker.is_reached(command_serial)


func get_destination_snapshot() -> SquadronDestinationSnapshot:
	return destination_tracker.get_snapshot(
		destination,
		state == State.HOLDING and _loiter_initialized
	)


func _on_destination_command_changed() -> void:
	if destination_tracker.command_type == &"player_move" \
			or not destination_tracker.active:
		player_destination_changed.emit(
			get_destination_snapshot()
		)


func _on_destination_command_reached() -> void:
	if destination_tracker.command_type != &"player_move":
		return
	player_destination_changed.emit(get_destination_snapshot())
	player_destination_reached.emit()


func handle_carrier_unavailable(cleanup_grace_sec: float = 2.0) -> void:
	_owner_carrier_ref = null
	cancel_pending_weapon_release()
	set_player_selected(false)
	dive_control_source = DiveControlSource.NONE
	_has_manual_move_target = false
	_manual_attack_target_ref = null
	_cancel_player_dive_run(&"carrier_unavailable")
	if torpedo_attack_controller != null \
			and torpedo_attack_controller.is_active():
		torpedo_attack_controller.abort(&"carrier_unavailable", false)
	clear_fighter_targets()
	for aircraft in aircraft_units:
		if not is_instance_valid(aircraft):
			continue
		if aircraft.weapon_controller != null:
			aircraft.weapon_controller.disable_weapon_release()
		if aircraft.fighter_combat_controller != null:
			aircraft.fighter_combat_controller.disable_combat()
	if mission_controller != null:
		mission_controller.cancel_mission_due_to_carrier_loss()
	var coordinator := get_combat_coordinator()
	if coordinator != null:
		coordinator.unregister_intercept_assignment(self)
	_carrier_unavailable_cleanup_left = maxf(cleanup_grace_sec, 0.0)
	set_physics_process(true)


func is_recovered() -> bool:
	return state == State.RECOVERING


func get_owner_carrier() -> ShipUnit:
	if _owner_carrier_ref == null:
		return null
	var carrier: Variant = _owner_carrier_ref.get_ref()
	return carrier as ShipUnit if is_instance_valid(carrier) else null


func release_aircraft() -> void:
	if lifecycle_controller.owner_squadron != null:
		lifecycle_controller.release_aircraft()


func _physics_process(delta: float) -> void:
	_prune_aircraft()
	if aircraft_units.is_empty():
		_mark_destroyed()
		return
	if _carrier_unavailable_cleanup_left >= 0.0:
		_carrier_unavailable_cleanup_left = maxf(
			0.0,
			_carrier_unavailable_cleanup_left - delta
		)
		if _carrier_unavailable_cleanup_left <= 0.0:
			for aircraft in get_alive_aircraft():
				aircraft.destroy_for_cleanup()
			_mark_destroyed()
			return
	lifecycle_controller.update_launch_sequence(delta)
	payload_release_coordinator.update(delta)
	if _player_dive_run != null:
		_player_dive_run.update(delta)
		if _player_dive_run.is_finished():
			var dive_succeeded := _player_dive_run.successful
			_player_dive_run = null
			dive_control_source = DiveControlSource.NONE
			if dive_succeeded and manual_return_after_release:
				request_return()
				return
	var torpedo_attack_was_active := torpedo_attack_controller != null \
		and torpedo_attack_controller.is_active()
	if torpedo_attack_was_active:
		torpedo_attack_controller.update_attack(delta)
	if mission_controller != null \
			and not is_player_commanded() \
			and state not in [
				State.RETURNING,
				State.RECOVERING,
				State.DESTROYED,
			]:
			mission_controller.update_mission(delta)
	if torpedo_attack_was_active:
		return
	movement_controller.update_standard_movement(delta)


func _on_aircraft_payload_release_finished(
		aircraft_id: int,
		aircraft: AircraftUnit,
		success: bool,
		cancelled: bool,
		reason: int
) -> void:
	aircraft_weapon_release_finished.emit(
		aircraft_id,
		aircraft,
		success,
		cancelled,
		reason
	)


func _on_payload_release_pass_finished(
		result: AircraftPayloadReleasePassResult
) -> void:
	dive_release_pass_finished.emit(
		result.released_count,
		result.failed_count,
		result.skipped_count,
		result.cancelled
	)


func _spawn_aircraft() -> void:
	lifecycle_controller.spawn_aircraft()


func _calculate_formation_offset(index: int, count: int) -> Vector3:
	return lifecycle_controller.calculate_formation_offset(index, count)


func _update_launch_sequence(delta: float) -> void:
	lifecycle_controller.update_launch_sequence(delta)


func _activate_next_aircraft() -> void:
	lifecycle_controller.activate_next_aircraft()


func _advance_formation_center(target: Vector3, delta: float) -> void:
	movement_controller.advance_formation_center(target, delta)


func apply_direct_flight(
		direction: Vector3,
		speed_mps: float,
		delta: float,
		minimum_world_y: float
) -> void:
	movement_controller.apply_direct_flight(
		direction,
		speed_mps,
		delta,
		minimum_world_y
	)


func finish_direct_flight_holding(world_altitude: float) -> void:
	movement_controller.finish_direct_flight_holding(world_altitude)


func restore_formation_flight() -> void:
	movement_controller.restore_formation_flight()


func _begin_loiter() -> void:
	movement_controller.begin_loiter()


func _update_loiter(delta: float) -> void:
	movement_controller.update_loiter(delta)


func get_average_alive_aircraft_position() -> Vector3:
	var aircraft := get_alive_aircraft()
	if aircraft.is_empty():
		return formation_center
	var total := Vector3.ZERO
	for unit in aircraft:
		total += unit.global_position
	return total / float(aircraft.size())


func get_average_alive_aircraft_altitude() -> float:
	return get_average_alive_aircraft_position().y


func is_formation_aligned(
		maximum_error_m: float
) -> bool:
	var errors := get_formation_alignment_errors()
	if errors.is_empty():
		return false
	var allowed_error := maxf(maximum_error_m, 0.0)
	for error in errors:
		if error > allowed_error:
			return false
	return true


func get_formation_alignment_errors() -> PackedFloat32Array:
	var alive_aircraft := get_alive_aircraft()
	var result := PackedFloat32Array()
	if alive_aircraft.is_empty():
		return result
	var right := _formation_forward.cross(Vector3.UP).normalized()
	if right.length_squared() <= EPSILON:
		right = Vector3.RIGHT
	var offset_multiplier := 0.8 if _combat_formation_enabled else 1.0
	for aircraft in alive_aircraft:
		var offset := aircraft.formation_offset * offset_multiplier
		var expected_position := formation_center \
			+ right * offset.x \
			+ Vector3.UP * offset.y \
			+ _formation_forward * offset.z
		result.append(aircraft.global_position.distance_to(expected_position))
	return result


func _update_aircraft_formation_targets() -> void:
	movement_controller.update_formation_targets()


func _has_formation_arrived(target: Vector3) -> bool:
	return movement_controller.has_formation_arrived(target)


func _get_aircraft_speed() -> float:
	if squadron_data == null or squadron_data.aircraft_data == null:
		return 0.0
	var data := squadron_data.aircraft_data
	return minf(
		maxf(data.cruise_speed_mps, 0.0),
		maxf(data.maximum_speed_mps, 0.0)
	)


func _clamp_destination_to_combat_radius(
		world_position: Vector3
) -> Vector3:
	var carrier := get_owner_carrier()
	var data := squadron_data.aircraft_data
	if carrier == null or data == null:
		return world_position
	var result := world_position
	var origin := carrier.global_position
	var horizontal := Vector2(
		world_position.x - origin.x,
		world_position.z - origin.z
	)
	var radius := maxf(data.combat_radius_m, 0.0)
	if radius > 0.0 and horizontal.length() > radius:
		horizontal = horizontal.normalized() * radius
		result.x = origin.x + horizontal.x
		result.z = origin.z + horizontal.y
	result.y = maxf(
		world_position.y,
		carrier.global_position.y + data.operating_altitude_m
	)
	return result


func _clamp_destination_horizontal(world_position: Vector3) -> Vector3:
	var carrier := get_owner_carrier()
	var data := squadron_data.aircraft_data
	if carrier == null or data == null:
		return world_position
	var result := world_position
	var horizontal := Vector2(
		world_position.x - carrier.global_position.x,
		world_position.z - carrier.global_position.z
	)
	var radius := maxf(data.combat_radius_m, 0.0)
	if radius > 0.0 and horizontal.length() > radius:
		horizontal = horizontal.normalized() * radius
		result.x = carrier.global_position.x + horizontal.x
		result.z = carrier.global_position.z + horizontal.y
	return result


func get_command_debug_snapshot() -> Dictionary:
	var attack_target := get_manual_attack_target()
	return {
		"command_authority": CommandAuthority.keys()[int(command_authority)],
		"manual_move_target": _manual_move_target,
		"has_manual_move_target": _has_manual_move_target,
		"manual_attack_target":
			attack_target.name if attack_target != null else "",
		"dive_control_source":
			DiveControlSource.keys()[int(dive_control_source)],
		"dive_attack_state":
			SquadronDiveBombCoordinator.State.keys()[
				int(get_dive_attack_state())
			],
	}


func _can_accept_player_command() -> bool:
	var carrier := get_owner_carrier()
	return carrier != null \
		and is_instance_valid(carrier) \
		and carrier.player_controlled \
		and get_team() == FactionRelations.PLAYER \
		and get_alive_aircraft_count() > 0 \
		and state not in [
			State.RETURNING,
			State.RECOVERING,
			State.DESTROYED,
		]


func _is_valid_manual_attack_target(target: ShipUnit) -> bool:
	var carrier := get_owner_carrier()
	return target != null \
		and is_instance_valid(target) \
		and not target.is_queued_for_deletion() \
		and target.is_alive() \
		and carrier != null \
		and carrier.is_hostile_to(target)


func _get_carrier_launch_position() -> Vector3:
	var carrier := get_owner_carrier()
	var air_group := carrier.carrier_air_group
	if air_group == null or air_group.air_group_data == null:
		return carrier.global_position
	return carrier.global_transform * air_group.air_group_data.launch_local_position


func _get_carrier_recovery_position() -> Vector3:
	var carrier := get_owner_carrier()
	var air_group := carrier.carrier_air_group
	if air_group == null or air_group.air_group_data == null:
		return carrier.global_position
	return carrier.global_transform \
		* air_group.air_group_data.recovery_local_position


func _complete_recovery() -> void:
	if _completion_emitted:
		return
	_completion_emitted = true
	cancel_pending_weapon_release()
	set_player_selected(false)
	var coordinator := get_combat_coordinator()
	if coordinator != null:
		coordinator.unregister_squadron(self)
	state = State.RECOVERING
	set_physics_process(false)
	for aircraft in aircraft_units:
		if is_instance_valid(aircraft):
			aircraft.deactivate()
	recovery_completed.emit(self)


func _mark_destroyed() -> void:
	if _completion_emitted:
		return
	_completion_emitted = true
	cancel_pending_weapon_release()
	if torpedo_attack_controller != null \
			and torpedo_attack_controller.is_active():
		torpedo_attack_controller.abort(&"squadron_destroyed", false)
	set_player_selected(false)
	var coordinator := get_combat_coordinator()
	if coordinator != null:
		coordinator.unregister_squadron(self)
	state = State.DESTROYED
	set_physics_process(false)
	if not squadron_lost.get_connections().is_empty():
		squadron_lost.emit(self)
		return
	if battle_services != null:
		battle_services.events.emit_squadron_destroyed(self)
	release_aircraft()
	queue_free()


func _on_aircraft_destroyed(aircraft: AircraftUnit) -> void:
	if aircraft == null:
		return
	var aircraft_id := aircraft.get_instance_id()
	payload_release_coordinator.unregister_aircraft(aircraft_id)
	aircraft_lost.emit(self, aircraft)
	call_deferred(&"_check_after_aircraft_loss")


func _check_after_aircraft_loss() -> void:
	_prune_aircraft()
	if get_alive_aircraft_count() > 0:
		return
	if mission_controller != null:
		mission_controller.fail_without_return()
	_mark_destroyed()


func _prune_aircraft() -> void:
	for index in range(aircraft_units.size() - 1, -1, -1):
		if not is_instance_valid(aircraft_units[index]):
			aircraft_units.remove_at(index)


func _exit_tree() -> void:
	shutdown()

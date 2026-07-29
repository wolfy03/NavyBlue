extends Node
class_name CarrierAirGroup

signal squadron_launched(squadron)
signal squadron_recovered(squadron)
signal squadron_destroyed(squadron)
signal squadron_state_changed(
	squadron_id: String,
	state: SquadronRuntimeState
)

const SQUADRON_SCENE := preload(
	"res://scenes/aircraft/aircraft_squadron.tscn"
)

var owner_ship: ShipUnit
var air_group_data: CarrierAirGroupData
var active_squadrons: Array[AircraftSquadron] = []
# Deprecated compatibility view. Runtime ownership lives in squadron_states.
var available_squadron_ids: Array[String] = []
var squadron_states: Dictionary = {}
var launch_cooldown_left := 0.0

var _missing_aircraft_root_warned := false
var _carrier_unavailable := false
var _battle_resolved := false
var _carrier_loss_resolved := false
var _validation_warnings: Dictionary = {}


func setup(ship: ShipUnit, data: CarrierAirGroupData) -> void:
	_disconnect_owner_health()
	_release_active_squadrons()
	owner_ship = ship
	air_group_data = data
	active_squadrons.clear()
	squadron_states.clear()
	available_squadron_ids.clear()
	launch_cooldown_left = 0.0
	_carrier_unavailable = false
	_battle_resolved = false
	_carrier_loss_resolved = false
	_validation_warnings.clear()
	if owner_ship == null or air_group_data == null:
		set_process(false)
		return
	_validate_data_once()
	if owner_ship.health != null \
			and not owner_ship.health.died.is_connected(_on_owner_ship_died):
		owner_ship.health.died.connect(_on_owner_ship_died)
	for template in air_group_data.squadron_templates:
		if not _is_valid_template(template):
			continue
		if squadron_states.has(template.id):
			_warn_validation_once(
				"duplicate_%s" % template.id,
				"Duplicate squadron template id in carrier air group: %s"
				% template.id
			)
			continue
		_create_runtime_state(template)
	_refresh_available_ids()
	set_process(not squadron_states.is_empty())


func _process(delta: float) -> void:
	launch_cooldown_left = maxf(
		0.0,
		launch_cooldown_left - maxf(delta, 0.0)
	)
	_update_rearm_states(delta)
	_prune_active_squadrons()


func is_available() -> bool:
	return owner_ship != null \
		and is_instance_valid(owner_ship) \
		and not _carrier_unavailable \
		and not _battle_resolved \
		and owner_ship.is_alive() \
		and air_group_data != null \
		and not get_launchable_squadron_ids().is_empty()


func can_launch(squadron_id: String) -> bool:
	return can_launch_squadron(squadron_id)


func can_launch_squadron(squadron_id: String) -> bool:
	if owner_ship == null or not is_instance_valid(owner_ship) \
			or _carrier_unavailable or _battle_resolved \
			or not owner_ship.is_alive() \
			or air_group_data == null \
			or launch_cooldown_left > 0.0:
		return false
	if get_active_squadron_count() \
			>= maxi(air_group_data.maximum_active_squadrons, 1):
		return false
	var state := _get_mutable_state(squadron_id)
	return state != null \
		and state.availability_state \
			== SquadronRuntimeState.AvailabilityState.READY \
		and state.available_aircraft > 0 \
		and get_squadron_data(squadron_id) != null


func launch_squadron(
		squadron_id: String,
		world_position: Vector3
) -> AircraftSquadron:
	if not can_launch_squadron(squadron_id):
		return null
	var template := get_squadron_data(squadron_id)
	var state := _get_mutable_state(squadron_id)
	var aircraft_parent := _resolve_aircraft_parent()
	if template == null or state == null or aircraft_parent == null:
		return null
	var launch_count := mini(
		maxi(template.aircraft_count, 0),
		state.available_aircraft
	)
	if launch_count <= 0:
		return null
	var squadron := SQUADRON_SCENE.instantiate() as AircraftSquadron
	if squadron == null:
		return null
	squadron.setup(
		owner_ship,
		template,
		aircraft_parent,
		launch_count
	)
	if squadron.state == AircraftSquadron.State.DESTROYED \
			or squadron.aircraft_units.is_empty():
		squadron.queue_free()
		return null
	_connect_squadron(squadron)
	active_squadrons.append(squadron)
	state.available_aircraft -= launch_count
	state.active_aircraft += launch_count
	state.availability_state = \
		SquadronRuntimeState.AvailabilityState.LAUNCHING
	state.normalize()
	_emit_state_changed(squadron_id)
	launch_cooldown_left = maxf(
		air_group_data.launch_cooldown_sec,
		0.0
	)
	squadron.launch_to(world_position)
	squadron_launched.emit(squadron)
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").squadron_launched.emit(squadron)
	return squadron


func launch_manual_squadron(
		squadron_id: String
) -> AircraftSquadron:
	if owner_ship == null or not is_instance_valid(owner_ship) \
			or not owner_ship.player_controlled \
			or not can_launch_squadron(squadron_id):
		return null
	var template := get_squadron_data(squadron_id)
	if template == null or template.aircraft_data == null:
		return null
	var forward := -owner_ship.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() \
		if forward.length_squared() > 0.0001 else Vector3.FORWARD
	var rally_position := owner_ship.global_position + forward * 550.0
	rally_position.y = owner_ship.global_position.y \
		+ template.aircraft_data.operating_altitude_m
	var squadron := launch_squadron(squadron_id, rally_position)
	if squadron == null:
		return null
	squadron.set_command_authority(
		AircraftSquadron.CommandAuthority.PLAYER
	)
	squadron.issue_player_move_command(rally_position)
	return squadron


func launch_strike_squadron(
		squadron_id: String,
		target_ship: Node3D,
		mission_data: AirMissionData = null
) -> AircraftSquadron:
	if not _is_valid_strike_target(target_ship):
		return null
	var resolved_id := _resolve_strike_squadron_id(squadron_id)
	if resolved_id.is_empty() or not can_launch_strike(resolved_id):
		return null
	var template := get_squadron_data(resolved_id)
	var active_mission := mission_data \
		if mission_data != null \
		else get_default_strike_mission(resolved_id)
	if template == null or template.aircraft_data == null \
			or active_mission == null:
		return null
	if _distance_xz(
		owner_ship.global_position,
		target_ship.global_position
	) > maxf(template.aircraft_data.combat_radius_m, 0.0):
		return null
	var squadron := launch_squadron(
		resolved_id,
		target_ship.global_position
	)
	if squadron == null:
		return null
	if not squadron.assign_strike_mission(target_ship, active_mission):
		request_squadron_return(squadron)
		return null
	return squadron


func can_launch_strike(squadron_id: String = "") -> bool:
	if squadron_id.is_empty():
		return not _resolve_strike_squadron_id("").is_empty()
	return can_launch_squadron(squadron_id) \
		and _template_has_bomb_payload(get_squadron_data(squadron_id)) \
		and get_default_strike_mission(squadron_id) != null


func launch_intercept_squadron(
		squadron_id: String,
		target_squadron: AircraftSquadron,
		mission_data: AirMissionData = null
) -> AircraftSquadron:
	var resolved_id := _resolve_fighter_squadron_id(squadron_id)
	if resolved_id.is_empty() \
			or not can_launch_intercept(resolved_id, target_squadron):
		return null
	var template := get_squadron_data(resolved_id)
	var active_mission := mission_data \
		if mission_data != null \
		else get_default_mission(resolved_id)
	if template == null or template.aircraft_data == null \
			or active_mission == null:
		return null
	var squadron := launch_squadron(
		resolved_id,
		target_squadron.formation_center
	)
	if squadron == null:
		return null
	if not squadron.assign_intercept_mission(
		target_squadron,
		active_mission,
		owner_ship.get_instance_id() \
			^ target_squadron.get_instance_id() \
			^ resolved_id.hash()
	):
		request_squadron_return(squadron)
		return null
	return squadron


func get_launchable_fighter_squadron_ids() -> Array[String]:
	var result: Array[String] = []
	for squadron_id in get_launchable_squadron_ids():
		var template := get_squadron_data(squadron_id)
		if _template_has_fighter_gun(template) \
				and get_default_mission(squadron_id) != null \
				and get_default_mission(squadron_id).mission_type \
					== AirMissionData.MissionType.INTERCEPT_AIRCRAFT:
			result.append(squadron_id)
	return result


func can_launch_intercept(
		squadron_id: String,
		target_squadron: AircraftSquadron
) -> bool:
	if not can_launch_squadron(squadron_id) \
			or not _template_has_fighter_gun(
				get_squadron_data(squadron_id)
			) \
			or not _is_valid_intercept_target(target_squadron):
		return false
	var mission := get_default_mission(squadron_id)
	if mission == null or mission.mission_type \
			!= AirMissionData.MissionType.INTERCEPT_AIRCRAFT:
		return false
	var template := get_squadron_data(squadron_id)
	return owner_ship.global_position.distance_to(
		target_squadron.formation_center
	) <= maxf(template.aircraft_data.combat_radius_m, 0.0)


func request_squadron_return(squadron: AircraftSquadron) -> void:
	if squadron == null or not is_instance_valid(squadron) \
			or not active_squadrons.has(squadron):
		return
	var squadron_id := _get_runtime_squadron_id(squadron)
	var state := _get_mutable_state(squadron_id)
	if state != null:
		state.availability_state = \
			SquadronRuntimeState.AvailabilityState.RETURNING
		_emit_state_changed(squadron_id)
	squadron.request_return()


func request_squadron_return_by_id(squadron_id: String) -> void:
	for squadron in get_active_squadrons():
		if _get_runtime_squadron_id(squadron) == squadron_id:
			request_squadron_return(squadron)


func request_all_squadrons_return() -> void:
	for squadron in get_active_squadrons():
		request_squadron_return(squadron)


func get_active_squadrons() -> Array[AircraftSquadron]:
	_prune_active_squadrons()
	return active_squadrons.duplicate()


func get_active_squadron_by_id(
		squadron_id: String
) -> AircraftSquadron:
	return _find_active_squadron(squadron_id)


func get_active_squadron_count() -> int:
	return get_active_squadrons().size()


func get_launchable_squadron_ids() -> Array[String]:
	var result: Array[String] = []
	for squadron_id_value in squadron_states.keys():
		var squadron_id := str(squadron_id_value)
		if can_launch_squadron(squadron_id):
			result.append(squadron_id)
	result.sort()
	return result


func get_launchable_strike_squadron_ids() -> Array[String]:
	var result: Array[String] = []
	for squadron_id in get_launchable_squadron_ids():
		var mission_data := get_default_mission(squadron_id)
		if mission_data != null \
				and mission_data.mission_type \
					== AirMissionData.MissionType.STRIKE_SHIP:
			result.append(squadron_id)
	return result


func resolve_squadron_id(requested_id: String) -> String:
	if not requested_id.is_empty():
		return requested_id \
			if get_squadron_data(requested_id) != null else ""
	var launchable := get_launchable_squadron_ids()
	return launchable[0] if not launchable.is_empty() else ""


func get_squadron_state(
		squadron_id: String
) -> SquadronRuntimeState:
	var state := _get_mutable_state(squadron_id)
	return state.duplicate_state() if state != null else null


func get_all_squadron_states() -> Array[SquadronRuntimeState]:
	var result: Array[SquadronRuntimeState] = []
	for squadron_id_value in squadron_states.keys():
		var state := get_squadron_state(str(squadron_id_value))
		if state != null:
			result.append(state)
	result.sort_custom(
		func(a: SquadronRuntimeState, b: SquadronRuntimeState) -> bool:
			return a.squadron_id < b.squadron_id
	)
	return result


func get_squadron_data(squadron_id: String) -> SquadronData:
	if air_group_data == null:
		return null
	for template in air_group_data.squadron_templates:
		if template != null and template.id == squadron_id:
			return template
	return null


func get_default_strike_mission(
		squadron_id: String
) -> AirMissionData:
	var mission := get_default_mission(squadron_id)
	return mission \
		if mission != null \
		and mission.mission_type \
			== AirMissionData.MissionType.STRIKE_SHIP else null


func get_default_mission(
		squadron_id: String
) -> AirMissionData:
	var template := get_squadron_data(squadron_id)
	return template.default_mission_data if template != null else null


func get_remaining_aircraft(squadron_id: String) -> int:
	var state := _get_mutable_state(squadron_id)
	return state.available_aircraft if state != null else 0


func restore_aircraft(squadron_id: String, count: int) -> int:
	var state := _get_mutable_state(squadron_id)
	if state == null or count <= 0:
		return 0
	var restored := mini(count, state.lost_aircraft)
	state.lost_aircraft -= restored
	state.available_aircraft += restored
	state.rearm_time_left = 0.0
	state.availability_state = \
		SquadronRuntimeState.AvailabilityState.READY \
		if state.available_aircraft > 0 \
		else SquadronRuntimeState.AvailabilityState.DESTROYED
	state.normalize()
	_emit_state_changed(squadron_id)
	return restored


func report_aircraft_destroyed(
		squadron: AircraftSquadron,
		_aircraft: AircraftUnit
) -> void:
	if squadron == null or not is_instance_valid(squadron):
		return
	var squadron_id := _get_runtime_squadron_id(squadron)
	var state := _get_mutable_state(squadron_id)
	if state == null:
		return
	state.active_aircraft = maxi(state.active_aircraft - 1, 0)
	state.lost_aircraft = mini(
		state.lost_aircraft + 1,
		state.total_aircraft
	)
	if state.active_aircraft <= 0:
		state.availability_state = \
			SquadronRuntimeState.AvailabilityState.DESTROYED \
			if state.available_aircraft <= 0 \
			else SquadronRuntimeState.AvailabilityState.REARMING
		state.rearm_time_left = 0.0
	state.normalize()
	_emit_state_changed(squadron_id)


func to_save_data() -> Dictionary:
	var saved_states: Dictionary = {}
	for state in get_all_squadron_states():
		saved_states[state.squadron_id] = state.to_dictionary()
	return {
		"air_group_id": air_group_data.id \
			if air_group_data != null else "",
		"squadrons": saved_states,
	}


func restore_from_save_data(data: Dictionary) -> void:
	if data.is_empty():
		return
	var saved_air_group_id := str(data.get("air_group_id", ""))
	if not saved_air_group_id.is_empty() \
			and air_group_data != null \
			and saved_air_group_id != air_group_data.id:
		_warn_validation_once(
			"restore_air_group_mismatch",
			"Saved carrier air group '%s' does not match '%s'."
			% [saved_air_group_id, air_group_data.id]
		)
		return
	var saved_states_value: Variant = data.get("squadrons", {})
	if not saved_states_value is Dictionary:
		return
	var saved_states := saved_states_value as Dictionary
	for squadron_id_value in saved_states.keys():
		var squadron_id := str(squadron_id_value)
		if not squadron_states.has(squadron_id):
			_warn_validation_once(
				"restore_unknown_%s" % squadron_id,
				"Ignoring unknown saved squadron id: %s"
				% squadron_id
			)
			continue
		var state_data: Variant = saved_states[squadron_id_value]
		if not state_data is Dictionary:
			continue
		var restored := SquadronRuntimeState.from_dictionary(state_data)
		var template := get_squadron_data(squadron_id)
		var state := _get_mutable_state(squadron_id)
		if template == null or state == null:
			continue
		restored.squadron_id = squadron_id
		restored.total_aircraft = maxi(template.aircraft_count, 0)
		# Individual aircraft positions are not saved. Airborne survivors return
		# to the hangar when a run is restored.
		restored.available_aircraft += restored.active_aircraft
		restored.active_aircraft = 0
		if restored.available_aircraft > 0:
			restored.availability_state = \
				SquadronRuntimeState.AvailabilityState.REARMING \
				if restored.rearm_time_left > 0.0 \
				else SquadronRuntimeState.AvailabilityState.READY
		else:
			restored.availability_state = \
				SquadronRuntimeState.AvailabilityState.DESTROYED
		restored.normalize()
		squadron_states[squadron_id] = restored
		_emit_state_changed(squadron_id)
	_refresh_available_ids()


func resolve_battle_end(success: bool) -> void:
	if _battle_resolved:
		return
	_battle_resolved = true
	if success:
		resolve_victory()
	else:
		resolve_carrier_loss()


func resolve_victory() -> void:
	for state_value in squadron_states.values():
		var state := state_value as SquadronRuntimeState
		if state == null:
			continue
		state.available_aircraft += state.active_aircraft
		state.active_aircraft = 0
		state.rearm_time_left = 0.0
		state.availability_state = \
			SquadronRuntimeState.AvailabilityState.READY \
			if state.available_aircraft > 0 \
			else SquadronRuntimeState.AvailabilityState.DESTROYED
		state.normalize()
		_emit_state_changed(state.squadron_id)
	_release_active_squadrons()
	_refresh_available_ids()


func resolve_carrier_loss() -> void:
	if _carrier_loss_resolved:
		return
	_carrier_loss_resolved = true
	_carrier_unavailable = true
	_battle_resolved = true
	for state_value in squadron_states.values():
		var state := state_value as SquadronRuntimeState
		if state == null:
			continue
		state.lost_aircraft = state.total_aircraft
		state.available_aircraft = 0
		state.active_aircraft = 0
		state.rearm_time_left = 0.0
		state.availability_state = \
			SquadronRuntimeState.AvailabilityState.DESTROYED
		state.normalize()
		_emit_state_changed(state.squadron_id)
	for squadron in get_active_squadrons():
		squadron.handle_carrier_unavailable(0.25)
	_refresh_available_ids()


func get_squadron_status_snapshot(squadron_id: String) -> Dictionary:
	var state := get_squadron_state(squadron_id)
	var template := get_squadron_data(squadron_id)
	if state == null or template == null:
		return {}
	var active_squadron := _find_active_squadron(squadron_id)
	var target := active_squadron.get_current_target() \
		if active_squadron != null else null
	var ammunition_per_aircraft := 0
	if template.aircraft_data != null \
			and template.aircraft_data.weapon_data != null:
		ammunition_per_aircraft = template.aircraft_data \
			.weapon_data.ammunition_per_sortie
	var active_ammunition := active_squadron \
		.get_total_remaining_ammunition() \
		if active_squadron != null else 0
	return {
		"state": state.to_dictionary(),
		"display_name": template.display_name,
		"aircraft_role": int(template.aircraft_data.role) \
			if template.aircraft_data != null else -1,
		"weapon_name": template.aircraft_data.weapon_data.display_name \
			if template.aircraft_data != null \
			and template.aircraft_data.weapon_data != null else "",
		"mission_id": active_squadron.get_current_mission_id() \
			if active_squadron != null else "",
		"mission_state": active_squadron.get_current_mission_state() \
			if active_squadron != null else -1,
		"target_name": target.name if target != null else "",
		"ammunition_per_aircraft": ammunition_per_aircraft,
		"active_ammunition": active_ammunition,
	}


func get_debug_snapshot() -> Dictionary:
	var templates: Array[Dictionary] = []
	if air_group_data != null:
		for template in air_group_data.squadron_templates:
			templates.append({
				"id": template.id if template != null else "",
				"valid": _template_validation_errors(template).is_empty(),
				"role": (
					int(template.aircraft_data.role)
					if template != null \
					and template.aircraft_data != null else -1
				),
			})
	var ready_count := 0
	var available_count := 0
	var active_count := 0
	var lost_count := 0
	var rearm_timers: Dictionary = {}
	var missions: Dictionary = {}
	for state in get_all_squadron_states():
		if state.availability_state \
				== SquadronRuntimeState.AvailabilityState.READY:
			ready_count += 1
		available_count += state.available_aircraft
		active_count += state.active_aircraft
		lost_count += state.lost_aircraft
		rearm_timers[state.squadron_id] = state.rearm_time_left
		var snapshot := get_squadron_status_snapshot(state.squadron_id)
		missions[state.squadron_id] = {
			"mission_id": snapshot.get("mission_id", ""),
			"target_name": snapshot.get("target_name", ""),
		}
	return {
		"air_group_id": air_group_data.id \
			if air_group_data != null else "",
		"template_count": air_group_data.squadron_templates.size() \
			if air_group_data != null else 0,
		"templates": templates,
		"runtime_state_ids": squadron_states.keys(),
		"active_squadron_count": get_active_squadron_count(),
		"ready_squadron_count": ready_count,
		"available_aircraft": available_count,
		"active_aircraft": active_count,
		"lost_aircraft": lost_count,
		"rearm_timers": rearm_timers,
		"launch_cooldown": launch_cooldown_left,
		"missions": missions,
	}


func debug_launch_first_squadron(
		world_position: Vector3
) -> AircraftSquadron:
	var launchable := get_launchable_squadron_ids()
	return launch_squadron(launchable[0], world_position) \
		if not launchable.is_empty() else null


func debug_recall_all_squadrons() -> void:
	request_all_squadrons_return()


func _connect_squadron(squadron: AircraftSquadron) -> void:
	if not squadron.recovery_completed.is_connected(_on_squadron_recovered):
		squadron.recovery_completed.connect(_on_squadron_recovered)
	if not squadron.squadron_lost.is_connected(_on_squadron_destroyed):
		squadron.squadron_lost.connect(_on_squadron_destroyed)
	if not squadron.aircraft_lost.is_connected(report_aircraft_destroyed):
		squadron.aircraft_lost.connect(report_aircraft_destroyed)
	if not squadron.formation_activated.is_connected(
		_on_squadron_formation_activated
	):
		squadron.formation_activated.connect(
			_on_squadron_formation_activated
		)
	if not squadron.return_requested.is_connected(
		_on_squadron_return_requested
	):
		squadron.return_requested.connect(_on_squadron_return_requested)


func _disconnect_squadron(squadron: AircraftSquadron) -> void:
	if squadron == null or not is_instance_valid(squadron):
		return
	if squadron.recovery_completed.is_connected(_on_squadron_recovered):
		squadron.recovery_completed.disconnect(_on_squadron_recovered)
	if squadron.squadron_lost.is_connected(_on_squadron_destroyed):
		squadron.squadron_lost.disconnect(_on_squadron_destroyed)
	if squadron.aircraft_lost.is_connected(report_aircraft_destroyed):
		squadron.aircraft_lost.disconnect(report_aircraft_destroyed)
	if squadron.formation_activated.is_connected(
		_on_squadron_formation_activated
	):
		squadron.formation_activated.disconnect(
			_on_squadron_formation_activated
		)
	if squadron.return_requested.is_connected(
		_on_squadron_return_requested
	):
		squadron.return_requested.disconnect(_on_squadron_return_requested)


func _on_squadron_formation_activated(
		squadron: AircraftSquadron
) -> void:
	var squadron_id := _get_runtime_squadron_id(squadron)
	var state := _get_mutable_state(squadron_id)
	if state == null:
		return
	state.availability_state = \
		SquadronRuntimeState.AvailabilityState.ACTIVE
	_emit_state_changed(squadron_id)


func _on_squadron_return_requested(
		squadron: AircraftSquadron
) -> void:
	var squadron_id := _get_runtime_squadron_id(squadron)
	var state := _get_mutable_state(squadron_id)
	if state == null or state.availability_state \
			== SquadronRuntimeState.AvailabilityState.RETURNING:
		return
	state.availability_state = \
		SquadronRuntimeState.AvailabilityState.RETURNING
	_emit_state_changed(squadron_id)


func _on_squadron_recovered(squadron: AircraftSquadron) -> void:
	if squadron == null or not is_instance_valid(squadron):
		return
	var squadron_id := _get_runtime_squadron_id(squadron)
	var state := _get_mutable_state(squadron_id)
	var template := get_squadron_data(squadron_id)
	if state != null:
		var returned_count := mini(
			squadron.get_alive_aircraft_count(),
			state.active_aircraft
		)
		state.active_aircraft -= returned_count
		state.available_aircraft += returned_count
		state.rearm_time_left = maxf(
			template.rearm_duration_sec if template != null else 0.0,
			0.0
		)
		state.availability_state = \
			SquadronRuntimeState.AvailabilityState.REARMING \
			if state.available_aircraft > 0 \
			else SquadronRuntimeState.AvailabilityState.DESTROYED
		state.normalize()
		_emit_state_changed(squadron_id)
	launch_cooldown_left = maxf(
		launch_cooldown_left,
		air_group_data.recovery_cooldown_sec \
			if air_group_data != null else 0.0
	)
	active_squadrons.erase(squadron)
	_disconnect_squadron(squadron)
	squadron_recovered.emit(squadron)
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").squadron_recovered.emit(squadron)
	squadron.release_aircraft()
	squadron.queue_free()


func _on_squadron_destroyed(squadron: AircraftSquadron) -> void:
	if squadron == null or not is_instance_valid(squadron):
		return
	var squadron_id := _get_runtime_squadron_id(squadron)
	var state := _get_mutable_state(squadron_id)
	if state != null and state.active_aircraft > 0:
		state.lost_aircraft = mini(
			state.lost_aircraft + state.active_aircraft,
			state.total_aircraft
		)
		state.active_aircraft = 0
	if state != null:
		state.rearm_time_left = 0.0
		state.availability_state = \
			SquadronRuntimeState.AvailabilityState.DESTROYED \
			if state.available_aircraft <= 0 \
			else SquadronRuntimeState.AvailabilityState.READY
		state.normalize()
		_emit_state_changed(squadron_id)
	active_squadrons.erase(squadron)
	_disconnect_squadron(squadron)
	squadron_destroyed.emit(squadron)
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").squadron_destroyed.emit(squadron)
	squadron.release_aircraft()
	squadron.queue_free()


func _update_rearm_states(delta: float) -> void:
	for state_value in squadron_states.values():
		var state := state_value as SquadronRuntimeState
		if state == null or state.availability_state \
				!= SquadronRuntimeState.AvailabilityState.REARMING:
			continue
		var previous_seconds := state.rearm_time_left
		state.rearm_time_left = maxf(
			0.0,
			state.rearm_time_left - maxf(delta, 0.0)
		)
		if state.rearm_time_left <= 0.0:
			state.availability_state = \
				SquadronRuntimeState.AvailabilityState.READY \
				if state.available_aircraft > 0 \
				else SquadronRuntimeState.AvailabilityState.DESTROYED
		var crossed_display_tick := floori(previous_seconds * 5.0) \
			!= floori(state.rearm_time_left * 5.0)
		if state.rearm_time_left <= 0.0 or crossed_display_tick:
			_emit_state_changed(state.squadron_id)


func _emit_state_changed(squadron_id: String) -> void:
	_refresh_available_ids()
	var snapshot := get_squadron_state(squadron_id)
	if snapshot != null:
		squadron_state_changed.emit(squadron_id, snapshot)


func _refresh_available_ids() -> void:
	available_squadron_ids.clear()
	for squadron_id_value in squadron_states.keys():
		var squadron_id := str(squadron_id_value)
		var state := _get_mutable_state(squadron_id)
		if state != null and state.availability_state \
				== SquadronRuntimeState.AvailabilityState.READY \
				and state.available_aircraft > 0:
			available_squadron_ids.append(squadron_id)
	available_squadron_ids.sort()


func _get_mutable_state(
		squadron_id: String
) -> SquadronRuntimeState:
	var value: Variant = squadron_states.get(squadron_id)
	return value as SquadronRuntimeState


func _get_runtime_squadron_id(squadron: AircraftSquadron) -> String:
	return squadron.squadron_data.id \
		if squadron != null \
		and squadron.squadron_data != null else ""


func _find_active_squadron(
		squadron_id: String
) -> AircraftSquadron:
	for squadron in get_active_squadrons():
		if _get_runtime_squadron_id(squadron) == squadron_id:
			return squadron
	return null


func _resolve_strike_squadron_id(requested_id: String) -> String:
	if not requested_id.is_empty():
		return requested_id \
			if can_launch_squadron(requested_id) \
			and _template_has_bomb_payload(
				get_squadron_data(requested_id)
			) else ""
	for candidate_id in get_launchable_squadron_ids():
		if _template_has_bomb_payload(get_squadron_data(candidate_id)) \
				and get_default_strike_mission(candidate_id) != null:
			return candidate_id
	return ""


func _resolve_fighter_squadron_id(requested_id: String) -> String:
	if not requested_id.is_empty():
		return requested_id \
			if can_launch_squadron(requested_id) \
			and _template_has_fighter_gun(
				get_squadron_data(requested_id)
			) else ""
	var launchable := get_launchable_fighter_squadron_ids()
	return launchable[0] if not launchable.is_empty() else ""


func _template_has_bomb_payload(template: SquadronData) -> bool:
	if template == null or template.aircraft_data == null:
		return false
	var weapon_data := template.aircraft_data.weapon_data
	return weapon_data != null \
		and weapon_data.weapon_type == AircraftWeaponData.WeaponType.BOMB \
		and weapon_data.is_valid_configuration()


func _template_has_fighter_gun(template: SquadronData) -> bool:
	if template == null or template.aircraft_data == null \
			or template.aircraft_data.role \
				!= AircraftData.AircraftRole.FIGHTER \
			or template.aircraft_data.fighter_combat_data == null:
		return false
	var weapon_data := template.aircraft_data.weapon_data
	return weapon_data != null \
		and weapon_data.weapon_type \
			== AircraftWeaponData.WeaponType.AIR_TO_AIR_GUN \
		and weapon_data.is_valid_configuration()


func _is_valid_strike_target(target_ship: Node3D) -> bool:
	if target_ship == null or not is_instance_valid(target_ship) \
			or target_ship.is_queued_for_deletion() \
			or owner_ship == null or not is_instance_valid(owner_ship):
		return false
	if target_ship.has_method(&"is_alive") \
			and not bool(target_ship.call(&"is_alive")):
		return false
	return owner_ship.is_hostile_to(target_ship)


func _is_valid_intercept_target(
		target_squadron: AircraftSquadron
) -> bool:
	return target_squadron != null \
		and is_instance_valid(target_squadron) \
		and not target_squadron.is_queued_for_deletion() \
		and target_squadron.state not in [
			AircraftSquadron.State.RETURNING,
			AircraftSquadron.State.RECOVERING,
			AircraftSquadron.State.DESTROYED,
		] \
		and target_squadron.get_alive_aircraft_count() > 0 \
		and FactionRelations.are_hostile(
			owner_ship.team,
			target_squadron.get_team()
		)


func _validate_data_once() -> void:
	if air_group_data.maximum_active_squadrons <= 0:
		_warn_validation_once(
			"maximum_active",
			"Carrier air group maximum_active_squadrons must be positive."
		)
	if air_group_data.launch_cooldown_sec < 0.0:
		_warn_validation_once(
			"launch_cooldown",
			"Carrier air group launch cooldown cannot be negative."
		)
	if air_group_data.recovery_cooldown_sec < 0.0:
		_warn_validation_once(
			"recovery_cooldown",
			"Carrier air group recovery cooldown cannot be negative."
		)
func _is_valid_template(template: SquadronData) -> bool:
	var errors := _template_validation_errors(template)
	var template_key := "null" \
		if template == null else str(template.get_instance_id())
	var template_name := "<null>" \
		if template == null or template.id.is_empty() else template.id
	for index in errors.size():
		_warn_validation_once(
			"template_%s_%d" % [template_key, index],
			"Invalid squadron template '%s': %s"
			% [template_name, errors[index]]
		)
	return errors.is_empty()


func _template_validation_errors(
		template: SquadronData
) -> PackedStringArray:
	var errors := PackedStringArray()
	if template == null:
		errors.append("template is null.")
		return errors
	errors.append_array(template.validate())
	if template.aircraft_data == null:
		return errors
	if template.aircraft_data.role == AircraftData.AircraftRole.FIGHTER:
		if template.aircraft_data.fighter_combat_data == null:
			errors.append("fighter_combat_data must be assigned.")
		else:
			for error in template.aircraft_data \
					.fighter_combat_data.validate():
				errors.append("fighter combat data: %s" % error)
	if template.aircraft_data.role \
			== AircraftData.AircraftRole.DIVE_BOMBER:
		if template.aircraft_data.dive_bomber_combat_data == null:
			errors.append("dive_bomber_combat_data must be assigned.")
		else:
			for error in template.aircraft_data \
					.dive_bomber_combat_data.validate():
				errors.append("dive bomber combat data: %s" % error)
	if template.rearm_duration_sec < 0.0:
		errors.append("rearm_duration_sec cannot be negative.")
	return errors


func _create_runtime_state(template: SquadronData) -> void:
	var state := SquadronRuntimeState.new()
	state.squadron_id = template.id
	state.total_aircraft = maxi(template.aircraft_count, 0)
	state.available_aircraft = state.total_aircraft
	state.availability_state = \
		SquadronRuntimeState.AvailabilityState.READY
	state.normalize()
	squadron_states[template.id] = state


func _warn_validation_once(key: String, message: String) -> void:
	if _validation_warnings.has(key):
		return
	_validation_warnings[key] = true
	push_warning(message)


func _resolve_aircraft_parent() -> Node:
	if get_tree() == null:
		return null
	var aircraft_root := get_tree().get_first_node_in_group(&"aircraft_root")
	if aircraft_root != null:
		return aircraft_root
	if not _missing_aircraft_root_warned:
		_missing_aircraft_root_warned = true
		push_warning(
			"Aircraft root is missing. Squadrons will use the current scene."
		)
	return get_tree().current_scene


func _prune_active_squadrons() -> void:
	for index in range(active_squadrons.size() - 1, -1, -1):
		if not is_instance_valid(active_squadrons[index]):
			active_squadrons.remove_at(index)


func _release_active_squadrons() -> void:
	for squadron in active_squadrons:
		if is_instance_valid(squadron):
			_disconnect_squadron(squadron)
			squadron.release_aircraft()
			squadron.queue_free()
	active_squadrons.clear()


func _on_owner_ship_died() -> void:
	if _carrier_unavailable:
		return
	resolve_carrier_loss()


func _disconnect_owner_health() -> void:
	if owner_ship != null and is_instance_valid(owner_ship) \
			and owner_ship.health != null \
			and owner_ship.health.died.is_connected(_on_owner_ship_died):
		owner_ship.health.died.disconnect(_on_owner_ship_died)


func _distance_xz(from: Vector3, to: Vector3) -> float:
	return Vector2(to.x - from.x, to.z - from.z).length()


func _exit_tree() -> void:
	_disconnect_owner_health()
	if _carrier_unavailable:
		for squadron in active_squadrons:
			_disconnect_squadron(squadron)
		active_squadrons.clear()
	else:
		_release_active_squadrons()

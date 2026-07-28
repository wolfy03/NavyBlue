extends Node
class_name CarrierAirGroupAI

enum LaunchBlockReason {
	NONE,
	NOT_INITIALIZED,
	CARRIER_INVALID,
	AIR_GROUP_INVALID,
	AI_DISABLED,
	PLAYER_CONTROLLED,
	NO_READY_SQUADRON,
	NO_AIRCRAFT,
	LAUNCH_COOLDOWN,
	ACTIVE_LIMIT,
	NO_MISSION,
	NO_TARGET,
	TARGET_FRIENDLY,
	TARGET_OUT_OF_RANGE,
	CARRIER_DAMAGED,
	UNSUPPORTED_MISSION,
}

@export var debug_diagnostics := true

var owner_carrier: ShipUnit
var air_group: CarrierAirGroup
var profile: CarrierAirGroupAIProfile

var _initialized := false
var _decision_timer := 0.0
var _decision_count := 0
var _candidate_count := 0
var _selected_target_ref: WeakRef
var _selected_target_score := 0.0
var _selected_target_distance_m := 0.0
var _combat_radius_m := 0.0
var _stop_launching := false
var _recall_all := false
var _last_launch_block_reason: LaunchBlockReason = \
	LaunchBlockReason.NOT_INITIALIZED


func setup(
		carrier: ShipUnit,
		next_air_group: CarrierAirGroup
) -> void:
	shutdown()
	if carrier == null or not is_instance_valid(carrier):
		_set_launch_block_reason(LaunchBlockReason.CARRIER_INVALID)
		_log_setup(false)
		return
	if next_air_group == null or not is_instance_valid(next_air_group) \
			or next_air_group.air_group_data == null:
		_set_launch_block_reason(LaunchBlockReason.AIR_GROUP_INVALID)
		_log_setup(false, carrier)
		return
	if carrier.player_controlled:
		_set_launch_block_reason(LaunchBlockReason.PLAYER_CONTROLLED)
		_log_setup(false, carrier, next_air_group)
		return
	var next_profile := next_air_group.air_group_data.ai_profile
	if next_profile == null:
		_set_launch_block_reason(LaunchBlockReason.AI_DISABLED)
		_log_setup(false, carrier, next_air_group)
		return
	owner_carrier = carrier
	air_group = next_air_group
	profile = next_profile
	_initialized = true
	_decision_timer = 0.0
	_decision_count = 0
	_candidate_count = 0
	_selected_target_ref = null
	_selected_target_score = 0.0
	_selected_target_distance_m = 0.0
	_combat_radius_m = _resolve_combat_radius()
	_stop_launching = false
	_recall_all = false
	_last_launch_block_reason = LaunchBlockReason.NONE
	if owner_carrier.health != null \
			and not owner_carrier.health.died.is_connected(
				_on_carrier_died
			):
		owner_carrier.health.died.connect(_on_carrier_died)
	process_mode = Node.PROCESS_MODE_INHERIT
	set_physics_process(true)
	_log_setup(true)


func shutdown() -> void:
	if owner_carrier != null and is_instance_valid(owner_carrier) \
			and owner_carrier.health != null \
			and owner_carrier.health.died.is_connected(
				_on_carrier_died
			):
		owner_carrier.health.died.disconnect(_on_carrier_died)
	_initialized = false
	_decision_timer = 0.0
	_candidate_count = 0
	_selected_target_ref = null
	_selected_target_score = 0.0
	_selected_target_distance_m = 0.0
	_combat_radius_m = 0.0
	_stop_launching = false
	_recall_all = false
	owner_carrier = null
	air_group = null
	profile = null
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not _initialized:
		return
	if owner_carrier == null or not is_instance_valid(owner_carrier) \
			or not owner_carrier.is_alive():
		_set_launch_block_reason(LaunchBlockReason.CARRIER_INVALID)
		shutdown()
		return
	if air_group == null or not is_instance_valid(air_group) \
			or air_group.air_group_data == null:
		_set_launch_block_reason(LaunchBlockReason.AIR_GROUP_INVALID)
		shutdown()
		return
	update_ai(delta)


func update_ai(delta: float) -> void:
	if not _initialized:
		_set_launch_block_reason(LaunchBlockReason.NOT_INITIALIZED)
		return
	if owner_carrier.player_controlled:
		_set_launch_block_reason(LaunchBlockReason.PLAYER_CONTROLLED)
		shutdown()
		return
	_decision_timer -= maxf(delta, 0.0)
	if _decision_timer > 0.0:
		return
	_decision_timer = _get_decision_interval()
	_decision_count += 1
	_stop_launching = should_stop_launching()
	_recall_all = should_recall_all()
	if _recall_all:
		_set_launch_block_reason(LaunchBlockReason.CARRIER_DAMAGED)
		air_group.request_all_squadrons_return()
		_log_recall()
		return
	if _stop_launching:
		_set_launch_block_reason(LaunchBlockReason.CARRIER_DAMAGED)
		return
	var readiness_reason := _get_air_group_readiness_reason()
	if readiness_reason != LaunchBlockReason.NONE:
		_set_launch_block_reason(readiness_reason)
		return
	var launchable_ids := air_group.get_launchable_squadron_ids()
	if launchable_ids.is_empty():
		_set_launch_block_reason(
			LaunchBlockReason.NO_READY_SQUADRON
		)
		return
	var squadron_id := launchable_ids[0]
	var mission_data := air_group.get_default_strike_mission(
		squadron_id
	)
	if mission_data == null:
		_set_launch_block_reason(LaunchBlockReason.NO_MISSION)
		return
	if mission_data.mission_type \
			!= AirMissionData.MissionType.STRIKE_SHIP:
		_set_launch_block_reason(
			LaunchBlockReason.UNSUPPORTED_MISSION
		)
		return
	_combat_radius_m = _get_squadron_combat_radius(squadron_id)
	var target := select_strike_target()
	if target == null:
		_set_launch_block_reason(LaunchBlockReason.NO_TARGET)
		return
	var squadron := air_group.launch_strike_squadron(
		squadron_id,
		target,
		mission_data
	)
	if squadron == null:
		_set_launch_block_reason(
			_resolve_failed_launch_reason(squadron_id, target)
		)
		return
	_set_launch_block_reason(LaunchBlockReason.NONE)
	_log_launch(squadron_id, target)


func select_strike_target() -> ShipUnit:
	_candidate_count = 0
	_selected_target_ref = null
	_selected_target_score = -INF
	_selected_target_distance_m = 0.0
	if not _initialized or get_tree() == null:
		return null
	var best_target: ShipUnit
	for value in get_tree().get_nodes_in_group(&"ships"):
		var candidate := value as ShipUnit
		if not _is_valid_strike_target(candidate):
			continue
		_candidate_count += 1
		var score := _score_target(candidate)
		if best_target == null \
				or score > _selected_target_score \
				or (
					is_equal_approx(score, _selected_target_score)
					and candidate.get_instance_id()
						< best_target.get_instance_id()
				):
			best_target = candidate
			_selected_target_score = score
	if best_target != null:
		_selected_target_ref = weakref(best_target)
		_selected_target_distance_m = _distance_xz(
			owner_carrier.global_position,
			best_target.global_position
		)
	else:
		_selected_target_score = 0.0
	return best_target


func should_stop_launching() -> bool:
	return _get_health_ratio() <= profile.launch_health_threshold \
		if profile != null else true


func should_recall_all() -> bool:
	return _get_health_ratio() <= profile.recall_health_threshold \
		if profile != null else true


func get_last_launch_block_reason() -> int:
	return int(_last_launch_block_reason)


func get_last_launch_block_reason_name() -> String:
	return LaunchBlockReason.keys()[int(_last_launch_block_reason)]


func get_debug_snapshot() -> Dictionary:
	var selected_target := _get_selected_target()
	var launchable_ids: Array[String] = []
	if air_group != null and is_instance_valid(air_group):
		launchable_ids = air_group.get_launchable_squadron_ids()
	return {
		"initialized": _initialized,
		"process_mode": process_mode,
		"physics_processing": is_physics_processing(),
		"carrier_name": owner_carrier.name \
			if owner_carrier != null \
			and is_instance_valid(owner_carrier) else "",
		"carrier_team": String(owner_carrier.team) \
			if owner_carrier != null \
			and is_instance_valid(owner_carrier) else "",
		"player_controlled": owner_carrier.player_controlled \
			if owner_carrier != null \
			and is_instance_valid(owner_carrier) else false,
		"decision_timer": _decision_timer,
		"decision_count": _decision_count,
		"candidate_count": _candidate_count,
		"selected_target": selected_target.name \
			if selected_target != null else "",
		"selected_target_distance_m":
			_selected_target_distance_m,
		"target_score": _selected_target_score,
		"combat_radius_m": _combat_radius_m,
		"launchable_squadron_ids": launchable_ids,
		"active_squadron_count":
			air_group.get_active_squadron_count() \
			if air_group != null \
			and is_instance_valid(air_group) else 0,
		"stop_launching": _stop_launching,
		"recall_all": _recall_all,
		"last_launch_block_reason":
			get_last_launch_block_reason_name(),
	}


func _get_air_group_readiness_reason() -> LaunchBlockReason:
	if air_group == null or not is_instance_valid(air_group) \
			or air_group.air_group_data == null:
		return LaunchBlockReason.AIR_GROUP_INVALID
	if air_group.launch_cooldown_left > 0.0:
		return LaunchBlockReason.LAUNCH_COOLDOWN
	if air_group.get_active_squadron_count() >= maxi(
		air_group.air_group_data.maximum_active_squadrons,
		1
	):
		return LaunchBlockReason.ACTIVE_LIMIT
	var has_aircraft := false
	var has_ready_state := false
	for state in air_group.get_all_squadron_states():
		has_aircraft = has_aircraft or state.available_aircraft > 0
		has_ready_state = has_ready_state or (
			state.available_aircraft > 0
			and state.availability_state \
				== SquadronRuntimeState.AvailabilityState.READY
		)
	if not has_aircraft:
		return LaunchBlockReason.NO_AIRCRAFT
	if not has_ready_state:
		return LaunchBlockReason.NO_READY_SQUADRON
	return LaunchBlockReason.NONE


func _resolve_failed_launch_reason(
		squadron_id: String,
		target: ShipUnit
) -> LaunchBlockReason:
	var readiness_reason := _get_air_group_readiness_reason()
	if readiness_reason != LaunchBlockReason.NONE:
		return readiness_reason
	if target == null or not is_instance_valid(target):
		return LaunchBlockReason.NO_TARGET
	if not owner_carrier.is_hostile_to(target):
		return LaunchBlockReason.TARGET_FRIENDLY
	var radius := _get_squadron_combat_radius(squadron_id)
	if _distance_xz(
		owner_carrier.global_position,
		target.global_position
	) > radius:
		return LaunchBlockReason.TARGET_OUT_OF_RANGE
	if air_group.get_default_strike_mission(squadron_id) == null:
		return LaunchBlockReason.NO_MISSION
	return LaunchBlockReason.NO_READY_SQUADRON


func _is_valid_strike_target(candidate: ShipUnit) -> bool:
	if candidate == null or not is_instance_valid(candidate) \
			or candidate == owner_carrier \
			or candidate.is_queued_for_deletion() \
			or not candidate.is_alive() \
			or candidate.ship_data == null \
			or not owner_carrier.is_hostile_to(candidate):
		return false
	var distance_squared := owner_carrier.global_position \
		.distance_squared_to(candidate.global_position)
	var radius := maxf(_combat_radius_m, 0.0)
	if radius <= 0.0 or distance_squared > radius * radius:
		return false
	var bounds := get_tree().get_first_node_in_group(
		&"battlefield_bounds"
	) as BattlefieldBounds
	return bounds == null or bounds.is_inside_bounds(
		candidate.global_position
	)


func _score_target(candidate: ShipUnit) -> float:
	var radius := maxf(_combat_radius_m, 1.0)
	var distance := _distance_xz(
		owner_carrier.global_position,
		candidate.global_position
	)
	var distance_score := (
		1.0 - clampf(distance / radius, 0.0, 1.0)
	) * 100.0 * profile.distance_weight
	var health_ratio := candidate.health.current_health \
		/ maxf(candidate.health.max_health, 1.0)
	var class_bonus := float(profile.ship_class_weights.get(
		int(candidate.ship_data.ship_class),
		0.0
	))
	var score := distance_score \
		+ (1.0 - health_ratio) * profile.damaged_target_bonus \
		+ candidate.ship_data.strategic_value \
			* profile.strategic_value_weight \
		+ class_bonus
	if candidate.combat != null \
			and candidate.combat.target == owner_carrier:
		score += profile.threat_to_carrier_weight
	score -= _count_squadrons_targeting(candidate) \
		* profile.duplicate_target_penalty
	return score


func _count_squadrons_targeting(target: ShipUnit) -> int:
	var count := 0
	for squadron in air_group.get_active_squadrons():
		if squadron.get_current_target() == target:
			count += 1
	return count


func _resolve_combat_radius() -> float:
	if air_group == null or air_group.air_group_data == null:
		return 0.0
	var maximum_radius := 0.0
	for template in air_group.air_group_data.squadron_templates:
		if template != null and template.aircraft_data != null:
			maximum_radius = maxf(
				maximum_radius,
				template.aircraft_data.combat_radius_m
			)
	return maximum_radius


func _get_squadron_combat_radius(squadron_id: String) -> float:
	var data := air_group.get_squadron_data(squadron_id) \
		if air_group != null else null
	return maxf(data.aircraft_data.combat_radius_m, 0.0) \
		if data != null and data.aircraft_data != null else 0.0


func _get_decision_interval() -> float:
	return maxf(profile.decision_interval_sec, 0.1) \
		if profile != null else 1.5


func _get_health_ratio() -> float:
	if owner_carrier == null or not is_instance_valid(owner_carrier) \
			or owner_carrier.health == null:
		return 0.0
	return owner_carrier.health.current_health \
		/ maxf(owner_carrier.health.max_health, 1.0)


func _get_selected_target() -> ShipUnit:
	if _selected_target_ref == null:
		return null
	var target := _selected_target_ref.get_ref() as ShipUnit
	return target if target != null and is_instance_valid(target) else null


func _set_launch_block_reason(reason: LaunchBlockReason) -> void:
	if _last_launch_block_reason == reason:
		return
	_last_launch_block_reason = reason
	if debug_diagnostics and reason != LaunchBlockReason.NONE:
		print_debug(
			"Carrier strike blocked carrier=%s reason=%s"
			% [
				owner_carrier.name \
					if owner_carrier != null \
					and is_instance_valid(owner_carrier) else "",
				get_last_launch_block_reason_name(),
			]
		)


func _log_setup(
		success: bool,
		carrier: ShipUnit = null,
		next_air_group: CarrierAirGroup = null
) -> void:
	if not debug_diagnostics:
		return
	var active_carrier := owner_carrier \
		if owner_carrier != null else carrier
	var active_group := air_group if air_group != null else next_air_group
	print_debug(
		(
			"CarrierAirGroupAI setup success=%s carrier=%s team=%s "
			+ "player_controlled=%s air_group=%s "
			+ "physics_processing=%s"
		) % [
			success,
			active_carrier.name \
				if active_carrier != null \
				and is_instance_valid(active_carrier) else "",
			String(active_carrier.team) \
				if active_carrier != null \
				and is_instance_valid(active_carrier) else "",
			active_carrier.player_controlled \
				if active_carrier != null \
				and is_instance_valid(active_carrier) else false,
			active_group.air_group_data.id \
				if active_group != null \
				and is_instance_valid(active_group) \
				and active_group.air_group_data != null else "",
			is_physics_processing(),
		]
	)


func _log_launch(squadron_id: String, target: ShipUnit) -> void:
	if debug_diagnostics:
		print_debug(
			"Carrier strike launched carrier=%s squadron=%s target=%s"
			% [owner_carrier.name, squadron_id, target.name]
		)


func _log_recall() -> void:
	if debug_diagnostics:
		print_debug(
			"Carrier squadrons recalled carrier=%s reason=CARRIER_DAMAGED"
			% owner_carrier.name
		)


func _on_carrier_died() -> void:
	if not _initialized:
		return
	_set_launch_block_reason(LaunchBlockReason.CARRIER_INVALID)
	shutdown()
	process_mode = Node.PROCESS_MODE_DISABLED


static func _distance_xz(from: Vector3, to: Vector3) -> float:
	return Vector2(to.x - from.x, to.z - from.z).length()

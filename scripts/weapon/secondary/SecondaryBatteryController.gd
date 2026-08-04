extends RefCounted
class_name SecondaryBatteryController
## Automatic secondary battery.
##
## Secondaries do not fire as a battery salvo: the whole battery shares one
## target and one weapon-group lead solution, but every mount fires the moment
## it is individually ready (reloaded, traversed, in arc, with a safe line of
## fire). A slow gun never holds up a fast one, and each mount carries its own
## aim bias and fall-of-shot correction.

const DEFAULT_PROFILE: SecondaryBatteryProfile = preload(
	"res://resources/settings/default_secondary_battery_profile.tres"
)
const PLAYER_AUTO_DIFFICULTY: AIGunneryDifficultyProfile = preload(
	"res://resources/ai_difficulty/gunnery_normal.tres"
)
const SECONDARY_ACCURACY: GunneryWeaponAccuracyProfile = preload(
	"res://resources/weapon_accuracy/secondary_gun_accuracy.tres"
)

var owner_ship: ShipUnit
var ship_combat: ShipCombat
var profile: SecondaryBatteryProfile
var secondary_mounts: Array[CannonMount] = []
var target_selector := SecondaryBatteryTargetSelector.new()
var fire_control := ShipGunneryFireControl.new()
var line_of_fire := WeaponLineOfFireEvaluator.new()

var current_target_ref: WeakRef
var current_target_instance_id := 0
var current_target_score := 0.0
var scan_elapsed_sec := 0.0
var target_switch_elapsed_sec := 0.0
var _candidate_provider := Callable()
var _debug_snapshot := SecondaryBatteryDebugSnapshot.new()
var _configured := false
## mount_instance_id -> SecondaryMountFireControlState
var _mount_fire_control_states: Dictionary = {}
var _elapsed_battle_time_sec := 0.0
var _counters: BattlePerformanceCounters
var _debug_settings: BattleDebugSettings
## Round-robin cursor for budgeted mount evaluation. Wrapped against the live
## mount count every frame so pruning a mount cannot leave it out of range.
var _next_mount_evaluation_index := 0


func setup(
		next_owner_ship: ShipUnit,
		next_ship_combat: ShipCombat,
		next_mounts: Array[CannonMount],
		next_profile: SecondaryBatteryProfile,
		candidate_provider: Callable = Callable()
) -> bool:
	shutdown()
	if next_owner_ship == null or not is_instance_valid(next_owner_ship) \
			or next_ship_combat == null:
		return false
	owner_ship = next_owner_ship
	ship_combat = next_ship_combat
	profile = next_profile \
		if next_profile != null and next_profile.validate().is_empty() \
		else DEFAULT_PROFILE
	secondary_mounts.assign(next_mounts)
	_candidate_provider = candidate_provider
	var services := owner_ship.battle_services
	_counters = services.performance_counters if services != null else null
	_debug_settings = services.debug_settings if services != null else null
	var difficulty := PLAYER_AUTO_DIFFICULTY \
		if owner_ship.player_controlled \
		else (services.ai_gunnery_difficulty if services != null else null)
	var crew := owner_ship.ship_data.secondary_gunnery_crew_stats \
		if owner_ship.ship_data != null else null
	if crew == null and owner_ship.ship_data != null:
		crew = owner_ship.ship_data.gunnery_crew_stats
	fire_control.configure(
		difficulty,
		crew,
		services.debug_settings if services != null else null,
		SECONDARY_ACCURACY
	)
	fire_control.set_fire_mode(
		ShipGunneryFireControl.FireMode.INDEPENDENT_MOUNT
	)
	fire_control.performance_counters = _counters
	_initialize_mount_fire_control_states()
	scan_elapsed_sec = maxf(profile.scan_interval_sec, 0.01)
	_configured = not secondary_mounts.is_empty()
	_refresh_debug_snapshot(0, 0)
	return _configured


func shutdown() -> void:
	_clear_target(&"shutdown")
	fire_control.clear()
	_mount_fire_control_states.clear()
	secondary_mounts.clear()
	_candidate_provider = Callable()
	owner_ship = null
	ship_combat = null
	profile = null
	_configured = false
	_refresh_debug_snapshot(0, 0)


func set_candidate_provider(provider: Callable) -> void:
	_candidate_provider = provider
	scan_elapsed_sec = maxf(profile.scan_interval_sec, 0.01) \
		if profile != null else 0.0


func update(delta: float) -> void:
	if not _configured or owner_ship == null \
			or not is_instance_valid(owner_ship) \
			or not owner_ship.is_alive():
		_clear_target(&"owner_unavailable")
		return
	_prune_invalid_mounts()
	if secondary_mounts.is_empty():
		_clear_target(&"all_mounts_lost")
		_configured = false
		return
	if profile == null or not profile.enabled \
			or (_debug_settings != null
				and _debug_settings.disable_secondary_battery_runtime):
		# Diagnostic isolation: the whole secondary runtime stops here while
		# main batteries and every other system keep running.
		_clear_target(&"disabled")
		_update_idle_mounts(delta)
		return
	if _counters != null:
		_counters.add_secondary_structure(1, secondary_mounts.size())
	target_switch_elapsed_sec += maxf(delta, 0.0)
	scan_elapsed_sec += maxf(delta, 0.0)
	_elapsed_battle_time_sec += maxf(delta, 0.0)
	var current_target := get_current_target()
	# One engagement scan per update. can_engage_world_point runs a ballistic
	# pitch solve per mount, so counting twice used to cost an extra
	# mount-count worth of sqrt/atan work every frame.
	var engaging := count_engaging_mounts(current_target)
	if not _is_valid_target(current_target) \
			or engaging < maxi(profile.minimum_engaging_mount_count, 1):
		_clear_target(&"target_unavailable")
		current_target = null
		engaging = 0
		scan_elapsed_sec = maxf(profile.scan_interval_sec, 0.01)
	if scan_elapsed_sec >= maxf(profile.scan_interval_sec, 0.01):
		_scan_for_target()
		scan_elapsed_sec = 0.0
		var rescanned_target := get_current_target()
		if rescanned_target != current_target:
			current_target = rescanned_target
			engaging = count_engaging_mounts(current_target)
	if current_target == null:
		_update_idle_mounts(delta)
		_refresh_debug_snapshot(0, 0)
		return
	# One shared lead solve per weapon group, then every mount acts alone. No
	# begin_salvo_for_mounts here: that is the main-battery salvo path.
	_update_shared_lead_solutions(current_target)
	var fired := 0
	var ready := 0
	var budget := _resolve_mount_evaluation_budget(delta)
	if _next_mount_evaluation_index >= secondary_mounts.size():
		_next_mount_evaluation_index = 0
	for _slot in budget:
		var mount := secondary_mounts[_next_mount_evaluation_index]
		_next_mount_evaluation_index = (
			_next_mount_evaluation_index + 1
		) % secondary_mounts.size()
		var outcome := _update_independent_mount(mount, current_target)
		if outcome.was_ready:
			ready += 1
		if outcome.did_fire:
			fired += 1
	_refresh_debug_snapshot(engaging, fired, ready)


## How many mounts get the expensive fire decision this frame.
##
## Unbudgeted (the default) evaluates every mount, preserving the original
## behaviour exactly. Budgeted mode derives the count from the configured
## maximum delay, so a ready gun still fires within
## maximum_mount_evaluation_delay_sec no matter how many mounts the ship has.
## Turret traverse and elevation keep interpolating every frame either way;
## only the fire decision is spread.
func _resolve_mount_evaluation_budget(delta: float) -> int:
	var mount_count := secondary_mounts.size()
	if _debug_settings == null \
			or not _debug_settings.use_budgeted_secondary_mount_updates:
		return mount_count
	var maximum_delay := maxf(
		profile.maximum_mount_evaluation_delay_sec,
		0.016
	)
	var required := ceili(
		float(mount_count) * maxf(delta, 0.0001) / maximum_delay
	)
	return clampi(
		required,
		mini(profile.minimum_mount_evaluation_budget, mount_count),
		mini(profile.maximum_mount_evaluation_budget, mount_count)
	)


class MountUpdateOutcome:
	extends RefCounted
	var was_ready := false
	var did_fire := false


## Drives one mount end to end. Nothing here consults any other mount, so a
## reloading or still-traversing gun cannot delay a ready one.
func _update_independent_mount(
		mount: CannonMount,
		target: ShipUnit
) -> MountUpdateOutcome:
	var outcome := MountUpdateOutcome.new()
	if mount == null or not is_instance_valid(mount):
		return outcome
	if not mount.is_operational():
		return outcome
	if _counters != null:
		_counters.count_secondary_mount_evaluated()
	if not fire_control.has_solution_for_mount(mount):
		mount.clear_aim()
		_set_mount_failure(mount, &"no_ballistic_solution")
		return outcome
	var state := _get_or_create_mount_state(mount)
	var lead_point := fire_control.get_lead_point_for_mount(
		mount,
		target.global_position
	)
	if not mount.can_engage_world_point(lead_point):
		mount.clear_aim()
		state.last_failure_reason = &"out_of_arc_or_range"
		return outcome
	var accuracy := fire_control.resolve_independent_mount_accuracy(
		mount,
		state.tracking_state,
		state.fire_sequence_index
	)
	if accuracy == null or not accuracy.success:
		state.last_failure_reason = &"accuracy_solution_failed"
		return outcome
	var actual_aim := accuracy.actual_aim_point
	mount.aim_at(actual_aim)
	fire_control.bind_mount_provider(mount)
	state.last_aim_point = actual_aim
	if mount.get_fire_readiness_at(actual_aim) \
			!= WeaponFireReadiness.State.READY:
		state.last_failure_reason = &"not_ready"
		return outcome
	outcome.was_ready = true
	if _counters != null:
		_counters.count_secondary_mount_ready()
	# The ray query runs only when the cached verdict has expired or the aim
	# point moved far enough to invalidate it.
	if not _is_line_of_fire_safe(mount, target, actual_aim, state):
		state.last_failure_reason = state.last_line_of_fire_reason
		_debug_snapshot.last_fire_control_failure = \
			state.last_line_of_fire_reason
		return outcome
	if profile.hold_fire:
		state.last_failure_reason = &"hold_fire"
		return outcome
	if not mount.fire():
		state.last_failure_reason = &"fire_rejected"
		return outcome
	# Only a shot advances this mount's sequence, so its next solution draws a
	# fresh seed while every other mount keeps its own.
	state.fire_sequence_index += 1
	state.shots_fired += 1
	state.last_fire_time_sec = _elapsed_battle_time_sec
	state.last_failure_reason = &""
	fire_control.advance_mount_correction(state.tracking_state)
	outcome.did_fire = true
	if _counters != null:
		_counters.count_secondary_mount_fired()
	return outcome


## Cached line-of-fire test. A mount that is ready every frame while its own
## reload cycles would otherwise re-run a physics ray query each frame; the
## verdict is stable over that interval unless the aim point really moved.
func _is_line_of_fire_safe(
		mount: CannonMount,
		target: ShipUnit,
		aim_point: Vector3,
		state: SecondaryMountFireControlState
) -> bool:
	var interval := maxf(profile.line_of_fire_cache_interval_sec, 0.0)
	var recheck_distance := maxf(
		profile.line_of_fire_recheck_distance_m,
		0.0
	)
	var age := _elapsed_battle_time_sec - state.last_line_of_fire_check_time_sec
	if state.has_line_of_fire_result \
			and age < interval \
			and state.last_line_of_fire_aim_point.distance_to(aim_point) \
				<= recheck_distance:
		return state.last_line_of_fire_result
	if _counters != null:
		_counters.count_line_of_fire_check()
	var safety := line_of_fire.evaluate(mount, target, aim_point)
	state.has_line_of_fire_result = true
	state.last_line_of_fire_result = safety.safe
	state.last_line_of_fire_reason = safety.blocked_reason
	state.last_line_of_fire_check_time_sec = _elapsed_battle_time_sec
	state.last_line_of_fire_aim_point = aim_point
	return safety.safe


func _get_or_create_mount_state(
		mount: CannonMount
) -> SecondaryMountFireControlState:
	var mount_id := mount.get_instance_id()
	var existing := _mount_fire_control_states.get(mount_id) \
		as SecondaryMountFireControlState
	if existing != null:
		if not existing.is_bound_to_weapon(mount):
			existing.reset_for_weapon(mount)
			var rebound_target := get_current_target()
			if rebound_target != null:
				existing.reset_for_target(
					rebound_target,
					rebound_target.get_instance_id()
				)
		return existing
	var state := SecondaryMountFireControlState.create(mount)
	var target := get_current_target()
	if target != null:
		state.reset_for_target(target, target.get_instance_id())
	_mount_fire_control_states[mount_id] = state
	return state


func _initialize_mount_fire_control_states() -> void:
	_mount_fire_control_states.clear()
	for mount in secondary_mounts:
		if mount == null or not is_instance_valid(mount):
			continue
		var state := SecondaryMountFireControlState.create(mount)
		_mount_fire_control_states[mount.get_instance_id()] = state


func _set_mount_failure(mount: CannonMount, reason: StringName) -> void:
	var state := _mount_fire_control_states.get(mount.get_instance_id()) \
		as SecondaryMountFireControlState
	if state != null:
		state.last_failure_reason = reason


func get_mount_fire_control_state(
		mount: CannonMount
) -> SecondaryMountFireControlState:
	if mount == null or not is_instance_valid(mount):
		return null
	return _mount_fire_control_states.get(mount.get_instance_id()) \
		as SecondaryMountFireControlState


func count_engaging_mounts(target_ship: ShipUnit) -> int:
	if not _is_valid_target(target_ship):
		return 0
	var count := 0
	for mount in secondary_mounts:
		if mount != null and is_instance_valid(mount) \
				and mount.can_engage_world_point(target_ship.global_position):
			count += 1
	return count


func get_current_target() -> ShipUnit:
	if current_target_ref == null:
		return null
	var value: Variant = current_target_ref.get_ref()
	if value == null or not is_instance_valid(value):
		return null
	var target := value as ShipUnit
	return target if target != null \
		and target.get_instance_id() == current_target_instance_id else null


func get_debug_snapshot() -> SecondaryBatteryDebugSnapshot:
	return _debug_snapshot


func is_configured() -> bool:
	return _configured


func _scan_for_target() -> void:
	var candidates := _get_candidates()
	var main_target := ship_combat.get_main_target() \
		if ship_combat != null else null
	var result := target_selector.select_target(
		owner_ship,
		secondary_mounts,
		candidates,
		profile,
		main_target
	)
	_debug_snapshot.candidate_count = result.candidate_count
	var current_target := get_current_target()
	if result.target == null:
		if current_target == null:
			return
		_clear_target(&"no_candidate")
		return
	if current_target == null:
		_set_target(result.target, result.score, &"acquired")
		return
	var current_context := target_selector.evaluate_candidate(
		owner_ship,
		secondary_mounts,
		current_target,
		profile,
		main_target
	)
	current_target_score = current_context.total_score
	if result.target == current_target:
		return
	if target_switch_elapsed_sec < maxf(profile.target_switch_cooldown_sec, 0.0):
		return
	if result.score < current_target_score \
			* maxf(profile.target_switch_score_ratio, 1.0):
		return
	_set_target(result.target, result.score, &"better_candidate")


func _set_target(
		target_ship: ShipUnit,
		score: float,
		reason: StringName
) -> void:
	if not _is_valid_target(target_ship):
		return
	if get_current_target() == target_ship:
		current_target_score = score
		return
	_clear_target(&"target_changed")
	current_target_ref = weakref(target_ship)
	current_target_instance_id = target_ship.get_instance_id()
	current_target_score = score
	target_switch_elapsed_sec = 0.0
	_debug_snapshot.last_target_change_reason = reason
	fire_control.begin_tracking_target(target_ship)
	# Aim correction accumulated against the previous ship is meaningless now.
	# fire_sequence_index deliberately keeps counting so seeds stay unique.
	for state_value: Variant in _mount_fire_control_states.values():
		var state := state_value as SecondaryMountFireControlState
		if state != null:
			state.reset_for_target(
				target_ship,
				target_ship.get_instance_id()
			)


func _clear_target(reason: StringName) -> void:
	var had_target := current_target_ref != null or current_target_instance_id != 0
	fire_control.release_provider_bindings()
	fire_control.clear_tracking_target(reason)
	current_target_ref = null
	current_target_instance_id = 0
	current_target_score = 0.0
	if had_target:
		_debug_snapshot.last_target_change_reason = reason
	for mount in secondary_mounts:
		if mount != null and is_instance_valid(mount) \
				and mount.shell_deviation_provider == fire_control:
			mount.shell_deviation_provider = null


## Refreshes the observation and the per-weapon-group ballistic lead once for
## the whole battery. Mounts sharing a WeaponData (and therefore the same
## muzzle velocity, gravity scale and accuracy profile) reuse one solve; the
## expensive NavalGunLeadResolver never runs per mount.
func _update_shared_lead_solutions(target_ship: ShipUnit) -> void:
	fire_control.update(owner_ship, target_ship, _as_weapon_mounts())


func _update_idle_mounts(delta: float) -> void:
	if profile == null \
			or profile.idle_behavior == SecondaryBatteryProfile.IdleBehavior.HOLD_LAST_AIM:
		return
	for mount in secondary_mounts:
		if mount == null or not is_instance_valid(mount):
			continue
		mount.clear_aim()
		mount.return_to_rest(delta)


func _prune_invalid_mounts() -> void:
	var live_mount_ids: Dictionary = {}
	for index in range(secondary_mounts.size() - 1, -1, -1):
		var value: Variant = secondary_mounts[index]
		if value == null or not is_instance_valid(value):
			secondary_mounts.remove_at(index)
			continue
		live_mount_ids[(value as CannonMount).get_instance_id()] = true
	# A destroyed mount must not leave its fire-control state behind.
	for mount_id_value: Variant in _mount_fire_control_states.keys().duplicate():
		var mount_id := int(mount_id_value)
		if live_mount_ids.has(mount_id):
			continue
		_mount_fire_control_states.erase(mount_id)
		fire_control.release_mount_state(mount_id)


func _get_candidates() -> Array:
	if not _candidate_provider.is_valid():
		return []
	var values: Variant = _candidate_provider.call()
	return values if values is Array else []


func _is_valid_target(target_ship: ShipUnit) -> bool:
	return target_ship != null \
		and is_instance_valid(target_ship) \
		and owner_ship != null \
		and is_instance_valid(owner_ship) \
		and target_ship.is_valid_attack_target_for(owner_ship.team)


func _as_weapon_mounts() -> Array[WeaponMount]:
	var result: Array[WeaponMount] = []
	for mount in secondary_mounts:
		if mount != null and is_instance_valid(mount):
			result.append(mount)
	return result


func _refresh_debug_snapshot(
		engaging: int,
		firing: int,
		ready: int = 0
) -> void:
	_debug_snapshot.fire_coordination_mode = int(
		profile.get_effective_fire_coordination_mode()
	) if profile != null else int(
		SecondaryBatteryProfile.FireCoordinationMode.INDEPENDENT
	)
	_debug_snapshot.independently_ready_mount_count = ready
	_debug_snapshot.independently_fired_mount_count = firing
	_debug_snapshot.shared_salvo_active = false
	_debug_snapshot.mount_fire_sequence_indices.clear()
	_debug_snapshot.mount_shots_fired.clear()
	_debug_snapshot.mount_last_failure_reasons.clear()
	for mount_id_value: Variant in _mount_fire_control_states:
		var state := _mount_fire_control_states[mount_id_value] \
			as SecondaryMountFireControlState
		if state == null:
			continue
		var mount_id := int(mount_id_value)
		_debug_snapshot.mount_fire_sequence_indices[mount_id] = \
			state.fire_sequence_index
		_debug_snapshot.mount_shots_fired[mount_id] = state.shots_fired
		_debug_snapshot.mount_last_failure_reasons[mount_id] = \
			state.last_failure_reason
	_refresh_battery_debug_snapshot(engaging, firing)


func _refresh_battery_debug_snapshot(engaging: int, firing: int) -> void:
	_debug_snapshot.enabled = _configured and profile != null and profile.enabled
	_debug_snapshot.hold_fire = profile.hold_fire if profile != null else false
	_debug_snapshot.current_target_instance_id = current_target_instance_id
	_debug_snapshot.current_target_score = current_target_score
	_debug_snapshot.total_mount_count = secondary_mounts.size()
	_debug_snapshot.valid_mount_count = secondary_mounts.size()
	_debug_snapshot.engaging_mount_count = engaging
	_debug_snapshot.firing_mount_count = firing
	_debug_snapshot.maximum_range_m = get_max_secondary_range_m()
	_debug_snapshot.scan_elapsed_sec = scan_elapsed_sec
	_debug_snapshot.target_switch_elapsed_sec = target_switch_elapsed_sec
	var snapshots := fire_control.get_debug_snapshots()
	if not snapshots.is_empty():
		_debug_snapshot.predicted_impact_position = snapshots[0].ideal_aim_point
		_debug_snapshot.actual_aim_position = snapshots[0].actual_aim_point
		_debug_snapshot.last_fire_control_failure = snapshots[0].failure_reason


func get_max_secondary_range_m() -> float:
	var result := 0.0
	for mount in secondary_mounts:
		if mount != null and is_instance_valid(mount):
			result = maxf(result, mount.get_range_m())
	return result

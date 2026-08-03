extends RefCounted
class_name ShipGunneryFireControl
## Per-ship AI gunnery fire control.
##
## Owns the observation -> lead -> accuracy pipeline for every cannon group of
## one AI ship. ShipCombat drives it once per physics frame and reads back one
## stable aim point per weapon group; CannonMount asks it for per-shell launch
## deviations at fire time. Player-controlled ships never create this object.
##
## Cadence rules (anti-jitter):
##   lead solution  -> refreshed on a fixed frame interval (or forced when the
##                     target moves beyond the repath threshold)
##   salvo bias     -> frozen until the current salvo has actually fired
##   dispersion     -> drawn once per launched shell

const DEFAULT_DIFFICULTY: AIGunneryDifficultyProfile = preload(
	"res://resources/ai_difficulty/gunnery_normal.tres"
)


var difficulty_profile: AIGunneryDifficultyProfile
var crew_stats: GunneryCrewStats
var debug_settings: BattleDebugSettings

var tracking := GunneryTrackingState.new()
var fire_command_id := 0

var _shooter_instance_id := 0
var _group_states: Dictionary = {}
var _mount_group_lookup: Dictionary = {}
var _frames_since_refresh := 1000000
var _last_solved_target_position := Vector3.ZERO
var _last_observation: GunneryObservation
var _last_actual_position := Vector3.ZERO
var _last_actual_velocity := Vector3.ZERO
var _elapsed_time_sec := 0.0
var _tracking_state_reset_count := 0
var _last_tracking_reset_reason: StringName = &""
var _bound_mount_refs: Dictionary = {}


func configure(
		next_difficulty: AIGunneryDifficultyProfile,
		next_crew_stats: GunneryCrewStats,
		next_debug_settings: BattleDebugSettings = null
) -> void:
	difficulty_profile = next_difficulty \
		if next_difficulty != null \
		and next_difficulty.validate().is_empty() else DEFAULT_DIFFICULTY
	# Single fallback location for missing crew data: default mid skills.
	crew_stats = next_crew_stats \
		if next_crew_stats != null else GunneryCrewStats.new()
	debug_settings = next_debug_settings


## Drives the fire-control pipeline. Call once per physics frame while the
## owning ship has an AI engagement target.
func update(
		owner_ship: ShipUnit,
		target: ShipUnit,
		cannon_mounts: Array[WeaponMount]
) -> void:
	if difficulty_profile == null:
		configure(null, null, null)
	if owner_ship == null or not is_instance_valid(owner_ship) \
			or target == null or not is_instance_valid(target):
		clear_tracking_target(&"invalid_target")
		return
	_shooter_instance_id = owner_ship.get_instance_id()
	if not is_tracking_target(target):
		begin_tracking_target(target)
	_elapsed_time_sec += 1.0 / maxf(
		float(Engine.physics_ticks_per_second),
		1.0
	)
	_rebuild_groups(cannon_mounts)
	_frames_since_refresh += 1
	_expire_salvo_sessions()
	var actual_position := target.global_position
	var actual_velocity := target.get_world_velocity()
	_last_actual_position = actual_position
	_last_actual_velocity = actual_velocity
	var refresh_frames := _get_refresh_frames()
	var moved_beyond_threshold := _last_solved_target_position \
		.distance_to(actual_position) \
		> _safe_nonnegative(
			difficulty_profile.aim_solution_repath_threshold_m,
			10.0
		)
	if _frames_since_refresh >= refresh_frames \
			or not tracking.has_observation \
			or moved_beyond_threshold:
		_refresh_observation(actual_position, actual_velocity)
		_refresh_group_solutions(target)
		_frames_since_refresh = 0
		_last_solved_target_position = actual_position


#region Target tracking lifecycle
func begin_tracking_target(target_ship: ShipUnit) -> bool:
	if target_ship == null or not is_instance_valid(target_ship):
		return false
	if is_tracking_target(target_ship):
		return false
	_release_all_provider_bindings()
	_group_states.clear()
	_mount_group_lookup.clear()
	fire_command_id += 1
	tracking.reset_for_target(target_ship, target_ship.get_instance_id())
	_tracking_state_reset_count += 1
	_last_tracking_reset_reason = &"new_target"
	_last_observation = null
	_frames_since_refresh = 1000000
	return true


func clear_tracking_target(reason: StringName = &"cleared") -> void:
	var had_tracking := tracking.target_instance_id != 0 \
		or not _group_states.is_empty() \
		or not _bound_mount_refs.is_empty()
	_release_all_provider_bindings()
	_group_states.clear()
	_mount_group_lookup.clear()
	tracking.reset_for_target(null, 0)
	_last_observation = null
	_frames_since_refresh = 1000000
	if had_tracking:
		_tracking_state_reset_count += 1
		_last_tracking_reset_reason = reason


func is_tracking_target(target_ship: ShipUnit) -> bool:
	if target_ship == null or not is_instance_valid(target_ship) \
			or tracking.target_ref == null:
		return false
	var tracked_value: Variant = tracking.target_ref.get_ref()
	if tracked_value == null or not is_instance_valid(tracked_value):
		return false
	return tracked_value == target_ship \
		and tracking.target_instance_id == target_ship.get_instance_id()


func clear() -> void:
	clear_tracking_target(&"clear")


func release_provider_bindings() -> void:
	_release_all_provider_bindings()
#endregion


#region Solution and deviation access
## Aim point a mount should track: the salvo-biased solution of its weapon
## group, or the raw fallback when no ballistic solution exists.
func get_aim_point_for_mount(
		mount: WeaponMount,
		fallback: Vector3
) -> Vector3:
	var group := _find_group_for_mount(mount)
	if group == null:
		return fallback
	if not group.has_solution:
		return fallback
	return group.biased_aim_point


func has_solution_for_mount(mount: WeaponMount) -> bool:
	var group := _find_group_for_mount(mount)
	return group != null and group.has_solution


## Duck-typed hook consumed by CannonMount at launch time: one deterministic
## (yaw, pitch) deviation per shell. Marks the group's current salvo as used.
func get_shell_deviation_radians(
		mount: WeaponMount,
		shell_index: int,
		_shell_count: int
) -> Vector2:
	var group := _find_group_for_mount(mount)
	if group == null or not group.has_solution \
			or group.current_salvo == null:
		return Vector2.ZERO
	if not group.salvo_active:
		_begin_group_salvo(group)
	group.shots_since_bias += 1
	group.shells_resolved_in_salvo += 1
	var mount_id := mount.get_instance_id()
	group.resolved_turret_ids[mount_id] = true
	var turret_index := group.mounts.find(mount as CannonMount)
	var shell_seed := GunneryAccuracyResolver.make_shell_seed(
		group.current_salvo.salvo_seed,
		maxi(turret_index, 0),
		shell_index
	)
	var range_offset := GunneryAccuracyResolver.sample_gaussian(
		hash([shell_seed, &"range"]),
		group.current_salvo.shell_dispersion_sigma_m
	)
	var lateral_offset := GunneryAccuracyResolver.sample_gaussian(
		hash([shell_seed, &"lateral"]),
		group.current_salvo.shell_dispersion_sigma_m
	)
	if group.resolved_turret_ids.size() \
			>= group.turrets_expected_in_salvo:
		group.salvo_active = false
	return GunneryAccuracyResolver.dispersion_to_launch_deviation(
		lateral_offset,
		range_offset,
		group.horizontal_range_m,
		group.projectile_speed_mps,
		group.gravity_mps2,
		group.elevation_rad
	)
#endregion


#region Debug snapshot
func get_debug_snapshots() -> Array[GunneryDebugSnapshot]:
	var snapshots: Array[GunneryDebugSnapshot] = []
	for group_value in _group_states.values():
		var group := group_value as GunneryWeaponGroupSession
		var snapshot := GunneryDebugSnapshot.new()
		snapshot.shooter_instance_id = _shooter_instance_id
		snapshot.target_instance_id = tracking.target_instance_id
		snapshot.weapon_group_id = group.group_key
		snapshot.target_actual_position = _last_actual_position
		snapshot.target_actual_velocity = _last_actual_velocity
		if _last_observation != null:
			snapshot.target_observed_position = \
				_last_observation.observed_position
			snapshot.target_observed_velocity = \
				_last_observation.observed_velocity
		snapshot.ideal_aim_point = group.ideal_aim_point
		snapshot.actual_aim_point = group.biased_aim_point
		snapshot.projectile_flight_time_sec = group.flight_time_sec
		if group.current_salvo != null:
			snapshot.range_error_m = \
				group.current_salvo.shared_range_error_m
			snapshot.lateral_error_m = \
				group.current_salvo.shared_lateral_error_m
			snapshot.shell_dispersion_sigma_m = \
				group.current_salvo.shell_dispersion_sigma_m
		snapshot.confidence = tracking.confidence
		snapshot.correction_level = tracking.correction_level
		snapshot.salvo_index = group.salvo_index
		snapshot.fire_command_id = fire_command_id
		snapshot.salvo_started_time_sec = group.salvo_started_time_sec
		snapshot.salvo_grouping_window_sec = \
			group.salvo_grouping_window_sec
		snapshot.shells_resolved_in_salvo = \
			group.shells_resolved_in_salvo
		snapshot.turrets_expected_in_salvo = \
			group.turrets_expected_in_salvo
		snapshot.tracking_target_instance_id = \
			tracking.target_instance_id
		snapshot.tracking_state_reset_count = \
			_tracking_state_reset_count
		snapshot.last_tracking_reset_reason = \
			_last_tracking_reset_reason
		snapshot.failure_reason = group.failure_reason
		snapshots.append(snapshot)
	return snapshots
#endregion


#region Observation and lead solution
func _get_refresh_frames() -> int:
	return maxi(1, roundi(
		_safe_nonnegative(
			difficulty_profile.aim_solution_refresh_interval_sec,
			0.2
		)
		* float(Engine.physics_ticks_per_second)
	))


func _refresh_observation(
		actual_position: Vector3,
		actual_velocity: Vector3
) -> void:
	var flat_velocity := actual_velocity
	flat_velocity.y = 0.0
	if tracking.has_observation:
		var velocity_change := (
			flat_velocity - tracking.previous_actual_velocity
		).length()
		var maneuver_alert := _safe_nonnegative(
			difficulty_profile.velocity_change_alert_mps,
			3.0
		)
		if velocity_change >= maneuver_alert:
			# Sharp maneuver: trust in the velocity estimate collapses and the
			# accumulated fall-of-shot correction partially resets.
			tracking.confidence = maxf(0.2, tracking.confidence * 0.5)
			tracking.correction_level *= 0.4
		else:
			tracking.confidence = minf(1.0, tracking.confidence + 0.1)
	tracking.previous_actual_velocity = flat_velocity
	tracking.observation_epoch += 1
	var observation_seed := hash([
		_shooter_instance_id,
		tracking.target_instance_id,
		fire_command_id,
		tracking.observation_epoch,
	])
	_last_observation = GunneryAccuracyResolver.observe_target(
		actual_position,
		actual_velocity,
		observation_seed,
		difficulty_profile,
		crew_stats,
		tracking.confidence
	)
	tracking.estimated_position = _last_observation.observed_position
	tracking.estimated_velocity = _last_observation.observed_velocity
	tracking.has_observation = true


func _refresh_group_solutions(target: ShipUnit) -> void:
	for group_value in _group_states.values():
		var group := group_value as GunneryWeaponGroupSession
		var representative := _get_representative_mount(group)
		group.fallback_aim_point = target.global_position
		if representative == null or _last_observation == null:
			group.has_solution = false
			group.failure_reason = &"no_operational_mount"
			continue
		group.projectile_speed_mps = \
			representative.get_modified_projectile_speed(
				representative.muzzle_velocity
			)
		group.gravity_mps2 = representative.get_effective_gravity_mps2()
		var lead := NavalGunLeadResolver.solve(
			representative.get_muzzle_position(),
			_last_observation.observed_position,
			_last_observation.observed_velocity,
			group.projectile_speed_mps,
			group.gravity_mps2
		)
		group.current_lead_result = lead
		if not lead.success:
			group.has_solution = false
			group.failure_reason = lead.failure_reason
			group.current_salvo = null
			group.reset_salvo_session()
			continue
		group.has_solution = true
		group.failure_reason = &""
		group.ideal_aim_point = lead.predicted_impact_position
		group.flight_time_sec = lead.projectile_flight_time_sec
		group.horizontal_range_m = lead.horizontal_distance_m
		group.elevation_rad = lead.elevation_rad
		if group.current_salvo == null:
			_generate_salvo_bias(group, representative, false)
		else:
			# Keep the frozen bias but re-center it on the fresh lead point so
			# the turret keeps tracking without re-rolling any error.
			group.biased_aim_point = (
				group.ideal_aim_point
				+ group.current_salvo.range_direction
					* group.current_salvo.shared_range_error_m
				+ group.current_salvo.lateral_direction
					* group.current_salvo.shared_lateral_error_m
			)
#endregion


#region Salvo lifecycle
func begin_salvo_for_mounts(cannon_mounts: Array[WeaponMount]) -> int:
	var ready_group_keys: Dictionary = {}
	for mount_value: Variant in cannon_mounts:
		if mount_value == null or not is_instance_valid(mount_value):
			continue
		var cannon := mount_value as CannonMount
		var group := _find_group_for_mount(cannon)
		if cannon == null or group == null or not group.has_solution:
			continue
		if cannon.get_current_fire_readiness() \
				== WeaponFireReadiness.State.READY:
			ready_group_keys[group.group_key] = true
	var started := 0
	for group_key_value: Variant in ready_group_keys:
		var group_key := StringName(group_key_value)
		if begin_salvo(group_key) != null:
			started += 1
	return started


func begin_salvo(
		weapon_group_id: StringName
) -> GunnerySalvoSolution:
	var group := _group_states.get(weapon_group_id) \
		as GunneryWeaponGroupSession
	if group == null or not group.has_solution \
			or group.current_salvo == null:
		return null
	if group.salvo_active:
		return group.current_salvo
	if group.shots_since_bias > 0:
		var representative := _get_representative_mount(group)
		if representative == null:
			return null
		_advance_correction()
		_generate_salvo_bias(group, representative, true)
	_begin_group_salvo(group)
	return group.current_salvo


func bind_mount_provider(cannon: CannonMount) -> void:
	if cannon == null or not is_instance_valid(cannon):
		return
	cannon.shell_deviation_provider = self
	_bound_mount_refs[cannon.get_instance_id()] = weakref(cannon)


func get_group_session_for_mount(
		mount: WeaponMount
) -> GunneryWeaponGroupSession:
	return _find_group_for_mount(mount)


func _begin_group_salvo(group: GunneryWeaponGroupSession) -> void:
	if group == null or group.current_salvo == null:
		return
	group.reset_salvo_session()
	group.salvo_active = true
	group.salvo_started_time_sec = _elapsed_time_sec
	group.fire_command_id = fire_command_id
	var profile := _get_accuracy_profile(_get_representative_mount(group))
	group.salvo_grouping_window_sec = maxf(
		_safe_nonnegative(profile.salvo_grouping_window_sec, 0.35),
		0.001
	)
	for cannon in group.mounts:
		if cannon != null and is_instance_valid(cannon) \
				and cannon.is_operational():
			group.turrets_expected_in_salvo += 1
	if group.turrets_expected_in_salvo <= 0:
		group.turrets_expected_in_salvo = 1


func _expire_salvo_sessions() -> void:
	for group_value in _group_states.values():
		var group := group_value as GunneryWeaponGroupSession
		if group == null or not group.salvo_active:
			continue
		if _elapsed_time_sec - group.salvo_started_time_sec \
				>= group.salvo_grouping_window_sec:
			group.salvo_active = false


func _generate_salvo_bias(
		group: GunneryWeaponGroupSession,
		representative: CannonMount,
		advance_salvo: bool
) -> void:
	if advance_salvo:
		group.salvo_index += 1
		tracking.salvo_index = maxi(tracking.salvo_index, group.salvo_index)
	var context := _build_context(group, representative)
	group.current_salvo = GunneryAccuracyResolver.create_salvo_solution(
		context
	)
	group.biased_aim_point = group.current_salvo.biased_salvo_center
	group.shots_since_bias = 0
	group.reset_salvo_session()
	tracking.range_bias_m = group.current_salvo.shared_range_error_m
	tracking.lateral_bias_m = group.current_salvo.shared_lateral_error_m
	if debug_settings != null and debug_settings.log_gunnery_fire_control:
		print(
			"[GunneryFC] shooter=%d target=%d group=%s salvo=%d "
			% [
				_shooter_instance_id,
				tracking.target_instance_id,
				String(group.group_key),
				group.salvo_index,
			]
			+ "range_err=%.1f lateral_err=%.1f dispersion_sigma=%.1f "
			% [
				group.current_salvo.shared_range_error_m,
				group.current_salvo.shared_lateral_error_m,
				group.current_salvo.shell_dispersion_sigma_m,
			]
			+ "flight=%.2f correction=%.2f confidence=%.2f"
			% [
				group.flight_time_sec,
				tracking.correction_level,
				tracking.confidence,
			]
		)


func _advance_correction() -> void:
	var correction_skill := crew_stats.salvo_correction_skill
	if is_nan(correction_skill) or is_inf(correction_skill):
		correction_skill = 0.5
	correction_skill = clampf(correction_skill, 0.0, 1.0)
	var strength := (
		clampf(
			_safe_nonnegative(
				difficulty_profile.base_salvo_correction_strength,
				0.25
			),
			0.0,
			1.0
		)
		* _safe_nonnegative(
			difficulty_profile.salvo_correction_multiplier,
			1.0
		)
		* lerpf(0.5, 1.5, correction_skill)
	)
	tracking.correction_level = clampf(
		tracking.correction_level + strength,
		0.0,
		1.0
	)
#endregion


#region Accuracy context and weapon groups
func _build_context(
		group: GunneryWeaponGroupSession,
		representative: CannonMount
) -> GunneryAccuracyContext:
	var context := GunneryAccuracyContext.new()
	context.shooter_instance_id = _shooter_instance_id
	context.target_instance_id = tracking.target_instance_id
	context.fire_command_id = fire_command_id
	context.salvo_index = group.salvo_index
	context.weapon_group_id = group.group_key
	context.launch_position = representative.get_muzzle_position()
	context.ideal_aim_point = group.ideal_aim_point
	context.range_m = group.horizontal_range_m
	context.projectile_flight_time_sec = group.flight_time_sec
	context.actual_target_velocity = _last_actual_velocity
	context.observed_target_velocity = tracking.estimated_velocity
	context.salvo_correction_level = tracking.correction_level
	context.weapon_accuracy_profile = _get_accuracy_profile(representative)
	context.difficulty_profile = difficulty_profile
	context.crew_stats = crew_stats
	return context


func _get_accuracy_profile(
		mount: CannonMount
) -> GunneryWeaponAccuracyProfile:
	var weapon_profile := mount.weapon_data.gunnery_accuracy_profile \
		if mount != null and mount.weapon_data != null else null
	return GunneryAccuracyProfileResolver.resolve(weapon_profile)


func _rebuild_groups(cannon_mounts: Array[WeaponMount]) -> void:
	var seen_groups: Dictionary = {}
	var active_mount_ids: Dictionary = {}
	_mount_group_lookup.clear()
	for mount_value: Variant in cannon_mounts:
		# Validity first: casting an already-freed mount raises
		# "Trying to cast a freed object".
		if mount_value == null or not is_instance_valid(mount_value):
			continue
		var cannon := mount_value as CannonMount
		if cannon == null:
			continue
		var group_key := _get_group_key(cannon)
		var group: GunneryWeaponGroupSession
		if _group_states.has(group_key):
			group = _group_states[group_key] as GunneryWeaponGroupSession
		else:
			group = GunneryWeaponGroupSession.new()
			group.group_key = group_key
			_group_states[group_key] = group
		if not seen_groups.has(group_key):
			group.mounts.clear()
			group.mounted_turret_ids.clear()
			seen_groups[group_key] = true
		group.mounts.append(cannon)
		var mount_id := cannon.get_instance_id()
		group.mounted_turret_ids.append(mount_id)
		_mount_group_lookup[mount_id] = group_key
		active_mount_ids[mount_id] = true
	for existing_key in _group_states.keys().duplicate():
		if not seen_groups.has(existing_key):
			_group_states.erase(existing_key)
	for group_value: Variant in _group_states.values():
		var group := group_value as GunneryWeaponGroupSession
		if group == null:
			continue
		group.mounts.sort_custom(
			func(left: CannonMount, right: CannonMount) -> bool:
				return left.get_instance_id() < right.get_instance_id()
		)
		group.mounted_turret_ids.clear()
		for cannon: CannonMount in group.mounts:
			group.mounted_turret_ids.append(cannon.get_instance_id())
	_release_stale_provider_bindings(active_mount_ids)


func _get_group_key(cannon: CannonMount) -> StringName:
	if cannon.weapon_data != null and not cannon.weapon_data.id.is_empty():
		return StringName(cannon.weapon_data.id)
	return StringName("mount_%d" % cannon.get_instance_id())


func _get_representative_mount(
		group: GunneryWeaponGroupSession
) -> CannonMount:
	for cannon in group.mounts:
		if is_instance_valid(cannon) and cannon.is_operational() \
				and cannon.has_valid_preview_muzzle():
			return cannon
	for cannon in group.mounts:
		if is_instance_valid(cannon):
			return cannon
	return null


func _find_group_for_mount(
		mount: WeaponMount
) -> GunneryWeaponGroupSession:
	if mount == null or not is_instance_valid(mount):
		return null
	var group_key: Variant = _mount_group_lookup.get(mount.get_instance_id())
	if group_key == null:
		return null
	return _group_states.get(group_key) as GunneryWeaponGroupSession


func _release_stale_provider_bindings(active_mount_ids: Dictionary) -> void:
	for mount_id: int in _bound_mount_refs.keys().duplicate():
		if active_mount_ids.has(mount_id):
			continue
		_release_provider_binding(mount_id)


func _release_all_provider_bindings() -> void:
	for mount_id: int in _bound_mount_refs.keys().duplicate():
		_release_provider_binding(mount_id)


func _release_provider_binding(mount_id: int) -> void:
	var reference := _bound_mount_refs.get(mount_id) as WeakRef
	_bound_mount_refs.erase(mount_id)
	if reference == null:
		return
	var value: Variant = reference.get_ref()
	if value == null or not is_instance_valid(value):
		return
	var cannon := value as CannonMount
	if cannon != null and cannon.shell_deviation_provider == self:
		cannon.shell_deviation_provider = null


func _safe_nonnegative(value: float, fallback: float) -> float:
	if is_nan(value) or is_inf(value):
		return maxf(fallback, 0.0)
	return maxf(value, 0.0)
#endregion

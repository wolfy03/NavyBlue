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
const DEFAULT_ACCURACY_PROFILE: GunneryWeaponAccuracyProfile = preload(
	"res://resources/weapon_accuracy/default_cannon_accuracy.tres"
)


class GroupState:
	extends RefCounted

	var group_id: StringName = &""
	var mounts: Array[CannonMount] = []
	var has_solution := false
	var failure_reason: StringName = &""
	var ideal_aim_point := Vector3.ZERO
	var biased_aim_point := Vector3.ZERO
	var fallback_aim_point := Vector3.ZERO
	var flight_time_sec := 0.0
	var horizontal_range_m := 0.0
	var projectile_speed_mps := 0.0
	var elevation_rad := 0.0
	var gravity_mps2 := 9.8
	var salvo_solution: GunnerySalvoSolution
	var salvo_index := 0
	var shots_since_bias := 0
	var frames_since_bias := 0


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


func configure(
		next_difficulty: AIGunneryDifficultyProfile,
		next_crew_stats: GunneryCrewStats,
		next_debug_settings: BattleDebugSettings = null
) -> void:
	difficulty_profile = next_difficulty \
		if next_difficulty != null else DEFAULT_DIFFICULTY
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
		clear()
		return
	_shooter_instance_id = owner_ship.get_instance_id()
	var target_id := target.get_instance_id()
	if tracking.target_instance_id != target_id:
		_begin_tracking(target, target_id)
	_rebuild_groups(cannon_mounts)
	_frames_since_refresh += 1
	for group in _group_states.values():
		(group as GroupState).frames_since_bias += 1
	var actual_position := target.global_position
	var actual_velocity := target.get_world_velocity()
	_last_actual_position = actual_position
	_last_actual_velocity = actual_velocity
	var refresh_frames := _get_refresh_frames()
	var moved_beyond_threshold := _last_solved_target_position \
		.distance_to(actual_position) \
		> difficulty_profile.aim_solution_repath_threshold_m
	if _frames_since_refresh >= refresh_frames \
			or not tracking.has_observation \
			or moved_beyond_threshold:
		_refresh_observation(actual_position, actual_velocity)
		_refresh_group_solutions(target)
		_frames_since_refresh = 0
		_last_solved_target_position = actual_position
	_refresh_salvo_biases(refresh_frames)


func clear() -> void:
	_group_states.clear()
	_mount_group_lookup.clear()
	tracking.reset_for_target(null, 0)
	_last_observation = null
	_frames_since_refresh = 1000000


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
			or group.salvo_solution == null:
		return Vector2.ZERO
	group.shots_since_bias += 1
	var turret_index := group.mounts.find(mount as CannonMount)
	var shell_seed := GunneryAccuracyResolver.make_shell_seed(
		group.salvo_solution.salvo_seed,
		maxi(turret_index, 0),
		shell_index
	)
	var range_offset := GunneryAccuracyResolver.sample_gaussian(
		hash([shell_seed, &"range"]),
		group.salvo_solution.shell_dispersion_sigma_m
	)
	var lateral_offset := GunneryAccuracyResolver.sample_gaussian(
		hash([shell_seed, &"lateral"]),
		group.salvo_solution.shell_dispersion_sigma_m
	)
	return GunneryAccuracyResolver.dispersion_to_launch_deviation(
		lateral_offset,
		range_offset,
		group.horizontal_range_m,
		group.projectile_speed_mps,
		group.gravity_mps2,
		group.elevation_rad
	)


func get_debug_snapshots() -> Array[GunneryDebugSnapshot]:
	var snapshots: Array[GunneryDebugSnapshot] = []
	for group_value in _group_states.values():
		var group := group_value as GroupState
		var snapshot := GunneryDebugSnapshot.new()
		snapshot.shooter_instance_id = _shooter_instance_id
		snapshot.target_instance_id = tracking.target_instance_id
		snapshot.weapon_group_id = group.group_id
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
		if group.salvo_solution != null:
			snapshot.range_error_m = \
				group.salvo_solution.shared_range_error_m
			snapshot.lateral_error_m = \
				group.salvo_solution.shared_lateral_error_m
			snapshot.shell_dispersion_sigma_m = \
				group.salvo_solution.shell_dispersion_sigma_m
		snapshot.confidence = tracking.confidence
		snapshot.correction_level = tracking.correction_level
		snapshot.salvo_index = group.salvo_index
		snapshot.fire_command_id = fire_command_id
		snapshot.failure_reason = group.failure_reason
		snapshots.append(snapshot)
	return snapshots


func _begin_tracking(target: ShipUnit, target_id: int) -> void:
	fire_command_id += 1
	tracking.reset_for_target(target, target_id)
	_group_states.clear()
	_mount_group_lookup.clear()
	_frames_since_refresh = 1000000


func _get_refresh_frames() -> int:
	return maxi(1, roundi(
		difficulty_profile.aim_solution_refresh_interval_sec
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
		if velocity_change >= difficulty_profile.velocity_change_alert_mps:
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
		var group := group_value as GroupState
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
		if not lead.success:
			group.has_solution = false
			group.failure_reason = lead.failure_reason
			group.salvo_solution = null
			continue
		group.has_solution = true
		group.failure_reason = &""
		group.ideal_aim_point = lead.predicted_impact_position
		group.flight_time_sec = lead.projectile_flight_time_sec
		group.horizontal_range_m = lead.horizontal_distance_m
		group.elevation_rad = lead.elevation_rad
		if group.salvo_solution == null:
			_generate_salvo_bias(group, representative, false)
		else:
			# Keep the frozen bias but re-center it on the fresh lead point so
			# the turret keeps tracking without re-rolling any error.
			group.biased_aim_point = (
				group.ideal_aim_point
				+ group.salvo_solution.range_direction
					* group.salvo_solution.shared_range_error_m
				+ group.salvo_solution.lateral_direction
					* group.salvo_solution.shared_lateral_error_m
			)


func _refresh_salvo_biases(refresh_frames: int) -> void:
	for group_value in _group_states.values():
		var group := group_value as GroupState
		if not group.has_solution:
			continue
		if group.shots_since_bias > 0 \
				and group.frames_since_bias >= refresh_frames:
			var representative := _get_representative_mount(group)
			if representative != null:
				_advance_correction()
				_generate_salvo_bias(group, representative, true)


func _generate_salvo_bias(
		group: GroupState,
		representative: CannonMount,
		advance_salvo: bool
) -> void:
	if advance_salvo:
		group.salvo_index += 1
		tracking.salvo_index = maxi(tracking.salvo_index, group.salvo_index)
	var context := _build_context(group, representative)
	group.salvo_solution = GunneryAccuracyResolver.create_salvo_solution(
		context
	)
	group.biased_aim_point = group.salvo_solution.biased_salvo_center
	group.shots_since_bias = 0
	group.frames_since_bias = 0
	tracking.range_bias_m = group.salvo_solution.shared_range_error_m
	tracking.lateral_bias_m = group.salvo_solution.shared_lateral_error_m
	if debug_settings != null and debug_settings.log_gunnery_fire_control:
		print(
			"[GunneryFC] shooter=%d target=%d group=%s salvo=%d "
			% [
				_shooter_instance_id,
				tracking.target_instance_id,
				String(group.group_id),
				group.salvo_index,
			]
			+ "range_err=%.1f lateral_err=%.1f dispersion_sigma=%.1f "
			% [
				group.salvo_solution.shared_range_error_m,
				group.salvo_solution.shared_lateral_error_m,
				group.salvo_solution.shell_dispersion_sigma_m,
			]
			+ "flight=%.2f correction=%.2f confidence=%.2f"
			% [
				group.flight_time_sec,
				tracking.correction_level,
				tracking.confidence,
			]
		)


func _advance_correction() -> void:
	var strength := (
		difficulty_profile.base_salvo_correction_strength
		* difficulty_profile.salvo_correction_multiplier
		* lerpf(0.5, 1.5, crew_stats.salvo_correction_skill)
	)
	tracking.correction_level = clampf(
		tracking.correction_level + strength,
		0.0,
		1.0
	)


func _build_context(
		group: GroupState,
		representative: CannonMount
) -> GunneryAccuracyContext:
	var context := GunneryAccuracyContext.new()
	context.shooter_instance_id = _shooter_instance_id
	context.target_instance_id = tracking.target_instance_id
	context.fire_command_id = fire_command_id
	context.salvo_index = group.salvo_index
	context.weapon_group_id = group.group_id
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
	if mount.weapon_data != null \
			and mount.weapon_data.gunnery_accuracy_profile != null:
		return mount.weapon_data.gunnery_accuracy_profile
	return DEFAULT_ACCURACY_PROFILE


func _rebuild_groups(cannon_mounts: Array[WeaponMount]) -> void:
	var seen_groups: Dictionary = {}
	_mount_group_lookup.clear()
	for mount_value in cannon_mounts:
		var cannon := mount_value as CannonMount
		if cannon == null or not is_instance_valid(cannon):
			continue
		var group_key := _get_group_key(cannon)
		var group: GroupState
		if _group_states.has(group_key):
			group = _group_states[group_key] as GroupState
		else:
			group = GroupState.new()
			group.group_id = group_key
			_group_states[group_key] = group
		if not seen_groups.has(group_key):
			group.mounts.clear()
			seen_groups[group_key] = true
		group.mounts.append(cannon)
		_mount_group_lookup[cannon.get_instance_id()] = group_key
	for existing_key in _group_states.keys().duplicate():
		if not seen_groups.has(existing_key):
			_group_states.erase(existing_key)


func _get_group_key(cannon: CannonMount) -> StringName:
	if cannon.weapon_data != null and not cannon.weapon_data.id.is_empty():
		return StringName(cannon.weapon_data.id)
	return StringName("mount_%d" % cannon.get_instance_id())


func _get_representative_mount(group: GroupState) -> CannonMount:
	for cannon in group.mounts:
		if is_instance_valid(cannon) and cannon.is_operational() \
				and cannon.has_valid_preview_muzzle():
			return cannon
	for cannon in group.mounts:
		if is_instance_valid(cannon):
			return cannon
	return null


func _find_group_for_mount(mount: WeaponMount) -> GroupState:
	if mount == null or not is_instance_valid(mount):
		return null
	var group_key: Variant = _mount_group_lookup.get(mount.get_instance_id())
	if group_key == null:
		return null
	return _group_states.get(group_key) as GroupState

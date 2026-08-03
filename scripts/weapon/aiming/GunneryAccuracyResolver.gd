extends RefCounted
class_name GunneryAccuracyResolver
## Layered gunnery error model. Every random draw uses a deterministic,
## explicitly seeded RandomNumberGenerator so identical inputs reproduce
## identical aim errors. Error layers:
##   observation  -> where the AI believes the target is and how it moves
##   salvo bias   -> shared fire-control error for one whole salvo
##   dispersion   -> independent per-shell mechanical spread
## Accuracy is always physical: it moves the aim point or launch direction and
## never gates damage after a real hit.

const EPSILON := 0.0001
const GAUSSIAN_CLAMP_SIGMAS := 3.0
const MAX_SHELL_PITCH_DEVIATION_RAD := 0.035


static func make_salvo_seed(
		shooter_instance_id: int,
		target_instance_id: int,
		fire_command_id: int,
		salvo_index: int,
		weapon_group_id: StringName
) -> int:
	return hash([
		shooter_instance_id,
		target_instance_id,
		fire_command_id,
		salvo_index,
		weapon_group_id,
	])


static func make_shell_seed(
		salvo_seed: int,
		turret_index: int,
		shell_index: int
) -> int:
	return hash([salvo_seed, turret_index, shell_index])


## Seed for an independently firing mount. The mount instance id and its own
## monotonic fire sequence replace the shared salvo index, so two guns of the
## same weapon group never draw the same error even on the same frame.
static func make_mount_seed(
		shooter_instance_id: int,
		target_instance_id: int,
		mount_instance_id: int,
		fire_sequence_index: int,
		weapon_group_id: StringName
) -> int:
	return hash([
		shooter_instance_id,
		target_instance_id,
		mount_instance_id,
		fire_sequence_index,
		weapon_group_id,
	])


## Single deterministic gaussian draw, clamped to +-3 sigma so a rare extreme
## roll cannot throw a shell absurdly far.
static func sample_gaussian(seed_value: int, sigma_m: float) -> float:
	if sigma_m <= 0.0:
		return 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return clampf(
		rng.randfn(0.0, sigma_m),
		-GAUSSIAN_CLAMP_SIGMAS * sigma_m,
		GAUSSIAN_CLAMP_SIGMAS * sigma_m
	)


static func compute_range_factor(
		range_m: float,
		profile: GunneryWeaponAccuracyProfile,
		growth_exponent: float
) -> float:
	var reference_range := maxf(
		_sanitize_nonnegative(profile.reference_range_m, 1.0),
		1.0
	)
	var minimum_factor := maxf(
		_sanitize_nonnegative(profile.minimum_range_factor, 0.25),
		EPSILON
	)
	var maximum_factor := maxf(
		_sanitize_nonnegative(profile.maximum_range_factor, minimum_factor),
		minimum_factor
	)
	var ratio := maxf(
		_sanitize_nonnegative(range_m) / reference_range,
		minimum_factor
	)
	return minf(
		pow(ratio, _sanitize_nonnegative(growth_exponent)),
		maximum_factor
	)


## Fills the sigma fields of a result from weapon profile x difficulty x crew.
static func compute_sigmas(
		context: GunneryAccuracyContext
) -> GunneryAccuracyResult:
	var weapon_profile := context.weapon_accuracy_profile
	var difficulty := context.difficulty_profile
	var crew := context.crew_stats
	if weapon_profile == null or difficulty == null or crew == null:
		return GunneryAccuracyResult.failed(&"missing_profiles")
	var result := GunneryAccuracyResult.new()
	result.success = true
	result.ideal_aim_point = context.ideal_aim_point
	var rangefinding_skill := _sanitize_skill(crew.rangefinding_skill)
	var tracking_skill := _sanitize_skill(crew.target_tracking_skill)
	var fire_control_skill := _sanitize_skill(crew.fire_control_skill)
	var gun_laying_skill := _sanitize_skill(crew.gun_laying_skill)
	var crew_range_multiplier := lerpf(1.5, 0.45, rangefinding_skill)
	var crew_tracking_multiplier := lerpf(1.6, 0.5, tracking_skill)
	var crew_lead_multiplier := lerpf(1.3, 0.7, fire_control_skill)
	var crew_dispersion_multiplier := lerpf(1.4, 0.55, gun_laying_skill)
	result.range_sigma_m = (
		_sanitize_nonnegative(weapon_profile.base_range_error_m)
		* compute_range_factor(
			context.range_m,
			weapon_profile,
			weapon_profile.range_error_growth_exponent
		)
		* _sanitize_nonnegative(difficulty.range_error_multiplier)
		* crew_range_multiplier
		* crew_lead_multiplier
	)
	result.lateral_sigma_m = (
		_sanitize_nonnegative(weapon_profile.base_lateral_error_m)
		* compute_range_factor(
			context.range_m,
			weapon_profile,
			weapon_profile.lateral_error_growth_exponent
		)
		* _sanitize_nonnegative(difficulty.lateral_error_multiplier)
		* crew_tracking_multiplier
	)
	result.shell_dispersion_sigma_m = (
		_sanitize_nonnegative(weapon_profile.base_shell_dispersion_m)
		* compute_range_factor(
			context.range_m,
			weapon_profile,
			weapon_profile.dispersion_growth_exponent
		)
		* _sanitize_nonnegative(difficulty.shell_dispersion_multiplier)
		* crew_dispersion_multiplier
	)
	var floor_scale := maxf(
		_sanitize_nonnegative(difficulty.minimum_error_multiplier, 1.0),
		EPSILON
	)
	result.range_sigma_m = maxf(
		result.range_sigma_m,
		maxf(
			_sanitize_nonnegative(weapon_profile.minimum_range_error_m, 2.0),
			EPSILON
		) * floor_scale
	)
	result.lateral_sigma_m = maxf(
		result.lateral_sigma_m,
		maxf(
			_sanitize_nonnegative(weapon_profile.minimum_lateral_error_m, 2.0),
			EPSILON
		) * floor_scale
	)
	result.shell_dispersion_sigma_m = maxf(
		result.shell_dispersion_sigma_m,
		maxf(
			_sanitize_nonnegative(
				weapon_profile.minimum_shell_dispersion_m,
				1.0
			),
			EPSILON
		) * floor_scale
	)
	return result


## Builds the shared solution for one salvo: every shell launched against this
## solution shares the same biased center point.
static func create_salvo_solution(
		context: GunneryAccuracyContext
) -> GunnerySalvoSolution:
	var sigmas := compute_sigmas(context)
	var solution := GunnerySalvoSolution.new()
	solution.command_id = context.fire_command_id
	solution.salvo_index = context.salvo_index
	solution.weapon_group_id = context.weapon_group_id
	solution.ideal_aim_point = context.ideal_aim_point
	solution.projectile_flight_time_sec = context.projectile_flight_time_sec
	var range_direction := context.ideal_aim_point - context.launch_position
	range_direction.y = 0.0
	if not sigmas.success \
			or range_direction.length_squared() <= EPSILON:
		solution.biased_salvo_center = context.ideal_aim_point
		return solution
	range_direction = range_direction.normalized()
	solution.range_direction = range_direction
	solution.lateral_direction = Vector3(
		-range_direction.z,
		0.0,
		range_direction.x
	)
	solution.range_sigma_m = sigmas.range_sigma_m
	solution.lateral_sigma_m = sigmas.lateral_sigma_m
	solution.shell_dispersion_sigma_m = sigmas.shell_dispersion_sigma_m
	# Consecutive salvos against the same target walk the shared bias toward
	# zero, but the minimum floors keep the final bias from vanishing.
	var correction_scale := lerpf(
		1.0,
		clampf(
			_sanitize_nonnegative(
				context.difficulty_profile.minimum_corrected_bias_ratio,
				0.4
			),
			0.0,
			1.0
		),
		clampf(context.salvo_correction_level, 0.0, 1.0)
	)
	solution.salvo_seed = make_salvo_seed(
		context.shooter_instance_id,
		context.target_instance_id,
		context.fire_command_id,
		context.salvo_index,
		context.weapon_group_id
	)
	solution.shared_range_error_m = sample_gaussian(
		hash([solution.salvo_seed, &"range"]),
		solution.range_sigma_m
	) * correction_scale
	solution.shared_lateral_error_m = sample_gaussian(
		hash([solution.salvo_seed, &"lateral"]),
		solution.lateral_sigma_m
	) * correction_scale
	solution.biased_salvo_center = (
		context.ideal_aim_point
		+ solution.range_direction * solution.shared_range_error_m
		+ solution.lateral_direction * solution.shared_lateral_error_m
	)
	return solution


## Bias solution for a single independently firing mount.
##
## Reuses the same sigma model and geometry as create_salvo_solution; only the
## seed differs, so the mount owns its fire-control bias instead of sharing the
## group's. The result is still a GunnerySalvoSolution: downstream dispersion
## and aim-point code is identical for both modes.
static func create_independent_mount_solution(
		context: GunneryAccuracyContext,
		mount_instance_id: int,
		fire_sequence_index: int
) -> GunnerySalvoSolution:
	var solution := create_salvo_solution(context)
	if not solution.has_bias_basis():
		return solution
	var mount_seed := make_mount_seed(
		context.shooter_instance_id,
		context.target_instance_id,
		mount_instance_id,
		fire_sequence_index,
		context.weapon_group_id
	)
	solution.salvo_seed = mount_seed
	solution.salvo_index = fire_sequence_index
	var correction_scale := lerpf(
		1.0,
		clampf(
			_sanitize_nonnegative(
				context.difficulty_profile.minimum_corrected_bias_ratio,
				0.4
			),
			0.0,
			1.0
		),
		clampf(context.salvo_correction_level, 0.0, 1.0)
	)
	solution.shared_range_error_m = sample_gaussian(
		hash([mount_seed, &"range"]),
		solution.range_sigma_m
	) * correction_scale
	solution.shared_lateral_error_m = sample_gaussian(
		hash([mount_seed, &"lateral"]),
		solution.lateral_sigma_m
	) * correction_scale
	solution.biased_salvo_center = (
		context.ideal_aim_point
		+ solution.range_direction * solution.shared_range_error_m
		+ solution.lateral_direction * solution.shared_lateral_error_m
	)
	return solution


## Per-shell mechanical dispersion around the shared salvo center.
static func resolve_shell_point(
		salvo_solution: GunnerySalvoSolution,
		context: GunneryAccuracyContext,
		shell_index: int
) -> GunneryAccuracyResult:
	var result := GunneryAccuracyResult.new()
	result.success = true
	result.ideal_aim_point = salvo_solution.ideal_aim_point
	result.range_sigma_m = salvo_solution.range_sigma_m
	result.lateral_sigma_m = salvo_solution.lateral_sigma_m
	result.shell_dispersion_sigma_m = salvo_solution.shell_dispersion_sigma_m
	result.range_error_m = salvo_solution.shared_range_error_m
	result.lateral_error_m = salvo_solution.shared_lateral_error_m
	result.salvo_bias_offset = (
		salvo_solution.biased_salvo_center - salvo_solution.ideal_aim_point
	)
	var shell_seed := make_shell_seed(
		salvo_solution.salvo_seed,
		context.turret_index,
		shell_index
	)
	result.shell_range_dispersion_m = sample_gaussian(
		hash([shell_seed, &"range"]),
		salvo_solution.shell_dispersion_sigma_m
	)
	result.shell_lateral_dispersion_m = sample_gaussian(
		hash([shell_seed, &"lateral"]),
		salvo_solution.shell_dispersion_sigma_m
	)
	result.shell_dispersion_offset = (
		salvo_solution.range_direction * result.shell_range_dispersion_m
		+ salvo_solution.lateral_direction * result.shell_lateral_dispersion_m
	)
	result.actual_aim_point = (
		salvo_solution.biased_salvo_center + result.shell_dispersion_offset
	)
	return result


## Delayed, noisy view of the target. The AI never reads the target's true
## state directly; this observation is what feeds the lead resolver.
static func observe_target(
		actual_position: Vector3,
		actual_velocity: Vector3,
		observation_seed: int,
		difficulty: AIGunneryDifficultyProfile,
		crew: GunneryCrewStats,
		confidence: float
) -> GunneryObservation:
	var observation := GunneryObservation.new()
	if difficulty == null or crew == null:
		observation.observed_position = actual_position
		observation.observed_velocity = actual_velocity
		return observation
	var confidence_penalty := 2.0 - _sanitize_skill(confidence)
	var minimum_delay := _sanitize_nonnegative(
		difficulty.minimum_observation_delay_sec
	)
	var maximum_delay := maxf(
		_sanitize_nonnegative(
			difficulty.maximum_observation_delay_sec,
			minimum_delay
		),
		minimum_delay
	)
	var tracking_skill := _sanitize_skill(crew.target_tracking_skill)
	var rangefinding_skill := _sanitize_skill(crew.rangefinding_skill)
	observation.observation_delay_sec = lerpf(
		maximum_delay,
		minimum_delay,
		tracking_skill
	) * _sanitize_nonnegative(difficulty.observation_delay_multiplier)
	observation.position_sigma_m = (
		_sanitize_nonnegative(difficulty.base_position_observation_error_m)
		* _sanitize_nonnegative(
			difficulty.position_observation_error_multiplier
		)
		* lerpf(1.5, 0.5, rangefinding_skill)
		* confidence_penalty
	)
	observation.velocity_sigma_mps = (
		_sanitize_nonnegative(difficulty.base_velocity_observation_error_mps)
		* _sanitize_nonnegative(
			difficulty.velocity_observation_error_multiplier
		)
		* lerpf(1.6, 0.5, tracking_skill)
		* confidence_penalty
	)
	var flat_velocity := actual_velocity
	flat_velocity.y = 0.0
	observation.observed_position = (
		actual_position
		- flat_velocity * observation.observation_delay_sec
		+ Vector3(
			sample_gaussian(
				hash([observation_seed, &"pos_x"]),
				observation.position_sigma_m
			),
			0.0,
			sample_gaussian(
				hash([observation_seed, &"pos_z"]),
				observation.position_sigma_m
			)
		)
	)
	observation.observed_velocity = flat_velocity + Vector3(
		sample_gaussian(
			hash([observation_seed, &"vel_x"]),
			observation.velocity_sigma_mps
		),
		0.0,
		sample_gaussian(
			hash([observation_seed, &"vel_z"]),
			observation.velocity_sigma_mps
		)
	)
	return observation


## Converts a per-shell world-space dispersion into small launch-direction
## deviations (yaw, pitch) so the spread stays purely physical: the shell
## still flies with real ballistics and lands in the water when it misses.
static func dispersion_to_launch_deviation(
		lateral_offset_m: float,
		range_offset_m: float,
		horizontal_range_m: float,
		projectile_speed_mps: float,
		gravity_mps2: float,
		elevation_rad: float
) -> Vector2:
	var safe_range := maxf(horizontal_range_m, 1.0)
	var yaw_rad := atan(lateral_offset_m / safe_range)
	var pitch_rad := 0.0
	if gravity_mps2 > EPSILON and projectile_speed_mps > EPSILON:
		# dR/d(theta) of the flat-ground range equation R = v^2 sin(2t)/g.
		var range_derivative := (
			2.0 * projectile_speed_mps * projectile_speed_mps
			* cos(2.0 * elevation_rad) / gravity_mps2
		)
		if absf(range_derivative) > 1.0:
			pitch_rad = range_offset_m / range_derivative
	return Vector2(
		yaw_rad,
		clampf(
			pitch_rad,
			-MAX_SHELL_PITCH_DEVIATION_RAD,
			MAX_SHELL_PITCH_DEVIATION_RAD
		)
	)


static func _sanitize_nonnegative(
		value: float,
		fallback: float = 0.0
) -> float:
	if is_nan(value) or is_inf(value):
		return maxf(fallback, 0.0)
	return maxf(value, 0.0)


static func _sanitize_skill(value: float) -> float:
	if is_nan(value) or is_inf(value):
		return 0.5
	return clampf(value, 0.0, 1.0)

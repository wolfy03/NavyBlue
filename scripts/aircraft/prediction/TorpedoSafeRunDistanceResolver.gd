extends RefCounted
class_name TorpedoSafeRunDistanceResolver

# Computes how far short of a target an air-dropped torpedo must be released so
# it is armed by the time it reaches the hull. Replaces the old fixed
# "arming + 100 m" constant with a per-attack calculation built from:
#
#   arming distance          - from the actual equipped TorpedoProjectileData
#   collision margin         - projected hull extent along the attack axis
#   prediction-error margin  - how far the target moves between repaths
#   additional safety margin - profile-tunable head-room
#   airborne-travel margin   - horizontal distance covered during the ballistic
#                              fall, which does NOT count toward arming because
#                              TorpedoProjectile resets its travelled distance at
#                              water entry
#
# The arithmetic core (`compose`) is a pure static so it can be unit-tested
# without a ship or scene; `resolve` only gathers the live inputs and delegates.

const DEFAULT_ARMING_DISTANCE_M := 50.0


func resolve(
		torpedo_data: TorpedoProjectileData,
		target_ship: ShipUnit,
		attack_profile: TorpedoAttackProfile,
		attack_direction: Vector3,
		target_velocity: Vector3,
		prediction_refresh_interval_sec: float,
		expected_release_velocity: Vector3 = Vector3.ZERO,
		downward_release_speed_mps: float = 0.0,
		gravity_mps2: float = 0.0
) -> TorpedoSafeRunDistanceResult:
	if attack_profile == null:
		return TorpedoSafeRunDistanceResult.failed(&"invalid_profile")
	var arming_distance := DEFAULT_ARMING_DISTANCE_M
	if torpedo_data != null:
		arming_distance = maxf(torpedo_data.arming_distance_m, 0.0)
	var collision_margin := 0.0
	if target_ship != null and is_instance_valid(target_ship):
		collision_margin = target_ship.get_torpedo_collision_margin_m(
			attack_direction
		)
	var prediction_error := prediction_error_margin(
		target_velocity.length(),
		prediction_refresh_interval_sec,
		attack_profile.prediction_error_safety_factor
	)
	var gravity := gravity_mps2
	if gravity <= 0.0:
		gravity = float(ProjectSettings.get_setting(
			"physics/3d/default_gravity",
			9.8
		))
	var horizontal_release_speed := Vector2(
		expected_release_velocity.x,
		expected_release_velocity.z
	).length()
	if horizontal_release_speed <= 0.01:
		horizontal_release_speed = attack_profile.attack_run_speed_mps
	var fall_time := airborne_fall_time_sec(
		attack_profile.release_altitude_m,
		downward_release_speed_mps,
		gravity
	)
	var airborne_travel := horizontal_release_speed * fall_time
	var result := compose(
		arming_distance,
		collision_margin,
		prediction_error,
		attack_profile.additional_arming_margin_m,
		airborne_travel,
		attack_profile.minimum_preferred_torpedo_run_distance_m,
		attack_profile.maximum_preferred_torpedo_run_distance_m
	)
	result.airborne_fall_time_sec = fall_time
	result.horizontal_release_speed_mps = horizontal_release_speed
	result.downward_release_speed_mps = maxf(
		downward_release_speed_mps,
		0.0
	)
	return result


static func prediction_error_margin(
		target_speed_mps: float,
		prediction_refresh_interval_sec: float,
		safety_factor: float
) -> float:
	return maxf(target_speed_mps, 0.0) \
		* maxf(prediction_refresh_interval_sec, 0.0) \
		* maxf(safety_factor, 0.0)


static func airborne_travel_distance(
		release_speed_mps: float,
		release_altitude_m: float,
		gravity_mps2: float,
		downward_release_speed_mps: float = 0.0
) -> float:
	# Horizontal distance covered during the ballistic fall from the release
	# altitude to the water. The torpedo keeps its forward speed while falling,
	# so this scales with both drop speed and fall time.
	var fall_time := airborne_fall_time_sec(
		release_altitude_m,
		downward_release_speed_mps,
		gravity_mps2
	)
	return maxf(release_speed_mps, 0.0) * fall_time


static func airborne_fall_time_sec(
		release_altitude_m: float,
		downward_release_speed_mps: float,
		gravity_mps2: float
) -> float:
	# TorpedoProjectile inherits the aircraft velocity and the weapon controller
	# clamps its initial Y velocity to at least this downward release speed.
	var height := maxf(release_altitude_m, 0.0)
	var downward_speed := maxf(downward_release_speed_mps, 0.0)
	var gravity := maxf(gravity_mps2, 0.01)
	if height <= 0.0:
		return 0.0
	return (
		-downward_speed
		+ sqrt(
			downward_speed * downward_speed
				+ 2.0 * gravity * height
		)
	) / gravity


static func compose(
		arming_distance_m: float,
		collision_margin_m: float,
		prediction_error_margin_m: float,
		additional_safety_margin_m: float,
		airborne_travel_margin_m: float,
		minimum_preferred_run_distance_m: float,
		maximum_preferred_run_distance_m: float
) -> TorpedoSafeRunDistanceResult:
	var result := TorpedoSafeRunDistanceResult.new()
	result.arming_distance_m = maxf(arming_distance_m, 0.0)
	result.collision_margin_m = maxf(collision_margin_m, 0.0)
	result.prediction_error_margin_m = maxf(prediction_error_margin_m, 0.0)
	result.additional_safety_margin_m = maxf(additional_safety_margin_m, 0.0)
	result.airborne_travel_margin_m = maxf(airborne_travel_margin_m, 0.0)
	# Underwater run (water-entry -> centre) needed for the torpedo to clear its
	# arming distance before the hull, with the hull-surface gap and the
	# prediction/head-room margins folded in.
	result.minimum_safe_run_distance_m = (
		result.arming_distance_m
		+ result.collision_margin_m
		+ result.prediction_error_margin_m
		+ result.additional_safety_margin_m
	)
	var preferred := maxf(
		result.minimum_safe_run_distance_m,
		maxf(minimum_preferred_run_distance_m, 0.0)
	)
	if maximum_preferred_run_distance_m > 0.0:
		# A ceiling that would starve the arming requirement is a hard failure
		# rather than a silent unsafe release.
		if maximum_preferred_run_distance_m + 0.01 \
				< result.minimum_safe_run_distance_m:
			result.success = false
			result.failure_reason = \
				&"preferred_run_distance_below_arming_requirement"
			result.preferred_run_distance_m = maximum_preferred_run_distance_m
			return result
		preferred = minf(preferred, maximum_preferred_run_distance_m)
	result.preferred_run_distance_m = preferred
	result.release_offset_from_center_m = \
		result.airborne_travel_margin_m + preferred
	result.underwater_run_to_hull_m = maxf(
		preferred - result.collision_margin_m,
		0.0
	)
	result.success = true
	return result

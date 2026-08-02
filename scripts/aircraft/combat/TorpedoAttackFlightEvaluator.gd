extends RefCounted
class_name TorpedoAttackFlightEvaluator

# Pure attack-run judgments extracted from TorpedoAttackController: heading
# alignment, attack-run progress, the release grace window, and the per-aircraft
# release envelope (altitude, speed, heading, longitudinal + lateral position).
# Stateless so it can be shared and unit-tested in isolation.

const EPSILON := 0.0001


func is_heading_aligned(
		forward: Vector3,
		attack_direction: Vector3,
		tolerance_deg: float
) -> bool:
	var flat := forward
	flat.y = 0.0
	if flat.length_squared() <= EPSILON:
		return false
	return rad_to_deg(flat.angle_to(attack_direction)) <= tolerance_deg


func run_progress(
		formation_center: Vector3,
		entry_point: Vector3,
		attack_direction: Vector3
) -> float:
	return (formation_center - entry_point).dot(attack_direction)


func required_progress(
		release_point: Vector3,
		entry_point: Vector3,
		attack_direction: Vector3
) -> float:
	return (release_point - entry_point).dot(attack_direction)


func has_reached_release_line(
		formation_center: Vector3,
		command: TorpedoAttackCommand,
		release_point_tolerance_m: float
) -> bool:
	var progress := run_progress(
		formation_center,
		command.entry_point,
		command.attack_direction
	)
	var required := required_progress(
		command.actual_release_point,
		command.entry_point,
		command.attack_direction
	)
	return progress + release_point_tolerance_m >= required


func is_release_window_missed(
		formation_center: Vector3,
		release_point: Vector3,
		attack_direction: Vector3,
		grace_distance_m: float
) -> bool:
	return (formation_center - release_point).dot(attack_direction) \
		>= grace_distance_m


func meets_release_envelope(
		aircraft: AircraftUnit,
		command: TorpedoAttackCommand,
		profile: TorpedoAttackProfile,
		formation_spacing_m: float,
		aircraft_count: int
) -> bool:
	var altitude := aircraft.global_position.y - command.command_plane_height_m
	if altitude < profile.release_altitude_m - 2.0 \
			or altitude > profile.maximum_release_altitude_m:
		return false
	var speed := aircraft.get_world_velocity().length()
	if speed < profile.minimum_release_speed_mps \
			or speed > profile.maximum_release_speed_mps:
		return false
	var forward := aircraft.get_forward_direction()
	forward.y = 0.0
	if forward.length_squared() <= EPSILON \
			or rad_to_deg(forward.angle_to(command.attack_direction)) \
				> profile.alignment_tolerance_deg:
		return false
	var release_offset := aircraft.global_position - command.actual_release_point
	release_offset.y = 0.0
	if absf(release_offset.dot(command.attack_direction)) \
			> profile.release_point_tolerance_m:
		return false
	# Lateral gate: reject aircraft that have drifted grossly off the attack
	# centreline while keeping the limit wider than the formation spread so
	# normal in-formation offsets still release.
	var lateral_axis := command.attack_direction.cross(Vector3.UP)
	if lateral_axis.length_squared() > EPSILON:
		var formation_half_width := maxf(formation_spacing_m, 0.0) \
			* maxf(float(aircraft_count), 1.0)
		var lateral_limit := maxf(
			profile.release_point_tolerance_m,
			formation_half_width
		)
		if absf(release_offset.dot(lateral_axis.normalized())) > lateral_limit:
			return false
	return true

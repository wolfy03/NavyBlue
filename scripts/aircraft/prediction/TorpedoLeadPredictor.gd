extends RefCounted
class_name TorpedoLeadPredictor

# Predicts where a moving target ship will be at the moment the torpedo actually
# reaches it, so the attack leads the target instead of aiming at its stale
# command-time position. The lead accounts for the full timeline:
#   aircraft flight to the drop point  +  torpedo water-entry fall  +
#   torpedo underwater run to the ship.
#
# Pure math: no nodes, scenes, or signals. The core `predict_impact` is static
# and takes primitives so it can be unit-tested without instantiating a scene.
# When the target is stationary the predicted position equals the current
# position, so existing (working) attack geometry is preserved exactly.

const MAX_ITERATIONS := 5
const CONVERGENCE_M := 5.0
const MAX_PREDICTION_TIME_SEC := 120.0


static func predict_impact(
		formation_center: Vector3,
		aircraft_speed_mps: float,
		target_position: Vector3,
		target_velocity: Vector3,
		release_altitude_m: float,
		gravity_mps2: float,
		torpedo_run_time_sec: float = 0.0
) -> Vector3:
	var flat_velocity := target_velocity
	flat_velocity.y = 0.0
	if flat_velocity.length_squared() <= 0.0001:
		return target_position
	var speed := maxf(aircraft_speed_mps, 1.0)
	var water_entry_time := sqrt(
		2.0 * maxf(release_altitude_m, 0.0) / maxf(gravity_mps2, 0.01)
	)
	var fixed_time := water_entry_time + maxf(torpedo_run_time_sec, 0.0)
	var predicted := target_position
	for _iteration in MAX_ITERATIONS:
		var aircraft_distance := formation_center.distance_to(predicted)
		var total_time := minf(
			aircraft_distance / speed + fixed_time,
			MAX_PREDICTION_TIME_SEC
		)
		var next_predicted := target_position + flat_velocity * total_time
		next_predicted.y = target_position.y
		if next_predicted.distance_to(predicted) <= CONVERGENCE_M:
			return next_predicted
		predicted = next_predicted
	return predicted


static func torpedo_run_time(
		run_distance_m: float,
		launch_speed_mps: float,
		max_speed_mps: float,
		acceleration_mps2: float
) -> float:
	# Time for the torpedo to cover `run_distance_m` underwater. It enters the
	# water at launch speed and accelerates toward its top speed (see
	# TorpedoProjectile._physics_process), so the run is an accelerating phase
	# followed by a cruise at top speed.
	var distance := maxf(run_distance_m, 0.0)
	if distance <= 0.0:
		return 0.0
	var launch_speed := maxf(launch_speed_mps, 0.01)
	var top_speed := maxf(max_speed_mps, launch_speed)
	if acceleration_mps2 <= 0.0 or top_speed <= launch_speed:
		return distance / launch_speed
	var time_to_top := (top_speed - launch_speed) / acceleration_mps2
	var accel_distance := launch_speed * time_to_top \
		+ 0.5 * acceleration_mps2 * time_to_top * time_to_top
	if distance <= accel_distance:
		# Solve distance = v0*t + 0.5*a*t^2 for t.
		return (
			-launch_speed
			+ sqrt(
				launch_speed * launch_speed
				+ 2.0 * acceleration_mps2 * distance
			)
		) / acceleration_mps2
	return time_to_top + (distance - accel_distance) / top_speed


func predict_impact_position(
		squadron: AircraftSquadron,
		target_ship: ShipUnit,
		profile: TorpedoAttackProfile,
		torpedo_run_distance_m: float = 0.0,
		torpedo_data: TorpedoProjectileData = null
) -> Vector3:
	if squadron == null or not is_instance_valid(squadron) \
			or target_ship == null or not is_instance_valid(target_ship) \
			or profile == null:
		return target_ship.global_position \
			if target_ship != null and is_instance_valid(target_ship) \
			else Vector3.ZERO
	var aircraft_speed := maxf(
		squadron.squadron_data.aircraft_data.cruise_speed_mps,
		1.0
	)
	var gravity := float(ProjectSettings.get_setting(
		"physics/3d/default_gravity",
		9.8
	))
	var run_time := 0.0
	if torpedo_data != null and torpedo_run_distance_m > 0.0:
		run_time = torpedo_run_time(
			torpedo_run_distance_m,
			torpedo_data.launch_speed_mps,
			torpedo_data.max_speed_mps,
			torpedo_data.acceleration_mps2
		)
	return predict_impact(
		squadron.formation_center,
		aircraft_speed,
		target_ship.global_position,
		target_ship.get_world_velocity(),
		profile.release_altitude_m,
		gravity,
		run_time
	)

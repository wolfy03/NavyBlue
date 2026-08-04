extends RefCounted
class_name DiveBombBallistics
## Single source of truth for bomb release ballistics.
##
## The attack resolver, the release-time impact check, the debug visualisation
## and the unit tests all call these functions, so prediction can never drift
## from what AircraftWeaponController actually launches. Pure math: no Node,
## SceneTree, Time or singleton access.

const EPSILON := 0.0001


## Mirrors AircraftWeaponController._spawn_projectile exactly: the bomb
## inherits the aircraft's world velocity, and its vertical component is forced
## to at least the weapon's downward release speed. Any change there must
## change here.
static func resolve_bomb_initial_velocity(
		aircraft_velocity: Vector3,
		weapon_data: AircraftWeaponData
) -> Vector3:
	var velocity := aircraft_velocity
	if not velocity.is_finite():
		velocity = Vector3.ZERO
	var downward_speed := maxf(
		weapon_data.downward_release_speed_mps if weapon_data != null else 0.0,
		0.0
	)
	velocity.y = minf(velocity.y, -downward_speed)
	return velocity


## Effective gravity for the bomb, including the projectile's gravity scale.
## Matches Projectile.get_effective_gravity_mps2.
static func resolve_bomb_gravity(
		weapon_data: AircraftWeaponData,
		world_gravity_mps2: float
) -> float:
	var shell_data := weapon_data.projectile_data as ShellProjectileData \
		if weapon_data != null else null
	var scale := shell_data.gravity_scale if shell_data != null else 1.0
	return maxf(world_gravity_mps2, 0.0) * maxf(scale, 0.0)


## Time for a bomb released at `release_height_m` above the target plane, with
## vertical velocity `initial_vertical_velocity` (negative is downward), to
## reach that plane. Returns -1.0 when it never does.
##
## Solves release_height + v*t - 0.5*g*t^2 = 0 for the positive root, which is
## the same integration Projectile._physics_process performs.
static func solve_fall_time(
		release_height_m: float,
		initial_vertical_velocity: float,
		gravity_mps2: float
) -> float:
	if release_height_m <= 0.0:
		return 0.0
	if gravity_mps2 <= EPSILON:
		# No gravity: only a downward velocity can ever reach the plane.
		if initial_vertical_velocity >= -EPSILON:
			return -1.0
		return release_height_m / absf(initial_vertical_velocity)
	var discriminant := initial_vertical_velocity * initial_vertical_velocity \
		+ 2.0 * gravity_mps2 * release_height_m
	if discriminant < 0.0:
		return -1.0
	var root := sqrt(discriminant)
	# Positive root of -0.5*g*t^2 + v*t + h = 0.
	var fall_time := (initial_vertical_velocity + root) / gravity_mps2
	return fall_time if fall_time >= 0.0 else -1.0


## Where a bomb released with this state crosses the target plane. Used both to
## plan a release point and to re-check the solution at the moment of release.
static func predict_impact_from_release_state(
		release_position: Vector3,
		release_velocity: Vector3,
		target_plane_y: float,
		weapon_data: AircraftWeaponData,
		world_gravity_mps2: float
) -> Vector3:
	var gravity := resolve_bomb_gravity(weapon_data, world_gravity_mps2)
	var height := release_position.y - target_plane_y
	var fall_time := solve_fall_time(height, release_velocity.y, gravity)
	if fall_time < 0.0:
		return Vector3(INF, INF, INF)
	var impact := release_position + Vector3(
		release_velocity.x,
		0.0,
		release_velocity.z
	) * fall_time
	impact.y = target_plane_y
	return impact


## Inverse of the above: the release point whose bomb lands on
## `impact_position`, given the horizontal velocity the bomb will carry.
static func solve_release_position_for_impact(
		impact_position: Vector3,
		release_altitude_above_target_m: float,
		bomb_horizontal_velocity: Vector3,
		bomb_vertical_velocity: float,
		target_plane_y: float,
		gravity_mps2: float
) -> Vector3:
	var fall_time := solve_fall_time(
		release_altitude_above_target_m,
		bomb_vertical_velocity,
		gravity_mps2
	)
	if fall_time < 0.0:
		return Vector3(INF, INF, INF)
	var flat_velocity := Vector3(
		bomb_horizontal_velocity.x,
		0.0,
		bomb_horizontal_velocity.z
	)
	var release := impact_position - flat_velocity * fall_time
	release.y = target_plane_y + release_altitude_above_target_m
	return release


static func is_finite_vector(value: Vector3) -> bool:
	return value.is_finite()

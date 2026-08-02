extends RefCounted
class_name TorpedoAttackPlanner

# Below this target speed (m/s, squared) the ship's facing is used for the beam
# axis; above it the actual velocity heading is preferred.
const MINIMUM_HEADING_SPEED_SQ := 4.0

static var _next_tracking_id := 1

var _resolver := TorpedoAttackCommandResolver.new()
var _lead_predictor := TorpedoLeadPredictor.new()
var _safe_run_resolver := TorpedoSafeRunDistanceResolver.new()


func plan_attack(
		squadron: AircraftSquadron,
		target_ship: ShipUnit,
		battle_environment: BattleEnvironment = null,
		predict_lead: bool = false,
		prediction_refresh_interval_sec: float = 0.0
) -> TorpedoAttackResolveResult:
	if squadron == null or not is_instance_valid(squadron):
		return TorpedoAttackResolveResult.failed(&"invalid_squadron")
	if target_ship == null or not is_instance_valid(target_ship) \
			or not target_ship.is_valid_attack_target_for(
				squadron.get_team()
			):
		return TorpedoAttackResolveResult.failed(&"invalid_target")
	var profile := squadron.get_torpedo_attack_profile()
	if profile == null:
		return TorpedoAttackResolveResult.failed(&"invalid_profile")
	var torpedo_data := _get_torpedo_data(squadron)
	var weapon_data := squadron.get_aircraft_weapon_data()
	if torpedo_data == null or weapon_data == null:
		return TorpedoAttackResolveResult.failed(&"invalid_torpedo_data")
	var target_velocity := target_ship.get_world_velocity()
	target_velocity.y = 0.0
	# Head-on axis (squadron -> target) only drives which beam is the near side;
	# the precise lead is recomputed per candidate direction below.
	var to_target := target_ship.global_position - squadron.formation_center
	to_target.y = 0.0
	if to_target.length_squared() <= 0.0001:
		to_target = squadron.get_formation_forward()
		to_target.y = 0.0
	if to_target.length_squared() <= 0.0001:
		return TorpedoAttackResolveResult.failed(&"direction_unavailable")
	to_target = to_target.normalized()
	var last_failure: StringName = &"no_valid_attack_geometry"
	var last_disposition := \
		TorpedoAttackResolveResult.FailureDisposition.RETRYABLE
	# Try a flank (beam) run first, then the opposite beam, then a head-on run.
	# The first geometry the resolver accepts (safe distance + min run + bounds)
	# wins.
	for direction in _attack_direction_candidates(target_ship, to_target):
		# ALIGNING applies the same run speed through the named movement override,
		# and ATTACK_RUN drives every aircraft at this exact horizontal speed.
		var expected_release_velocity := direction \
			* profile.attack_run_speed_mps
		var safe := _safe_run_resolver.resolve(
			torpedo_data,
			target_ship,
			profile,
			direction,
			target_velocity,
			prediction_refresh_interval_sec,
			expected_release_velocity,
			weapon_data.downward_release_speed_mps
		)
		if not safe.success:
			last_failure = safe.failure_reason
			last_disposition = _classify_failure(last_failure)
			continue
		# Predicted target centre at the moment the torpedo arrives. The lead
		# spans aircraft approach + water-entry fall + the armed underwater run
		# to the hull. Stationary/disabled -> current position.
		var impact_point := target_ship.global_position
		if predict_lead:
			impact_point = _lead_predictor.predict_impact_position(
				squadron,
				target_ship,
				profile,
				safe.underwater_run_to_hull_m,
				torpedo_data
			)
		# The predicted centre is where the torpedo must END UP. Release it short
		# by the airborne travel plus the armed underwater run so it clears its
		# arming distance before the hull instead of splashing down on the ship.
		var release_point := impact_point \
			- direction * safe.release_offset_from_center_m
		var entry_point := release_point \
			- direction * profile.minimum_attack_run_distance_m
		var result := _resolver.resolve(
			squadron,
			entry_point,
			release_point,
			profile,
			battle_environment,
			target_ship
		)
		if result.success:
			_annotate_command(result.command, impact_point, direction, safe)
			return result
		last_failure = result.failure_reason
		last_disposition = _classify_failure(last_failure)
	return TorpedoAttackResolveResult.failed(
		last_failure,
		last_disposition
	)


func _annotate_command(
		command: TorpedoAttackCommand,
		impact_point: Vector3,
		direction: Vector3,
		safe: TorpedoSafeRunDistanceResult
) -> void:
	if command == null:
		return
	command.predicted_impact_position = impact_point
	command.predicted_collision_point = impact_point \
		- direction * safe.collision_margin_m
	command.torpedo_safe_run_distance_m = safe.underwater_run_to_hull_m
	command.arming_distance_m = safe.arming_distance_m
	command.collision_margin_m = safe.collision_margin_m
	command.prediction_error_margin_m = safe.prediction_error_margin_m
	command.tracking_id = _allocate_tracking_id()
	command.solution_revision = 0
	command.solution_locked = false


func _get_torpedo_data(squadron: AircraftSquadron) -> TorpedoProjectileData:
	var weapon_data := squadron.get_aircraft_weapon_data()
	if weapon_data == null:
		return null
	return weapon_data.projectile_data as TorpedoProjectileData


func _attack_direction_candidates(
		target_ship: ShipUnit,
		head_on_direction: Vector3
) -> Array[Vector3]:
	# Prefer running perpendicular to the target's heading so torpedoes cross its
	# path. Approach from the beam nearest the squadron, fall back to the far
	# beam, then to a head-on run.
	var candidates: Array[Vector3] = []
	var target_forward := -target_ship.global_transform.basis.z
	target_forward.y = 0.0
	var target_velocity := target_ship.get_world_velocity()
	target_velocity.y = 0.0
	if target_velocity.length_squared() >= MINIMUM_HEADING_SPEED_SQ:
		target_forward = target_velocity
	var near_beam := select_beam_direction(target_forward, head_on_direction)
	if near_beam.length_squared() > 0.0001:
		candidates.append(near_beam)
		candidates.append(-near_beam)
	candidates.append(head_on_direction)
	return candidates


static func select_beam_direction(
		target_forward: Vector3,
		head_on_direction: Vector3
) -> Vector3:
	# Beam axis: perpendicular to the target heading, on the side the squadron is
	# approaching from. Returns Vector3.ZERO when the heading is degenerate.
	var forward := target_forward
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		return Vector3.ZERO
	forward = forward.normalized()
	var lateral := forward.cross(Vector3.UP)
	if lateral.length_squared() <= 0.0001:
		return Vector3.ZERO
	lateral = lateral.normalized()
	return lateral if lateral.dot(head_on_direction) >= 0.0 else -lateral


static func _allocate_tracking_id() -> int:
	var tracking_id := _next_tracking_id
	_next_tracking_id += 1
	if _next_tracking_id <= 0:
		_next_tracking_id = 1
	return tracking_id


static func _classify_failure(
		reason: StringName
) -> TorpedoAttackResolveResult.FailureDisposition:
	if reason in [
		&"no_valid_attack_geometry",
		&"outside_battle_area",
		&"insufficient_attack_space",
		&"target_snapshot_unavailable",
	]:
		return TorpedoAttackResolveResult.FailureDisposition.RETRYABLE
	return TorpedoAttackResolveResult.FailureDisposition.FATAL

extends RefCounted
class_name AircraftTorpedoReleaseService

# Owns the actual torpedo release for a squadron: it filters surviving aircraft,
# checks payload, verifies the release envelope through the flight evaluator,
# builds the typed launch request, and asks the aircraft weapon controller to
# create the projectile. Payload is consumed by the weapon controller only when
# a projectile is successfully created; this service never mutates controller
# state, it just reports what happened.

var _creation_attempts: Dictionary = {}


func reset() -> void:
	_creation_attempts.clear()


func release_ready_aircraft(
		squadron: AircraftSquadron,
		command: TorpedoAttackCommand,
		profile: TorpedoAttackProfile,
		evaluator: TorpedoAttackFlightEvaluator,
		resolved_ids: Dictionary
) -> AircraftTorpedoReleaseResult:
	var result := AircraftTorpedoReleaseResult.new()
	if squadron == null or command == null or profile == null \
			or evaluator == null:
		return result
	var formation_spacing_m := squadron.squadron_data.formation_spacing_m
	var aircraft_count := squadron.squadron_data.aircraft_count
	for aircraft in squadron.get_alive_aircraft():
		var id := aircraft.get_instance_id()
		if resolved_ids.has(id) or id in result.resolved_aircraft_ids:
			continue
		var weapon := aircraft.weapon_controller
		var permanent_reason := _get_permanent_failure_reason(weapon)
		if not permanent_reason.is_empty():
			result.resolved_aircraft_ids.append(id)
			_add_failure(result, id, permanent_reason, false)
			continue
		if not evaluator.meets_release_envelope(
			aircraft,
			command,
			profile,
			formation_spacing_m,
			aircraft_count
		):
			continue
		result.attempted += 1
		var request := AirDroppedTorpedoLaunchRequest.new()
		request.source_aircraft = aircraft
		request.source_squadron = squadron
		request.launch_position = aircraft \
			.get_payload_release_transform().origin
		request.launch_direction = command.attack_direction
		request.aircraft_velocity = aircraft.get_world_velocity()
		request.target_point = command.escape_point
		# The target can sink mid-run; the drop still completes, just without a
		# tracked ship reference.
		request.target_ship = command.get_live_target_ship()
		request.torpedo_data = weapon.weapon_data.projectile_data \
			as TorpedoProjectileData
		request.command_id = command.command_id
		var release_result := weapon.release_air_dropped_torpedo(request)
		if release_result.success:
			_creation_attempts.erase(id)
			result.released += 1
			result.released_aircraft_ids.append(id)
			result.resolved_aircraft_ids.append(id)
		else:
			result.failed += 1
			var attempts := int(_creation_attempts.get(id, 0)) + 1
			_creation_attempts[id] = attempts
			var retryable := _is_retryable_failure(
				release_result.failure_reason
			) and attempts <= maxi(
				profile.maximum_projectile_creation_retries,
				0
			)
			_add_failure(
				result,
				id,
				release_result.failure_reason,
				retryable,
				attempts
			)
			if not retryable:
				result.resolved_aircraft_ids.append(id)
	return result


func get_creation_attempt_count(aircraft_id: int) -> int:
	return int(_creation_attempts.get(aircraft_id, 0))


func _get_permanent_failure_reason(
		weapon: AircraftWeaponController
) -> StringName:
	if weapon == null:
		return &"missing_weapon_controller"
	if weapon.weapon_data == null:
		return &"missing_weapon_data"
	if weapon.weapon_data.weapon_type \
			!= AircraftWeaponData.WeaponType.TORPEDO:
		return &"not_torpedo_weapon"
	if not weapon.has_ammunition():
		return &"no_ammunition"
	if not weapon.weapon_data.projectile_data is TorpedoProjectileData \
			or weapon.weapon_data.projectile_scene == null:
		return &"invalid_projectile_data"
	return StringName()


func _is_retryable_failure(reason: StringName) -> bool:
	return reason in [
		&"release_unavailable",
		&"spawn_failed",
		&"projectile_creation_failed",
	]


func _add_failure(
		result: AircraftTorpedoReleaseResult,
		aircraft_id: int,
		reason: StringName,
		retryable: bool,
		attempt_count: int = 0
) -> void:
	result.failure_reasons.append(reason)
	result.failures.append(AircraftTorpedoReleaseFailure.create(
		aircraft_id,
		reason,
		retryable,
		attempt_count
	))

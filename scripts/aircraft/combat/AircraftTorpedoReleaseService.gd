extends RefCounted
class_name AircraftTorpedoReleaseService

# Owns the actual torpedo release for a squadron: it filters surviving aircraft,
# checks payload, verifies the release envelope through the flight evaluator,
# builds the typed launch request, and asks the aircraft weapon controller to
# create the projectile. Payload is consumed by the weapon controller only when
# a projectile is successfully created; this service never mutates controller
# state, it just reports what happened.


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
		if weapon == null or weapon.weapon_data == null \
				or weapon.weapon_data.weapon_type \
					!= AircraftWeaponData.WeaponType.TORPEDO \
				or not weapon.has_ammunition():
			result.resolved_aircraft_ids.append(id)
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
		request.target_ship = command.target_ship
		request.torpedo_data = weapon.weapon_data.projectile_data \
			as TorpedoProjectileData
		request.command_id = command.command_id
		var release_result := weapon.release_air_dropped_torpedo(request)
		if release_result.success:
			result.released += 1
			result.released_aircraft_ids.append(id)
			result.resolved_aircraft_ids.append(id)
		else:
			result.failed += 1
			result.failure_reasons.append(release_result.failure_reason)
	return result

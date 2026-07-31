extends RefCounted
class_name SquadronPresentationSnapshotBuilder


func build(
		squadron: AircraftSquadron
) -> SquadronPresentationSnapshot:
	if squadron == null or not is_instance_valid(squadron):
		return SquadronPresentationSnapshot.new()
	var alive := squadron.get_alive_aircraft()
	var health_total := 0.0
	var speed_total := 0.0
	for aircraft in alive:
		if aircraft.health != null:
			health_total += aircraft.health.current_health \
				/ maxf(aircraft.health.maximum_health, 1.0)
		speed_total += aircraft.velocity.length()
	return build_from_aggregate(
		squadron,
		alive.size(),
		health_total,
		speed_total,
		squadron.get_destination_snapshot()
	)


func build_from_aggregate(
		squadron: AircraftSquadron,
		alive_count: int,
		health_total: float,
		speed_total: float,
		destination: SquadronDestinationSnapshot
) -> SquadronPresentationSnapshot:
	var snapshot := SquadronPresentationSnapshot.new()
	if squadron == null or not is_instance_valid(squadron):
		return snapshot
	var data := squadron.squadron_data
	snapshot.display_name = data.display_name \
		if data != null and not data.display_name.is_empty() \
		else squadron.name
	var role := squadron.get_aircraft_role()
	snapshot.role_name = AircraftData.AircraftRole.keys()[
		int(role)
	].capitalize()
	snapshot.state_name = AircraftSquadron.State.keys()[
		int(squadron.state)
	]
	snapshot.alive_count = alive_count
	snapshot.total_count = squadron.get_sortie_aircraft_count()
	if alive_count > 0:
		snapshot.average_health_ratio = health_total \
			/ float(alive_count)
		snapshot.average_speed_mps = speed_total \
			/ float(alive_count)
	var weapon_data := squadron.get_aircraft_weapon_data()
	snapshot.weapon_name = weapon_data.display_name \
		if weapon_data != null \
		and not weapon_data.display_name.is_empty() else "Unarmed"
	snapshot.ammunition_count = squadron \
		.get_total_remaining_ammunition()
	snapshot.mission_name = _resolve_mission_name(
		squadron,
		destination
	)
	return snapshot


func _resolve_mission_name(
		squadron: AircraftSquadron,
		destination: SquadronDestinationSnapshot
) -> String:
	var mission_id := squadron.get_current_mission_id()
	if not mission_id.is_empty():
		return mission_id
	if destination != null and destination.command_type == &"player_move":
		return "Player move"
	if destination != null and destination.loitering:
		return "Loiter"
	if squadron.state == AircraftSquadron.State.RETURNING:
		return "Return"
	return "None"

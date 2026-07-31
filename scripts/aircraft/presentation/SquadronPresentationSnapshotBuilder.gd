extends RefCounted
class_name SquadronPresentationSnapshotBuilder


func build(
		squadron: AircraftSquadron
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
	var alive := squadron.get_alive_aircraft()
	snapshot.alive_count = alive.size()
	snapshot.total_count = squadron.get_sortie_aircraft_count()
	var health_total := 0.0
	var speed_total := 0.0
	for aircraft in alive:
		if aircraft.health != null:
			health_total += aircraft.health.current_health \
				/ maxf(aircraft.health.maximum_health, 1.0)
		speed_total += aircraft.velocity.length()
	if not alive.is_empty():
		snapshot.average_health_ratio = health_total \
			/ float(alive.size())
		snapshot.average_speed_mps = speed_total \
			/ float(alive.size())
	var weapon_data := squadron.get_aircraft_weapon_data()
	snapshot.weapon_name = weapon_data.display_name \
		if weapon_data != null \
		and not weapon_data.display_name.is_empty() else "Unarmed"
	snapshot.ammunition_count = squadron \
		.get_total_remaining_ammunition()
	snapshot.mission_name = _resolve_mission_name(squadron)
	return snapshot


func _resolve_mission_name(squadron: AircraftSquadron) -> String:
	var mission_id := squadron.get_current_mission_id()
	if not mission_id.is_empty():
		return mission_id
	var destination := squadron.get_destination_snapshot()
	if destination.command_type == &"player_move":
		return "Player move"
	if destination.loitering:
		return "Loiter"
	if squadron.state == AircraftSquadron.State.RETURNING:
		return "Return"
	return "None"

extends RefCounted
class_name SquadronPresentationFrameBuilder

var snapshot_builder := SquadronPresentationSnapshotBuilder.new()


func build(
		squadron: AircraftSquadron,
		settings: AircraftCommandPresentationSettings
) -> SquadronPresentationFrame:
	var frame := SquadronPresentationFrame.new()
	if squadron == null or not is_instance_valid(squadron):
		return frame
	var alive := squadron.get_alive_aircraft()
	frame.alive_aircraft_count = alive.size()
	frame.destination = squadron.get_destination_snapshot()
	var minimum_size := settings.minimum_box_size_m \
		if settings != null else Vector3(80.0, 30.0, 80.0)
	var padding := settings.bounds_padding_m \
		if settings != null else Vector3.ZERO
	var health_total := 0.0
	var speed_total := 0.0
	if alive.is_empty():
		frame.bounds = AABB(
			squadron.formation_center - minimum_size * 0.5,
			minimum_size
		)
	else:
		var minimum := alive[0].global_position
		var maximum := minimum
		for aircraft in alive:
			minimum = minimum.min(aircraft.global_position)
			maximum = maximum.max(aircraft.global_position)
			if aircraft.health != null:
				health_total += aircraft.health.current_health \
					/ maxf(aircraft.health.maximum_health, 1.0)
			speed_total += aircraft.velocity.length()
		minimum -= padding
		maximum += padding
		frame.bounds = AABB(minimum, maximum - minimum)
	frame.snapshot = snapshot_builder.build_from_aggregate(
		squadron,
		alive.size(),
		health_total,
		speed_total,
		frame.destination
	)
	return frame

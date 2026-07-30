extends RefCounted
class_name AircraftPayloadReleaseContext

var target_position := Vector3.ZERO
var target_velocity := Vector3.ZERO


static func create(
		next_target_position: Vector3,
		next_target_velocity: Vector3
) -> AircraftPayloadReleaseContext:
	var context := AircraftPayloadReleaseContext.new()
	context.target_position = next_target_position
	context.target_velocity = next_target_velocity
	return context

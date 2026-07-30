extends RefCounted
class_name AircraftPayloadReleaseRequestResult

enum Status {
	QUEUED,
	ALREADY_PENDING,
	ALREADY_RELEASED,
	RETRYABLE,
	NO_AMMUNITION,
	NO_WEAPON_CONTROLLER,
	WEAPON_DISABLED,
	INVALID_AIRCRAFT,
}

var status: Status = Status.INVALID_AIRCRAFT
var request_id := -1
var aircraft_id := 0


static func create(
		next_status: Status,
		next_aircraft_id: int = 0,
		next_request_id: int = -1
) -> AircraftPayloadReleaseRequestResult:
	var result := AircraftPayloadReleaseRequestResult.new()
	result.status = next_status
	result.aircraft_id = next_aircraft_id
	result.request_id = next_request_id
	return result

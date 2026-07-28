extends RefCounted
class_name SquadronRuntimeState

enum AvailabilityState {
	READY,
	LAUNCHING,
	ACTIVE,
	RETURNING,
	REARMING,
	DESTROYED,
}

var squadron_id: String = ""
var availability_state: AvailabilityState = AvailabilityState.READY
var total_aircraft := 0
var available_aircraft := 0
var active_aircraft := 0
var lost_aircraft := 0
var rearm_time_left := 0.0


func normalize() -> void:
	total_aircraft = maxi(total_aircraft, 0)
	lost_aircraft = clampi(lost_aircraft, 0, total_aircraft)
	active_aircraft = clampi(
		active_aircraft,
		0,
		total_aircraft - lost_aircraft
	)
	available_aircraft = clampi(
		available_aircraft,
		0,
		total_aircraft - lost_aircraft - active_aircraft
	)
	rearm_time_left = maxf(rearm_time_left, 0.0)
	if total_aircraft <= 0 \
			or available_aircraft + active_aircraft <= 0:
		availability_state = AvailabilityState.DESTROYED


func duplicate_state() -> SquadronRuntimeState:
	return from_dictionary(to_dictionary())


func to_dictionary() -> Dictionary:
	return {
		"squadron_id": squadron_id,
		"availability_state": int(availability_state),
		"total_aircraft": total_aircraft,
		"available_aircraft": available_aircraft,
		"active_aircraft": active_aircraft,
		"lost_aircraft": lost_aircraft,
		"rearm_time_left": rearm_time_left,
	}


static func from_dictionary(data: Dictionary) -> SquadronRuntimeState:
	var state := SquadronRuntimeState.new()
	state.squadron_id = str(data.get("squadron_id", ""))
	state.availability_state = clampi(
		int(data.get(
			"availability_state",
			AvailabilityState.READY
		)),
		AvailabilityState.READY,
		AvailabilityState.DESTROYED
	) as AvailabilityState
	state.total_aircraft = int(data.get("total_aircraft", 0))
	state.available_aircraft = int(data.get("available_aircraft", 0))
	state.active_aircraft = int(data.get("active_aircraft", 0))
	state.lost_aircraft = int(data.get("lost_aircraft", 0))
	state.rearm_time_left = float(data.get("rearm_time_left", 0.0))
	state.normalize()
	return state

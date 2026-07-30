extends RefCounted
class_name DiveReleasePolicy

enum Decision {
	WAIT,
	RELEASE,
	MISSED_WINDOW,
}


func evaluate(
		current_altitude_m: float,
		previous_altitude_m: float,
		elapsed_sec: float,
		data: DiveBomberCombatData
) -> Decision:
	if data == null:
		return Decision.MISSED_WINDOW
	if current_altitude_m < data.minimum_release_altitude_m:
		return Decision.MISSED_WINDOW
	if elapsed_sec < data.minimum_dive_time_before_release_sec:
		return Decision.WAIT
	var trigger := data.automatic_release_altitude_m
	var tolerance := maxf(data.release_altitude_tolerance_m, 0.0)
	if current_altitude_m <= trigger + tolerance:
		return Decision.RELEASE
	if previous_altitude_m > trigger and current_altitude_m < trigger:
		return Decision.RELEASE
	return Decision.WAIT

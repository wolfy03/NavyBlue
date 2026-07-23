extends RefCounted
class_name FleetThreatContext

var target_ref: WeakRef
var threat_score := 0.0
var reason: StringName
var created_time_sec := 0.0
var expires_time_sec := 0.0
var minimum_hold_sec := 0.0


func setup(
		target: ShipUnit,
		score: float,
		threat_reason: StringName,
		now_sec: float,
		hold_sec: float
) -> FleetThreatContext:
	target_ref = weakref(target)
	threat_score = score
	reason = threat_reason
	created_time_sec = now_sec
	minimum_hold_sec = hold_sec
	expires_time_sec = now_sec + hold_sec
	return self


func get_target() -> ShipUnit:
	return target_ref.get_ref() as ShipUnit if target_ref != null else null


func is_active(now_sec: float) -> bool:
	var target := get_target()
	return target != null and is_instance_valid(target) and target.is_alive() \
		and now_sec <= expires_time_sec

extends RefCounted
class_name SquadronDestinationTracker

var command_serial := 0
var reached_serial := -1


func begin_command() -> int:
	command_serial += 1
	reached_serial = -1
	return command_serial


func mark_reached(serial: int) -> void:
	if serial == command_serial:
		reached_serial = serial


func is_reached(serial: int = -1) -> bool:
	var requested_serial := command_serial if serial < 0 else serial
	return requested_serial >= 0 and reached_serial == requested_serial


func reset() -> void:
	command_serial = 0
	reached_serial = -1

extends RefCounted
class_name SquadronDestinationTracker

var command_serial := 0
var reached_serial := -1
var command_type: StringName
var active := false
var command_plane_height_m := 0.0


func begin_command(
		next_command_type: StringName = &"mission",
		next_command_plane_height_m: float = 0.0
) -> int:
	command_serial += 1
	reached_serial = -1
	command_type = next_command_type
	command_plane_height_m = next_command_plane_height_m
	active = true
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
	command_type = StringName()
	active = false
	command_plane_height_m = 0.0


func clear_active_command() -> void:
	active = false
	command_type = StringName()


func get_snapshot(
		destination: Vector3,
		loitering: bool
) -> SquadronDestinationSnapshot:
	var snapshot := SquadronDestinationSnapshot.new()
	snapshot.active = active
	snapshot.destination = destination
	snapshot.command_plane_height_m = command_plane_height_m
	snapshot.reached = is_reached()
	snapshot.loitering = loitering
	snapshot.command_type = command_type
	snapshot.command_serial = command_serial
	return snapshot


func shutdown() -> void:
	reset()

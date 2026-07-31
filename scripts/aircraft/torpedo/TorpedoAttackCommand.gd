extends RefCounted
class_name TorpedoAttackCommand

var command_id := 0
var entry_point := Vector3.ZERO
var requested_release_point := Vector3.ZERO
var actual_release_point := Vector3.ZERO
var approach_point := Vector3.ZERO
var escape_point := Vector3.ZERO
var attack_direction := Vector3.FORWARD
var requested_run_distance_m := 0.0
var actual_run_distance_m := 0.0
var minimum_run_distance_m := 0.0
var command_plane_height_m := 0.0
var target_ship: ShipUnit


func duplicate_command() -> TorpedoAttackCommand:
	var copy := TorpedoAttackCommand.new()
	copy.command_id = command_id
	copy.entry_point = entry_point
	copy.requested_release_point = requested_release_point
	copy.actual_release_point = actual_release_point
	copy.approach_point = approach_point
	copy.escape_point = escape_point
	copy.attack_direction = attack_direction
	copy.requested_run_distance_m = requested_run_distance_m
	copy.actual_run_distance_m = actual_run_distance_m
	copy.minimum_run_distance_m = minimum_run_distance_m
	copy.command_plane_height_m = command_plane_height_m
	copy.target_ship = target_ship
	return copy


func translated(offset: Vector3) -> TorpedoAttackCommand:
	var copy := duplicate_command()
	copy.entry_point += offset
	copy.requested_release_point += offset
	copy.actual_release_point += offset
	copy.approach_point += offset
	copy.escape_point += offset
	return copy

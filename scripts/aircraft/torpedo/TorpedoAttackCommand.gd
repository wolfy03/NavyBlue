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

# AI predictive-attack metadata. Left at defaults for player manual commands so
# their existing coordinate contract is untouched.
var predicted_impact_position := Vector3.ZERO
var predicted_collision_point := Vector3.ZERO
var torpedo_safe_run_distance_m := 0.0
var arming_distance_m := 0.0
var collision_margin_m := 0.0
var prediction_error_margin_m := 0.0
var tracking_id := 0
var solution_revision := 0
var solution_locked := false


## Returns the tracked target only while it is still a live instance, clearing
## the field once it has been freed.
##
## A torpedo run is deliberately not aborted once it reaches RELEASING, so the
## target can sink while the drop is still in flight. Reading the stale
## reference is harmless, but assigning it to another typed slot raises
## "Invalid assignment ... of type 'previously freed'". Every propagation of
## this field must go through here.
func get_live_target_ship() -> ShipUnit:
	# is_instance_valid alone, with no `!= null` precondition: a freed
	# reference does not reliably compare unequal to null, so guarding on that
	# first lets the stale reference through. is_instance_valid(null) is false,
	# so this covers the genuine-null case too.
	if not is_instance_valid(target_ship):
		target_ship = null
	return target_ship


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
	copy.target_ship = get_live_target_ship()
	copy.predicted_impact_position = predicted_impact_position
	copy.predicted_collision_point = predicted_collision_point
	copy.torpedo_safe_run_distance_m = torpedo_safe_run_distance_m
	copy.arming_distance_m = arming_distance_m
	copy.collision_margin_m = collision_margin_m
	copy.prediction_error_margin_m = prediction_error_margin_m
	copy.tracking_id = tracking_id
	copy.solution_revision = solution_revision
	copy.solution_locked = solution_locked
	return copy


func translated(offset: Vector3) -> TorpedoAttackCommand:
	var copy := duplicate_command()
	copy.entry_point += offset
	copy.requested_release_point += offset
	copy.actual_release_point += offset
	copy.approach_point += offset
	copy.escape_point += offset
	return copy

extends RefCounted
class_name ShipManualAimCommand

var local_azimuth_rad := 0.0
var elevation_rad := 0.0
var maximum_range_m := 0.0
# Desired firing distance along the aim bearing, taken from where the player
# clicked and clamped into the cannon's reachable range. Turrets fire at this
# distance rather than always at maximum range.
var range_m := 0.0
var clicked_world_point := Vector3.ZERO


func get_local_direction() -> Vector3:
	var horizontal_scale := cos(elevation_rad)
	return Vector3(
		sin(local_azimuth_rad) * horizontal_scale,
		sin(elevation_rad),
		-cos(local_azimuth_rad) * horizontal_scale
	).normalized()


func duplicate_command() -> ShipManualAimCommand:
	var copy := ShipManualAimCommand.new()
	copy.local_azimuth_rad = local_azimuth_rad
	copy.elevation_rad = elevation_rad
	copy.maximum_range_m = maximum_range_m
	copy.range_m = range_m
	copy.clicked_world_point = clicked_world_point
	return copy

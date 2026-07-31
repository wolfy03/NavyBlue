extends RefCounted
class_name ShipManualAimResolver


func create_command(
		ship: ShipUnit,
		world_point: Vector3
) -> ShipManualAimCommand:
	var command := ShipManualAimCommand.new()
	if ship == null or not is_instance_valid(ship):
		return command
	var local_point := ship.to_local(world_point)
	var flat_direction := Vector3(
		local_point.x,
		0.0,
		local_point.z
	)
	if flat_direction.length_squared() <= 0.0001:
		flat_direction = Vector3.FORWARD
	else:
		flat_direction = flat_direction.normalized()
	command.local_azimuth_rad = atan2(
		flat_direction.x,
		-flat_direction.z
	)
	command.clicked_world_point = world_point
	command.maximum_range_m = ship \
		.get_selected_cannon_maximum_range_m()
	return command

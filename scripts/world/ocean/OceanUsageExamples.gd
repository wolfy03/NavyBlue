extends RefCounted
class_name OceanUsageExamples


static func get_ship_water_samples(ocean: Node, front_sample: Node3D, rear_sample: Node3D, left_sample: Node3D, right_sample: Node3D) -> Dictionary:
	if ocean == null:
		return {}

	var front_height := _get_water_height(ocean, front_sample.global_position)
	var rear_height := _get_water_height(ocean, rear_sample.global_position)
	var left_height := _get_water_height(ocean, left_sample.global_position)
	var right_height := _get_water_height(ocean, right_sample.global_position)
	var center_position := (front_sample.global_position + rear_sample.global_position + left_sample.global_position + right_sample.global_position) * 0.25
	var center_surface := _get_water_surface_position(ocean, center_position)
	var surface_normal := _get_water_normal(ocean, center_position)

	return {
		"front_height": front_height,
		"rear_height": rear_height,
		"left_height": left_height,
		"right_height": right_height,
		"center_surface": center_surface,
		"surface_normal": surface_normal,
		"pitch_height_delta": front_height - rear_height,
		"roll_height_delta": right_height - left_height,
	}


static func get_projectile_water_hit(ocean: Node, previous_position: Vector3, current_position: Vector3) -> RefCounted:
	if ocean == null or not ocean.has_method(&"get_surface_intersection_hit"):
		return null
	return ocean.call(&"get_surface_intersection_hit", previous_position, current_position) as RefCounted


static func _get_water_height(ocean: Node, world_position: Vector3) -> float:
	if ocean.has_method(&"get_water_height"):
		return float(ocean.call(&"get_water_height", world_position))
	return world_position.y


static func _get_water_surface_position(ocean: Node, world_position: Vector3) -> Vector3:
	if ocean.has_method(&"get_water_surface_position"):
		return ocean.call(&"get_water_surface_position", world_position) as Vector3
	return world_position


static func _get_water_normal(ocean: Node, world_position: Vector3) -> Vector3:
	if ocean.has_method(&"get_water_normal"):
		return ocean.call(&"get_water_normal", world_position) as Vector3
	return Vector3.UP

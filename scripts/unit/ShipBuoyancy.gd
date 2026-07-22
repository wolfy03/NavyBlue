extends Node
class_name ShipBuoyancy

@export var buoyancy_enabled := false
@export var water_height := 0.0
@export var ocean_manager_group := "ocean_manager"

func apply_buoyancy(ship: Node3D) -> void:
	if ship == null:
		return
	var next_position := ship.global_position
	next_position.y = _sample_water_height(ship.global_position) if buoyancy_enabled else water_height
	ship.global_position = next_position

func _sample_water_height(world_position: Vector3) -> float:
	var ocean_manager := _get_ocean_manager()
	if ocean_manager != null and ocean_manager.has_method(&"get_ship_sample_heights"):
		var samples: Variant = ocean_manager.call(&"get_ship_sample_heights", world_position)
		if samples is Array and not samples.is_empty():
			return float(samples[0])
	return water_height

func _get_ocean_manager() -> Node:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group(ocean_manager_group)

extends RefCounted
class_name WorldPointerResolver

var settings: WorldPointerSettings


func setup(next_settings: WorldPointerSettings) -> void:
	settings = next_settings


func pick_ship(
		camera: Camera3D,
		screen_position: Vector2
) -> ShipUnit:
	if camera == null or camera.get_world_3d() == null:
		return null
	var ray_length := settings.selection_ray_length_m \
		if settings != null else 50000.0
	var origin := camera.project_ray_origin(screen_position)
	var ray_end := origin \
		+ camera.project_ray_normal(screen_position) * ray_length
	var query := PhysicsRayQueryParameters3D.create(origin, ray_end)
	query.collide_with_areas = true
	if settings != null:
		query.collision_mask = settings.selection_collision_mask
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var candidate := hit.get("collider") as Node
	while candidate != null:
		if candidate is ShipUnit:
			return candidate as ShipUnit
		candidate = candidate.get_parent()
	return null


func screen_to_sea(
		camera: RTSCamera,
		screen_position: Vector2,
		sea_level_m: float
) -> Variant:
	if camera == null:
		return null
	var point: Variant = camera.screen_to_sea_plane(screen_position)
	if point is Vector3:
		var world_point := point as Vector3
		world_point.y = sea_level_m
		return world_point
	return null

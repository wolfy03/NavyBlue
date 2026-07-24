extends RefCounted
class_name WaterIntersection

const EPSILON := 0.00001


static func find_surface_intersection(
		caller: Node,
		segment_start: Vector3,
		segment_end: Vector3,
		fallback_water_height_m: float = 0.0
) -> WaterSurfaceHit:
	var ocean_manager := _get_ocean_manager(caller)
	if ocean_manager != null \
			and ocean_manager.has_method(&"get_surface_intersection_hit"):
		var manager_hit := ocean_manager.call(
			&"get_surface_intersection_hit",
			segment_start,
			segment_end
		) as WaterSurfaceHit
		if manager_hit != null and manager_hit.hit:
			return manager_hit
		if ocean_manager.has_method(&"get_water_height"):
			var start_height := float(ocean_manager.call(
				&"get_water_height",
				segment_start
			))
			if segment_start.y <= start_height:
				return WaterSurfaceHit.from_hit(
					Vector3(segment_start.x, start_height, segment_start.z),
					Vector3.UP,
					0.0
				) as WaterSurfaceHit
		return manager_hit
	var water_height := fallback_water_height_m
	if ocean_manager != null and ocean_manager.has_method(&"get_water_height"):
		water_height = float(ocean_manager.call(
			&"get_water_height",
			segment_start
		))
	return find_plane_intersection(
		segment_start,
		segment_end,
		water_height
	)


static func find_plane_intersection(
		segment_start: Vector3,
		segment_end: Vector3,
		water_height_m: float
) -> WaterSurfaceHit:
	var start_offset := segment_start.y - water_height_m
	var end_offset := segment_end.y - water_height_m
	if start_offset <= 0.0:
		return WaterSurfaceHit.from_hit(
			Vector3(segment_start.x, water_height_m, segment_start.z),
			Vector3.UP,
			0.0
		) as WaterSurfaceHit
	if end_offset > 0.0:
		return WaterSurfaceHit.miss() as WaterSurfaceHit
	var denominator := start_offset - end_offset
	if denominator <= EPSILON:
		return WaterSurfaceHit.miss() as WaterSurfaceHit
	var ratio := clampf(start_offset / denominator, 0.0, 1.0)
	var position := segment_start.lerp(segment_end, ratio)
	position.y = water_height_m
	return WaterSurfaceHit.from_hit(
		position,
		Vector3.UP,
		ratio
	) as WaterSurfaceHit


static func get_water_height(
		caller: Node,
		world_position: Vector3,
		fallback_water_height_m: float = 0.0
) -> float:
	var ocean_manager := _get_ocean_manager(caller)
	if ocean_manager != null and ocean_manager.has_method(&"get_water_height"):
		return float(ocean_manager.call(&"get_water_height", world_position))
	return fallback_water_height_m


static func _get_ocean_manager(caller: Node) -> Node:
	if caller == null or caller.get_tree() == null:
		return null
	return caller.get_tree().get_first_node_in_group(&"ocean_manager")

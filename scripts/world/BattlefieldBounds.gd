extends BattleNavigation
class_name BattlefieldBounds

const DEFAULT_SETTINGS := preload("res://resources/settings/default_battlefield_settings.tres")

@export var settings: BattlefieldSettings = DEFAULT_SETTINGS

func _ready() -> void:
	add_to_group(&"battlefield_bounds")

func is_inside_bounds(world_position: Vector3) -> bool:
	var half_extents := _get_half_extents()
	return absf(world_position.x) <= half_extents.x and absf(world_position.z) <= half_extents.y

func clamp_to_bounds(world_position: Vector3, margin_m: float = 0.0) -> Vector3:
	var half_extents := _get_half_extents()
	var safe_margin := clampf(margin_m, 0.0, minf(half_extents.x, half_extents.y))
	return clamp_to_battle_area(
		world_position,
		Vector2(-half_extents.x + safe_margin, -half_extents.y + safe_margin),
		Vector2(half_extents.x - safe_margin, half_extents.y - safe_margin)
	)

func get_closest_point_inside(world_position: Vector3) -> Vector3:
	return clamp_to_bounds(world_position)

func get_distance_to_boundary(world_position: Vector3) -> float:
	var half_extents := _get_half_extents()
	var outside_x := maxf(absf(world_position.x) - half_extents.x, 0.0)
	var outside_z := maxf(absf(world_position.z) - half_extents.y, 0.0)
	if outside_x > 0.0 or outside_z > 0.0:
		return Vector2(outside_x, outside_z).length()
	return minf(half_extents.x - absf(world_position.x), half_extents.y - absf(world_position.z))

func get_sea_level_m() -> float:
	return settings.sea_level_m if settings != null else 0.0

func _get_half_extents() -> Vector2:
	if settings == null:
		return Vector2(10000.0, 10000.0)
	return settings.get_half_extents_m()

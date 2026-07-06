extends Node
class_name BattleNavigation

func clamp_to_battle_area(position: Vector3, min_xz: Vector2, max_xz: Vector2) -> Vector3:
	position.x = clampf(position.x, min_xz.x, max_xz.x)
	position.z = clampf(position.z, min_xz.y, max_xz.y)
	return position


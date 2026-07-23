extends Node
class_name ShipAI

enum BehaviorState {
	CHASE,
	ATTACK,
	RETREAT,
}

@export var engagement_range_m := 8000.0
@export var retreat_distance_m := 350.0

var target
var behavior_state: BehaviorState = BehaviorState.CHASE

func set_target(next_target) -> void:
	target = next_target

func select_target(owner_ship: Node3D, candidates: Array) -> void:
	var best
	var best_distance := INF
	for candidate in candidates:
		if candidate == owner_ship or not candidate is Node3D:
			continue
		if candidate.get("team") == owner_ship.get("team"):
			continue
		var distance: float = owner_ship.global_position.distance_squared_to(candidate.global_position)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	target = best

func update_ai(owner_ship: Node3D, movement, navigation, combat, _ship_data: Resource, _delta: float) -> void:
	if owner_ship == null or movement == null or combat == null:
		return
	if navigation.battlefield_bounds != null \
			and not navigation.battlefield_bounds.is_inside_bounds(owner_ship.global_position):
		behavior_state = BehaviorState.CHASE
		return
	if not is_instance_valid(target):
		behavior_state = BehaviorState.CHASE
		if navigation.has_navigation_target:
			navigation.clear_navigation_target()
		movement.set_movement_command(0.0, 0.0)
		return

	var to_target: Vector3 = target.global_position - owner_ship.global_position
	var distance := to_target.length()
	combat.set_target(target)
	combat.set_aim_point(target.global_position)

	if distance <= retreat_distance_m:
		behavior_state = BehaviorState.RETREAT
		navigation.clear_navigation_target()
		movement.set_movement_command(-0.35, movement.get_rudder_to_direction(to_target))
		return

	if distance <= engagement_range_m:
		behavior_state = BehaviorState.ATTACK
		navigation.clear_navigation_target()
		movement.set_movement_command(0.28, movement.get_rudder_to_direction(to_target))
		combat.fire_all()
		return

	behavior_state = BehaviorState.CHASE
	navigation.set_navigation_target(target.global_position)

func should_fire(distance_to_target: float) -> bool:
	return distance_to_target <= engagement_range_m

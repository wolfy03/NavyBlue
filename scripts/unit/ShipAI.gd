extends Node
class_name ShipAI

enum BehaviorState {
	CHASE,
	ATTACK,
	RETREAT,
}

@export var engagement_range := 85.0
@export var retreat_distance := 18.0

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

func update_ai(owner_ship: Node3D, movement, combat, _ship_data: Resource, _delta: float) -> void:
	if owner_ship == null or movement == null or combat == null:
		return
	if not is_instance_valid(target):
		behavior_state = BehaviorState.CHASE
		var wander := sin(Time.get_ticks_msec() * 0.0006 + float(owner_ship.get_instance_id() % 7)) * 0.35
		movement.set_movement_command(0.35, wander)
		return

	var to_target: Vector3 = target.global_position - owner_ship.global_position
	var distance := to_target.length()
	combat.set_target(target)
	combat.set_aim_point(target.global_position)

	if distance <= retreat_distance:
		behavior_state = BehaviorState.RETREAT
		movement.set_movement_command(-0.35, movement.get_rudder_to_direction(to_target))
		return

	if distance <= engagement_range:
		behavior_state = BehaviorState.ATTACK
		movement.set_movement_command(0.28, movement.get_rudder_to_direction(to_target))
		combat.fire_all()
		return

	behavior_state = BehaviorState.CHASE
	movement.set_movement_command(0.78, movement.get_rudder_to_direction(to_target))

func should_fire(distance_to_target: float) -> bool:
	return distance_to_target <= engagement_range

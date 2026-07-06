extends Node
class_name ShipAI

@export var engagement_range := 85.0

func should_fire(distance_to_target: float) -> bool:
	return distance_to_target <= engagement_range

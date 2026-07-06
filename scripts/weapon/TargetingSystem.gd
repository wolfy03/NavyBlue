extends Node
class_name TargetingSystem

func nearest_target(source: Node3D, candidates: Array) -> Node3D:
	var best: Node3D
	var best_distance := INF
	for candidate in candidates:
		if candidate is Node3D:
			var distance := source.global_position.distance_squared_to(candidate.global_position)
			if distance < best_distance:
				best_distance = distance
				best = candidate
	return best


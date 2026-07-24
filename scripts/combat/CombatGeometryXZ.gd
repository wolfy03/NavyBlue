extends RefCounted
class_name CombatGeometryXZ


static func distance_xz(from: Vector3, to: Vector3) -> float:
	return Vector2(to.x - from.x, to.z - from.z).length()


static func segment_rectangle_intersection_xz(
		segment_start: Vector3,
		segment_end: Vector3,
		target_transform: Transform3D,
		half_extents: Vector2
) -> SegmentIntersectionResult:
	var result := SegmentIntersectionResult.new()
	var inverse_transform := target_transform.affine_inverse()
	var start_local := inverse_transform * segment_start
	var end_local := inverse_transform * segment_end
	var start := Vector2(start_local.x, start_local.z)
	var end := Vector2(end_local.x, end_local.z)
	var direction := end - start
	var minimum_time := 0.0
	var maximum_time := 1.0

	# This is intentionally an XZ-only swept test. Visual depth and ship height
	# do not participate in naval torpedo hit eligibility.
	for axis in 2:
		var start_axis := start[axis]
		var direction_axis := direction[axis]
		var extent := maxf(half_extents[axis], 0.0)
		if absf(direction_axis) <= 0.00001:
			if start_axis < -extent or start_axis > extent:
				return result
			continue
		var inverse_direction := 1.0 / direction_axis
		var first_time := (-extent - start_axis) * inverse_direction
		var second_time := (extent - start_axis) * inverse_direction
		if first_time > second_time:
			var swap := first_time
			first_time = second_time
			second_time = swap
		minimum_time = maxf(minimum_time, first_time)
		maximum_time = minf(maximum_time, second_time)
		if minimum_time > maximum_time:
			return result

	result.hit = true
	result.ratio = clampf(minimum_time, 0.0, 1.0)
	result.position = segment_start.lerp(segment_end, result.ratio)
	return result

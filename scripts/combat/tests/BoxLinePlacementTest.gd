extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var line_root := Node3D.new()
	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3.ONE
	mesh_instance.mesh = box_mesh
	line_root.add_child(mesh_instance)
	root.add_child(line_root)
	var start := Vector3(100.0, 12.0, -80.0)
	var end := start + Vector3(600.0, 0.0, -800.0)
	var thickness := 0.7
	var expected_length := start.distance_to(end)
	_check(
		BoxLinePlacement.place_between(
			line_root,
			mesh_instance,
			start,
			end,
			thickness
		),
		"nonzero segment is placed"
	)
	_check(
		line_root.global_position.is_equal_approx((start + end) * 0.5),
		"line root is centered between endpoints"
	)
	_check(
		is_equal_approx(mesh_instance.scale.z, expected_length),
		"unit BoxMesh local Z equals the world segment length"
	)
	_check(
		is_equal_approx(mesh_instance.scale.x, thickness) \
			and is_equal_approx(mesh_instance.scale.y, thickness),
		"line thickness is independent from range"
	)
	var expected_direction := (end - start).normalized()
	var rendered_direction := -line_root.global_basis.z.normalized()
	_check(
		rendered_direction.dot(expected_direction) > 0.9999,
		"Godot local -Z points toward the endpoint"
	)
	_check(
		not BoxLinePlacement.place_between(
			line_root,
			mesh_instance,
			start,
			start,
			thickness
		) and not mesh_instance.visible,
		"zero-length line is hidden"
	)
	line_root.queue_free()
	await process_frame
	for failure in _failures:
		push_error("BOX LINE PLACEMENT TEST: %s" % failure)
	print(
		"BOX_LINE_PLACEMENT_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)

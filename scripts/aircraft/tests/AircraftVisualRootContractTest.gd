extends SceneTree
## The %VisualRoot scene contract: banking works through the unique-named
## visual root regardless of what the model node inside it is called, and the
## physics root/collision/hardpoint transforms stay untouched.

const AIRCRAFT_SCENE := preload("res://scenes/aircraft/aircraft_unit.tscn")
const DELTA := 1.0 / 60.0

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	var aircraft := AIRCRAFT_SCENE.instantiate() as AircraftUnit
	# The GLB/model node inside the visual root can be renamed freely: the
	# contract is only the VisualRoot unique name.
	var visual := aircraft.get_node("VisualRoot") as Node3D
	if visual.get_child_count() > 0:
		visual.get_child(0).name = "RenamedImportedModel"
	root.add_child(aircraft)
	aircraft.aircraft_data = AircraftData.new()
	_check(
		aircraft.visual_root != null,
		"%VisualRoot resolves on the aircraft scene"
	)
	_check(
		aircraft.visual_controller.has_visual_root(),
		"the visual controller adopts the visual root"
	)
	var collision_before := aircraft.collision_shape.rotation
	var hardpoint_before := aircraft.payload_hardpoint.rotation
	_drive_turn(aircraft, 45.0, 120)
	_check(
		aircraft.visual_root.rotation.z > 0.05,
		"banking works with a renamed model node"
	)
	_check(
		aircraft.rotation == Vector3.ZERO \
			and aircraft.collision_shape.rotation == collision_before \
			and aircraft.payload_hardpoint.rotation == hardpoint_before,
		"physics root, collision and hardpoint never roll"
	)
	aircraft.queue_free()
	await process_frame
	for failure in _failures:
		push_error("VISUAL ROOT CONTRACT: %s" % failure)
	print(
		"AIRCRAFT_VISUAL_ROOT_CONTRACT_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _drive_turn(
		aircraft: AircraftUnit,
		turn_rate_deg_sec: float,
		frames: int
) -> void:
	var heading := 0.0
	for frame in frames:
		heading += deg_to_rad(turn_rate_deg_sec) * DELTA
		aircraft.velocity = Vector3(-sin(heading), 0.0, -cos(heading)) * 120.0
		aircraft.update_visual_bank(DELTA)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)

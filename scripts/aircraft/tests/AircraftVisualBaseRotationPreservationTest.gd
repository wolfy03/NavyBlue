extends SceneTree
## An authored (import-correction) rotation on the visual root is preserved:
## banking adds to it instead of overwriting it, and level flight returns to
## exactly the authored base.

const AIRCRAFT_SCENE := preload("res://scenes/aircraft/aircraft_unit.tscn")
const DELTA := 1.0 / 60.0
const BASE_ROTATION := Vector3(0.1, PI, 0.25)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	var aircraft := AIRCRAFT_SCENE.instantiate() as AircraftUnit
	# Author a non-zero base rotation BEFORE _ready captures it.
	(aircraft.get_node("VisualRoot") as Node3D).rotation = BASE_ROTATION
	root.add_child(aircraft)
	aircraft.aircraft_data = AircraftData.new()
	_check(
		aircraft.visual_controller.visual_base_rotation \
			.is_equal_approx(BASE_ROTATION),
		"the authored base rotation is captured at ready"
	)
	_drive_turn(aircraft, 45.0, 120)
	var banked := aircraft.visual_root.rotation
	_check(
		absf(banked.x - BASE_ROTATION.x) < 0.001 \
			and absf(banked.y - BASE_ROTATION.y) < 0.001,
		"banking never disturbs the authored X/Y rotation"
	)
	_check(
		banked.z > BASE_ROTATION.z + 0.05,
		"banking adds on top of the authored Z rotation"
	)
	_drive_turn(aircraft, 0.0, 300)
	_check(
		aircraft.visual_root.rotation.is_equal_approx(BASE_ROTATION),
		"level flight returns to exactly the authored base"
	)
	aircraft.visual_controller.reset_visual_attitude()
	_check(
		aircraft.visual_root.rotation.is_equal_approx(BASE_ROTATION),
		"an attitude reset restores the authored base"
	)
	aircraft.queue_free()
	await process_frame
	for failure in _failures:
		push_error("BASE ROTATION: %s" % failure)
	print(
		"AIRCRAFT_VISUAL_BASE_ROTATION_PRESERVATION_TEST %s"
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

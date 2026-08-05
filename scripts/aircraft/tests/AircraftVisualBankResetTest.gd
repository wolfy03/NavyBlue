extends SceneTree
## Lifecycle bank reset: deactivation (and any attitude reset) returns the
## visual root to its base rotation and clears the bank angle to zero.

const AIRCRAFT_SCENE := preload("res://scenes/aircraft/aircraft_unit.tscn")
const DELTA := 1.0 / 60.0

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	var aircraft := AIRCRAFT_SCENE.instantiate() as AircraftUnit
	root.add_child(aircraft)
	aircraft.aircraft_data = AircraftData.new()
	_drive_turn(aircraft, 60.0, 180)
	_check(
		absf(aircraft.visual_controller.get_current_bank_angle_rad()) > 0.1,
		"the turn builds up a visible bank"
	)
	aircraft.deactivate()
	_check(
		aircraft.visual_root.rotation.is_equal_approx(
			aircraft.visual_controller.visual_base_rotation
		),
		"deactivation restores the base rotation"
	)
	_check(
		aircraft.visual_controller.get_current_bank_angle_rad() == 0.0,
		"deactivation clears the bank angle to zero"
	)
	aircraft.queue_free()
	await process_frame
	for failure in _failures:
		push_error("BANK RESET: %s" % failure)
	print(
		"AIRCRAFT_VISUAL_BANK_RESET_TEST %s"
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

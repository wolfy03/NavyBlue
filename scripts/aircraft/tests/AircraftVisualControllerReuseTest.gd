extends SceneTree
## Pool/sortie reuse: after deactivate + activate, the first update flying a
## completely different heading must NOT produce an instantaneous full bank —
## the previous sortie's velocity history is gone.

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
	# First sortie: hard left turn heading roughly -Z.
	_drive_turn(aircraft, 90.0, 180)
	aircraft.deactivate()
	aircraft.activate()
	_check(
		aircraft.visual_controller.get_current_bank_angle_rad() == 0.0,
		"reactivation starts with zero bank"
	)
	# Second sortie: instantly flying +X. Without the reset, the stale
	# previous-velocity sample would read as a violent turn.
	aircraft.velocity = Vector3(120.0, 0.0, 0.0)
	aircraft.update_visual_bank(DELTA)
	aircraft.update_visual_bank(DELTA)
	var bank_after_two_frames := absf(
		aircraft.visual_controller.get_current_bank_angle_rad()
	)
	_check(
		bank_after_two_frames < deg_to_rad(6.0),
		"a fresh sortie never snaps toward maximum bank (got %.1f deg)"
			% rad_to_deg(bank_after_two_frames)
	)
	# Straight flight on the new heading keeps the model level.
	for frame in 60:
		aircraft.update_visual_bank(DELTA)
	_check(
		absf(aircraft.visual_controller.get_current_bank_angle_rad()) < 0.01,
		"straight flight on the new heading stays level"
	)
	aircraft.queue_free()
	await process_frame
	for failure in _failures:
		push_error("VISUAL REUSE: %s" % failure)
	print(
		"AIRCRAFT_VISUAL_CONTROLLER_REUSE_TEST %s"
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

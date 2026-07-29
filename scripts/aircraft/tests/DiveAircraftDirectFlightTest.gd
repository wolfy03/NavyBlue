extends SceneTree

const AIRCRAFT_SCENE := preload(
	"res://scenes/aircraft/aircraft_unit.tscn"
)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var aircraft := AIRCRAFT_SCENE.instantiate() as AircraftUnit
	root.add_child(aircraft)
	await process_frame
	var movement := aircraft.movement
	var data := AircraftData.new()
	data.cruise_speed_mps = 150.0
	data.maximum_speed_mps = 220.0
	movement.setup(aircraft, data)
	aircraft.global_position = Vector3(0.0, 200.0, 0.0)
	var direction := Vector3(0.0, -0.8, -0.6).normalized()
	movement.set_direct_flight(direction, 200.0)
	var before := aircraft.global_position
	movement.update_movement(1.0 / 60.0)
	_check(
		movement.flight_mode \
			== AircraftMovement.FlightMode.DIRECT_FLIGHT,
		"movement enters DIRECT_FLIGHT"
	)
	_check(aircraft.velocity.y < 0.0, "direct flight preserves descent")
	_check(
		aircraft.global_position.y < before.y,
		"direct flight moves the aircraft downward"
	)
	_check(
		aircraft.get_forward_direction().dot(direction) > 0.99,
		"aircraft pitch follows the direct flight direction"
	)
	movement.set_formation_mode()
	_check(
		movement.flight_mode == AircraftMovement.FlightMode.FORMATION,
		"formation mode restores"
	)
	aircraft.queue_free()
	await process_frame
	_finish()


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	for failure in _failures:
		push_error("DIVE AIRCRAFT DIRECT FLIGHT TEST: %s" % failure)
	print(
		"DIVE_AIRCRAFT_DIRECT_FLIGHT_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)

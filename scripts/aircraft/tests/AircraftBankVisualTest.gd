extends SceneTree
## Visual bank contract: the aircraft MODEL rolls into horizontal turns while
## the physics root, collision shape and weapon transforms never roll. Drives
## update_visual_bank directly with synthetic velocity histories.

const AIRCRAFT_SCENE := preload("res://scenes/aircraft/aircraft_unit.tscn")
const DELTA := 1.0 / 60.0
const SPEED := 120.0

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	_test_left_turn_banks_left()
	_test_right_turn_banks_right()
	_test_straight_flight_levels_out()
	_test_bank_is_clamped()
	_test_physics_root_never_rolls()
	_test_slow_or_diving_flight_levels_out()
	print(
		"AIRCRAFT_BANK_VISUAL_TEST failures=%d" % _failures.size()
	)
	for failure in _failures:
		push_error("AIRCRAFT BANK VISUAL: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _spawn_aircraft() -> AircraftUnit:
	var aircraft := AIRCRAFT_SCENE.instantiate() as AircraftUnit
	root.add_child(aircraft)
	aircraft.aircraft_data = AircraftData.new()
	return aircraft


func _drive_turn(
		aircraft: AircraftUnit,
		turn_rate_deg_sec: float,
		frames: int,
		speed: float = SPEED
) -> void:
	# Positive rate = positive yaw about UP = a LEFT turn for a -Z-forward
	# aircraft: heading rotates the -Z track counterclockwise seen from above.
	var heading := 0.0
	for frame in frames:
		heading += deg_to_rad(turn_rate_deg_sec) * DELTA
		aircraft.velocity = Vector3(
			-sin(heading), 0.0, -cos(heading)
		) * speed
		aircraft.update_visual_bank(DELTA)


func _test_left_turn_banks_left() -> void:
	var aircraft := _spawn_aircraft()
	# Positive yaw about UP is a left turn; the model must roll to positive z.
	_drive_turn(aircraft, 30.0, 90)
	if aircraft.visual_root.rotation.z <= 0.01:
		_failures.append(
			"left turn banks left (rotation.z %.3f)"
			% aircraft.visual_root.rotation.z
		)
	aircraft.queue_free()


func _test_right_turn_banks_right() -> void:
	var aircraft := _spawn_aircraft()
	_drive_turn(aircraft, -30.0, 90)
	if aircraft.visual_root.rotation.z >= -0.01:
		_failures.append(
			"right turn banks right (rotation.z %.3f)"
			% aircraft.visual_root.rotation.z
		)
	aircraft.queue_free()


func _test_straight_flight_levels_out() -> void:
	var aircraft := _spawn_aircraft()
	_drive_turn(aircraft, 30.0, 90)
	_drive_turn(aircraft, 0.0, 240)
	if absf(aircraft.visual_root.rotation.z) > 0.01:
		_failures.append(
			"straight flight returns the model to level (rotation.z %.3f)"
			% aircraft.visual_root.rotation.z
		)
	aircraft.queue_free()


func _test_bank_is_clamped() -> void:
	var aircraft := _spawn_aircraft()
	var settings := AircraftBankVisualSettings.new()
	settings.maximum_bank_angle_degrees = 35.0
	aircraft.aircraft_data.bank_visual_settings = settings
	# Far beyond the full-bank turn rate: the roll must stop at the maximum.
	_drive_turn(aircraft, 160.0, 240)
	var limit := deg_to_rad(35.0) + 0.01
	if absf(aircraft.visual_root.rotation.z) > limit:
		_failures.append(
			"bank clamps at the maximum angle (rotation.z %.3f)"
			% aircraft.visual_root.rotation.z
		)
	if absf(aircraft.visual_root.rotation.z) < deg_to_rad(30.0):
		_failures.append(
			"a hard turn reaches near the maximum bank (rotation.z %.3f)"
			% aircraft.visual_root.rotation.z
		)
	aircraft.queue_free()


func _test_physics_root_never_rolls() -> void:
	var aircraft := _spawn_aircraft()
	var root_rotation_before := aircraft.rotation
	var collision_rotation_before := aircraft.collision_shape.rotation
	var hardpoint_rotation_before := aircraft.payload_hardpoint.rotation
	_drive_turn(aircraft, 45.0, 180)
	if not aircraft.rotation.is_equal_approx(root_rotation_before):
		_failures.append("banking never rotates the physics root")
	if not aircraft.collision_shape.rotation.is_equal_approx(
		collision_rotation_before
	):
		_failures.append("banking never rotates the collision shape")
	if not aircraft.payload_hardpoint.rotation.is_equal_approx(
		hardpoint_rotation_before
	):
		_failures.append("banking never rotates the payload hardpoint")
	if absf(aircraft.visual_root.rotation.z) <= 0.01:
		_failures.append("the visual model does bank during the turn")
	aircraft.queue_free()


func _test_slow_or_diving_flight_levels_out() -> void:
	var aircraft := _spawn_aircraft()
	_drive_turn(aircraft, 30.0, 90)
	# A fixed-direction dive: huge vertical speed, straight slow horizontal
	# track. The model must level out instead of holding the old bank.
	for frame in 240:
		aircraft.velocity = Vector3(0.0, -172.0, 8.0)
		aircraft.update_visual_bank(DELTA)
	if absf(aircraft.visual_root.rotation.z) > 0.01:
		_failures.append(
			"a straight dive levels the model (rotation.z %.3f)"
			% aircraft.visual_root.rotation.z
		)
	aircraft.queue_free()


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)

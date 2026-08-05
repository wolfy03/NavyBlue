extends RefCounted
class_name AircraftCommandController

var selection_controller: AircraftSelectionController
var carrier_controller: CarrierCommandController
var torpedo_targeting_session: TorpedoAttackTargetingSession
var dive_targeting_session: DiveBombTargetingSession
var world_pointer_resolver: WorldPointerResolver
var camera: RTSCamera
var battle_environment: BattleEnvironment


func setup(
		next_selection_controller: AircraftSelectionController,
		next_carrier_controller: CarrierCommandController
) -> void:
	shutdown()
	selection_controller = next_selection_controller
	carrier_controller = next_carrier_controller


func shutdown() -> void:
	cancel_torpedo_targeting(&"shutdown")
	cancel_dive_targeting(&"shutdown")
	if selection_controller != null:
		_disconnect_selection_changed()
		selection_controller.set_input_enabled(false)
		selection_controller.clear_selection()
	if carrier_controller != null and carrier_controller.is_targeting():
		carrier_controller.cancel_targeting()
	selection_controller = null
	carrier_controller = null
	torpedo_targeting_session = null
	dive_targeting_session = null
	world_pointer_resolver = null
	camera = null
	battle_environment = null


func setup_torpedo_targeting(
		session: TorpedoAttackTargetingSession,
		pointer_resolver: WorldPointerResolver,
		view_camera: Camera3D,
		environment: BattleEnvironment
) -> void:
	torpedo_targeting_session = session
	world_pointer_resolver = pointer_resolver
	camera = view_camera as RTSCamera
	battle_environment = environment
	if selection_controller != null \
			and not selection_controller.selection_changed.is_connected(
				_on_aircraft_selection_changed
			):
		selection_controller.selection_changed.connect(
			_on_aircraft_selection_changed
		)


func setup_dive_targeting(
		session: DiveBombTargetingSession,
		pointer_resolver: WorldPointerResolver,
		view_camera: Camera3D,
		environment: BattleEnvironment
) -> void:
	dive_targeting_session = session
	if world_pointer_resolver == null:
		world_pointer_resolver = pointer_resolver
	if camera == null:
		camera = view_camera as RTSCamera
	if battle_environment == null:
		battle_environment = environment
	if selection_controller != null \
			and not selection_controller.selection_changed.is_connected(
				_on_aircraft_selection_changed
			):
		selection_controller.selection_changed.connect(
			_on_aircraft_selection_changed
		)


func set_input_enabled(enabled: bool) -> void:
	if selection_controller != null:
		selection_controller.set_input_enabled(enabled)
	if not enabled:
		cancel_torpedo_targeting(&"input_disabled")
		cancel_dive_targeting(&"input_disabled")


func has_selection() -> bool:
	return selection_controller != null \
		and selection_controller.has_selection()


func clear_selection() -> void:
	if selection_controller != null:
		selection_controller.clear_selection()


func execute_special_action() -> bool:
	if selection_controller == null:
		return false
	var squadrons := selection_controller.get_selected_squadrons()
	if squadrons.is_empty():
		return false
	var torpedo_count := 0
	var dive_count := 0
	for squadron in squadrons:
		match squadron.get_aircraft_role():
			AircraftData.AircraftRole.TORPEDO_BOMBER:
				torpedo_count += 1
			AircraftData.AircraftRole.DIVE_BOMBER:
				dive_count += 1
	if torpedo_count == squadrons.size():
		cancel_dive_targeting(&"other_attack")
		return _begin_torpedo_targeting(squadrons)
	if dive_count == squadrons.size():
		cancel_torpedo_targeting(&"other_attack")
		return _begin_dive_targeting(squadrons)
	selection_controller.command_feedback.emit(
		"Manual attacks require squadrons of the same attack role."
	)
	return true


func cancel_targeting() -> bool:
	if cancel_torpedo_targeting(&"command_cancel"):
		return true
	if cancel_dive_targeting(&"command_cancel"):
		return true
	if carrier_controller == null or not carrier_controller.is_targeting():
		return false
	carrier_controller.cancel_targeting()
	return true


func cancel_torpedo_targeting(reason: StringName) -> bool:
	if torpedo_targeting_session == null \
			or not torpedo_targeting_session.is_active():
		return false
	torpedo_targeting_session.cancel(reason)
	return true


func cancel_dive_targeting(reason: StringName) -> bool:
	if dive_targeting_session == null \
			or not dive_targeting_session.is_active():
		return false
	dive_targeting_session.cancel(reason)
	return true


func is_torpedo_targeting_active() -> bool:
	return torpedo_targeting_session != null \
		and torpedo_targeting_session.is_active()


func is_dive_targeting_active() -> bool:
	return dive_targeting_session != null \
		and dive_targeting_session.is_active()


func handle_targeting_input(event: InputEvent) -> bool:
	return handle_torpedo_targeting_input(event) \
		or handle_dive_targeting_input(event)


func handle_torpedo_targeting_input(event: InputEvent) -> bool:
	if not is_torpedo_targeting_active():
		return false
	if event is InputEventMouseMotion:
		var motion_point: Variant = _screen_to_command_plane(
			(event as InputEventMouseMotion).position
		)
		if motion_point == null:
			return true
		if torpedo_targeting_session.is_dragging():
			torpedo_targeting_session.update_drag(motion_point as Vector3)
		else:
			torpedo_targeting_session.update_armed_cursor(
				motion_point as Vector3
			)
		return true
	if not event is InputEventMouseButton:
		return false
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT \
			and mouse_event.pressed:
		cancel_torpedo_targeting(&"right_click")
		return true
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return false
	var point: Variant = _screen_to_command_plane(mouse_event.position)
	if point == null:
		return true
	if mouse_event.pressed:
		torpedo_targeting_session.begin_drag(point as Vector3)
		return true
	var squadrons := torpedo_targeting_session.get_active_squadrons()
	var target_ship: ShipUnit
	if world_pointer_resolver != null:
		target_ship = world_pointer_resolver.pick_ship(
			camera,
			mouse_event.position
		)
	var commands := torpedo_targeting_session.resolve_drag_commands(
		point as Vector3,
		target_ship
	)
	if commands.is_empty():
		# Resolve failed: the session already reverted to ARMED so the player
		# can drag again. Nothing to apply.
		return true
	var issued_count := mini(squadrons.size(), commands.size())
	# Atomic apply: every selected squadron must be able to accept its command
	# before any command is issued, so a multi-squadron order never lands on
	# only some of the squadrons.
	var all_applicable := issued_count == squadrons.size() \
		and issued_count == commands.size()
	if all_applicable:
		for index in issued_count:
			if not squadrons[index].can_apply_torpedo_attack(commands[index]):
				all_applicable = false
				break
	if not all_applicable:
		torpedo_targeting_session.return_to_armed(&"apply_rejected")
		if selection_controller != null:
			selection_controller.command_feedback.emit(
				"Torpedo attack could not be ordered for every squadron."
			)
		return true
	# Apply atomically: issue each command and roll back everything already
	# applied if any squadron fails, so the order is all-or-nothing and the
	# session only completes once every squadron has actually started its run.
	var applied: Array[AircraftSquadron] = []
	for index in issued_count:
		if squadrons[index].issue_player_torpedo_attack(commands[index]):
			applied.append(squadrons[index])
			continue
		for applied_squadron in applied:
			applied_squadron.abort_player_torpedo_attack(
				&"atomic_apply_rollback"
			)
		torpedo_targeting_session.return_to_armed(&"apply_failed")
		if selection_controller != null:
			selection_controller.command_feedback.emit(
				"Torpedo attack command failed."
			)
		return true
	torpedo_targeting_session.confirm_completed(commands)
	if selection_controller != null:
		selection_controller.command_feedback.emit(
			"Torpedo attack ordered for %d squadron(s)." % issued_count
		)
	return true


func handle_dive_targeting_input(event: InputEvent) -> bool:
	if not is_dive_targeting_active():
		return false
	if event is InputEventMouseMotion:
		var motion_point: Variant = _screen_to_command_plane(
			(event as InputEventMouseMotion).position
		)
		if motion_point != null:
			dive_targeting_session.update_cursor(motion_point as Vector3)
		return true
	if not event is InputEventMouseButton:
		return false
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT \
			and mouse_event.pressed:
		cancel_dive_targeting(&"right_click")
		return true
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return false
	if not mouse_event.pressed:
		# Consume the release so it does not start a selection drag.
		return true
	var point: Variant = _screen_to_command_plane(mouse_event.position)
	if point == null:
		return true
	var squadrons := dive_targeting_session.get_active_squadrons()
	# Atomic apply: only order the run if every selected squadron can still dive.
	var all_applicable := not squadrons.is_empty()
	for squadron in squadrons:
		if not squadron.can_begin_manual_dive():
			all_applicable = false
			break
	if not all_applicable:
		dive_targeting_session.cancel(&"apply_rejected")
		if selection_controller != null:
			selection_controller.command_feedback.emit(
				"Dive attack could not be ordered."
			)
		return true
	# A click directly on a ship makes it the explicit dive target; ocean
	# clicks rely on the resolver's radius acquisition around the point.
	var clicked_ship: ShipUnit = null
	if world_pointer_resolver != null:
		clicked_ship = world_pointer_resolver.pick_ship(
			camera,
			mouse_event.position
		)
	var commands := dive_targeting_session.confirm(
		point as Vector3,
		clicked_ship
	)
	var issued_count := mini(squadrons.size(), commands.size())
	var ordered := 0
	for index in issued_count:
		if squadrons[index].begin_manual_dive_at(
			commands[index].target_point,
			commands[index].dispersion_radius_m,
			commands[index].get_target_ship()
		):
			ordered += 1
	if selection_controller != null:
		selection_controller.command_feedback.emit(
			"Dive attack ordered for %d squadron(s)." % ordered
		)
	return true


func _begin_torpedo_targeting(
		squadrons: Array[AircraftSquadron]
) -> bool:
	if torpedo_targeting_session == null:
		selection_controller.command_feedback.emit(
			"Torpedo targeting is unavailable."
		)
		return true
	if torpedo_targeting_session.is_active():
		return true
	var cursor_point: Variant = _screen_to_command_plane(
		camera.get_viewport().get_mouse_position() \
			if camera != null else Vector2.ZERO
	)
	if cursor_point == null:
		selection_controller.command_feedback.emit(
			"Torpedo targeting requires a valid battle position."
		)
		return true
	if not torpedo_targeting_session.begin(
		squadrons,
		cursor_point as Vector3
	):
		selection_controller.command_feedback.emit(
			"Selected squadrons cannot begin a torpedo attack."
		)
		return true
	selection_controller.cancel_drag()
	selection_controller.command_feedback.emit(
		"Torpedo targeting: drag from entry point to release point."
	)
	return true


func _begin_dive_targeting(
		squadrons: Array[AircraftSquadron]
) -> bool:
	if dive_targeting_session == null:
		selection_controller.command_feedback.emit(
			"Dive targeting is unavailable."
		)
		return true
	if dive_targeting_session.is_active():
		return true
	var cursor_point: Variant = _screen_to_command_plane(
		camera.get_viewport().get_mouse_position() \
			if camera != null else Vector2.ZERO
	)
	if cursor_point == null:
		selection_controller.command_feedback.emit(
			"Dive targeting requires a valid battle position."
		)
		return true
	if not dive_targeting_session.begin(
		squadrons,
		cursor_point as Vector3
	):
		selection_controller.command_feedback.emit(
			"Selected squadrons cannot begin a dive attack."
		)
		return true
	selection_controller.cancel_drag()
	selection_controller.command_feedback.emit(
		"Dive targeting: left-click the bomb point."
	)
	return true


func _screen_to_command_plane(screen_position: Vector2) -> Variant:
	if world_pointer_resolver == null or camera == null:
		return null
	return world_pointer_resolver.screen_to_sea(
		camera,
		screen_position,
		battle_environment.sea_level_m \
			if battle_environment != null else 0.0
	)


func _on_aircraft_selection_changed(
		_squadrons: Array[AircraftSquadron]
) -> void:
	cancel_torpedo_targeting(&"selection_changed")
	cancel_dive_targeting(&"selection_changed")


func _disconnect_selection_changed() -> void:
	if selection_controller != null \
			and selection_controller.selection_changed.is_connected(
				_on_aircraft_selection_changed
			):
		selection_controller.selection_changed.disconnect(
			_on_aircraft_selection_changed
		)

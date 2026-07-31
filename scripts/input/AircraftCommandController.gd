extends RefCounted
class_name AircraftCommandController

var selection_controller: AircraftSelectionController
var carrier_controller: CarrierCommandController
var torpedo_targeting_session: TorpedoAttackTargetingSession
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
	if selection_controller != null:
		_disconnect_selection_changed()
		selection_controller.set_input_enabled(false)
		selection_controller.clear_selection()
	if carrier_controller != null and carrier_controller.is_targeting():
		carrier_controller.cancel_targeting()
	selection_controller = null
	carrier_controller = null
	torpedo_targeting_session = null
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


func set_input_enabled(enabled: bool) -> void:
	if selection_controller != null:
		selection_controller.set_input_enabled(enabled)
	if not enabled:
		cancel_torpedo_targeting(&"input_disabled")


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
		return _begin_torpedo_targeting(squadrons)
	if dive_count == squadrons.size():
		cancel_torpedo_targeting(&"other_attack")
		return selection_controller.execute_special_action()
	selection_controller.command_feedback.emit(
		"Manual attacks require squadrons of the same attack role."
	)
	return true


func cancel_targeting() -> bool:
	if cancel_torpedo_targeting(&"command_cancel"):
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


func is_torpedo_targeting_active() -> bool:
	return torpedo_targeting_session != null \
		and torpedo_targeting_session.is_active()


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
	var commands := torpedo_targeting_session.complete_drag(
		point as Vector3,
		target_ship
	)
	var issued_count := mini(squadrons.size(), commands.size())
	for index in issued_count:
		squadrons[index].issue_player_torpedo_attack(commands[index])
	if issued_count > 0 and selection_controller != null:
		selection_controller.command_feedback.emit(
			"Torpedo attack ordered for %d squadron(s)." % issued_count
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


func _disconnect_selection_changed() -> void:
	if selection_controller != null \
			and selection_controller.selection_changed.is_connected(
				_on_aircraft_selection_changed
			):
		selection_controller.selection_changed.disconnect(
			_on_aircraft_selection_changed
		)

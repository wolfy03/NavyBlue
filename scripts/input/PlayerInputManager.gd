extends Node
class_name PlayerInputManager

signal selection_changed(selected_ships: Array[ShipUnit])
signal move_command_issued(target: Vector3, ships: Array[ShipUnit])
signal command_mode_changed(mode: CommandMode)

enum CommandMode {
	SHIP,
	AIRCRAFT,
}

const DEFAULT_RULES: BattlefieldRules = preload(
	"res://resources/settings/default_battlefield_rules.tres"
)
const DEFAULT_FORMATION: FleetFormationData = preload(
	"res://resources/settings/default_fleet_formation.tres"
)
const DEFAULT_POINTER_SETTINGS: WorldPointerSettings = preload(
	"res://resources/settings/default_world_pointer_settings.tres"
)

@export var pitch_step_degrees := 1.5
@export var movement_marker_path: NodePath = ^"../MovementMarker"
@export var battlefield_rules: BattlefieldRules = DEFAULT_RULES
@export var fleet_formation_data: FleetFormationData = DEFAULT_FORMATION
@export var pointer_settings: WorldPointerSettings = DEFAULT_POINTER_SETTINGS

var camera: RTSCamera
var battlefield_bounds: BattlefieldBounds
var battle_environment: BattleEnvironment
var carrier_command_controller: CarrierCommandController
var aircraft_selection_controller: AircraftSelectionController
var command_mode: CommandMode = CommandMode.SHIP

var selection_coordinator := SelectionCoordinator.new()
var ship_command_controller := ShipCommandController.new()
var aircraft_command_controller := AircraftCommandController.new()
var world_pointer_resolver := WorldPointerResolver.new()
var formation_planner := FleetFormationPlanner.new()

var controlled_ship: ShipUnit:
	get:
		return selection_coordinator.controlled_ship
	set(value):
		selection_coordinator.controlled_ship = value

var selected_ships: Array[ShipUnit]:
	get:
		return selection_coordinator.selected_ships
	set(value):
		selection_coordinator.selected_ships = value

var _input_enabled := true


func _init() -> void:
	world_pointer_resolver.setup(pointer_settings)
	if not selection_coordinator.selection_changed.is_connected(
		_on_ship_selection_changed
	):
		selection_coordinator.selection_changed.connect(
			_on_ship_selection_changed
		)
	if not ship_command_controller.move_command_issued.is_connected(
		_on_move_command_issued
	):
		ship_command_controller.move_command_issued.connect(
			_on_move_command_issued
		)


func setup(
		ship: ShipUnit,
		view_camera: Camera3D,
		environment: BattleEnvironment
) -> void:
	camera = view_camera as RTSCamera
	battle_environment = environment
	battlefield_bounds = environment.battlefield_bounds \
		if environment != null else null
	world_pointer_resolver.setup(pointer_settings)
	selection_coordinator.setup(ship)
	ship_command_controller.setup(
		selection_coordinator,
		battlefield_bounds,
		battlefield_rules,
		fleet_formation_data,
		formation_planner,
		get_node_or_null(movement_marker_path) as Node3D
	)
	aircraft_command_controller.setup(
		aircraft_selection_controller,
		carrier_command_controller
	)
	if camera != null:
		camera.set_selection_provider(self)
	_apply_command_mode()


func set_carrier_command_controller(
		controller: CarrierCommandController
) -> void:
	carrier_command_controller = controller
	aircraft_command_controller.setup(
		aircraft_selection_controller,
		carrier_command_controller
	)
	if carrier_command_controller != null \
			and carrier_command_controller.panel != null \
			and not carrier_command_controller.panel \
				.aircraft_command_requested.is_connected(
					_on_aircraft_command_requested
				):
		carrier_command_controller.panel.aircraft_command_requested.connect(
			_on_aircraft_command_requested
		)
	_sync_carrier_selection()


func set_aircraft_selection_controller(
		controller: AircraftSelectionController
) -> void:
	aircraft_selection_controller = controller
	aircraft_command_controller.setup(
		aircraft_selection_controller,
		carrier_command_controller
	)
	_apply_command_mode()


func _physics_process(_delta: float) -> void:
	_prune_selection()
	if controlled_ship == null or not is_instance_valid(controlled_ship):
		return
	if command_mode == CommandMode.AIRCRAFT:
		ship_command_controller.suspend_combat_input()
		if Input.is_action_just_pressed(&"command_cancel"):
			if aircraft_command_controller.cancel_targeting():
				return
			aircraft_command_controller.clear_selection()
		return
	ship_command_controller.update_direct_control()
	if Input.is_action_just_pressed(&"turret_pitch_up"):
		ship_command_controller.adjust_turret_pitch(pitch_step_degrees)
	if Input.is_action_just_pressed(&"turret_pitch_down"):
		ship_command_controller.adjust_turret_pitch(-pitch_step_degrees)
	if Input.is_action_just_pressed(&"command_cancel"):
		if aircraft_command_controller.cancel_targeting():
			return
		if aircraft_command_controller.has_selection():
			aircraft_command_controller.clear_selection()
			return
		cancel_selected_commands()


func _input(event: InputEvent) -> void:
	if not _input_enabled:
		return
	if event.is_action_pressed(&"toggle_command_mode") \
			and not event.is_echo():
		toggle_command_mode()
		get_viewport().set_input_as_handled()
		return
	if _handle_aircraft_special_action(event):
		get_viewport().set_input_as_handled()
		return
	if _handle_pointer_input(event):
		get_viewport().set_input_as_handled()


func _handle_aircraft_special_action(event: InputEvent) -> bool:
	if not event.is_action_pressed(&"aircraft_special_action") \
			or event.is_echo():
		return false
	return command_mode == CommandMode.AIRCRAFT \
		and not _is_text_input_focused() \
		and aircraft_command_controller.execute_special_action()


func _handle_pointer_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		if command_mode == CommandMode.AIRCRAFT \
				and aircraft_selection_controller != null:
			aircraft_selection_controller.update_drag(
				(event as InputEventMouseMotion).position
			)
		return false
	if not event is InputEventMouseButton:
		return false
	var mouse_event := event as InputEventMouseButton
	if _is_pointer_over_interactive_ui():
		if mouse_event.button_index == MOUSE_BUTTON_LEFT \
				and not mouse_event.pressed \
				and aircraft_selection_controller != null:
			aircraft_selection_controller.cancel_drag()
		return false
	match mouse_event.button_index:
		MOUSE_BUTTON_LEFT:
			return _handle_left_mouse(mouse_event)
		MOUSE_BUTTON_RIGHT:
			return _handle_right_mouse(mouse_event)
	return false


func _handle_left_mouse(event: InputEventMouseButton) -> bool:
	if command_mode == CommandMode.SHIP:
		if not event.pressed:
			_handle_primary_click(event.position)
		return true
	if event.pressed:
		if carrier_command_controller != null \
				and carrier_command_controller.is_targeting():
			_handle_primary_click(event.position)
			return true
		return aircraft_selection_controller != null \
			and aircraft_selection_controller.begin_drag(event.position)
	if aircraft_selection_controller != null:
		aircraft_selection_controller.finish_drag(
			event.position,
			Input.is_action_pressed(&"selection_additive")
		)
	return true


func _handle_right_mouse(event: InputEventMouseButton) -> bool:
	if not event.pressed:
		return false
	if aircraft_command_controller.cancel_targeting():
		return true
	if command_mode == CommandMode.AIRCRAFT:
		if aircraft_selection_controller != null \
				and aircraft_selection_controller.has_selection():
			aircraft_selection_controller.issue_move_from_screen(
				event.position,
				world_pointer_resolver.pick_ship(
					camera,
					event.position
				)
			)
		return true
	var target: Variant = world_pointer_resolver.screen_to_sea(
		camera,
		event.position,
		battle_environment.sea_level_m \
			if battle_environment != null else 0.0
	)
	if target is Vector3:
		ship_command_controller.issue_move_command(target)
	return true


func get_selected_ships() -> Array[ShipUnit]:
	return selection_coordinator.get_selected_ships()


func get_controlled_ship() -> ShipUnit:
	return controlled_ship


func set_command_mode(mode: CommandMode) -> void:
	if command_mode == mode:
		_apply_command_mode()
		return
	command_mode = mode
	_apply_command_mode()
	command_mode_changed.emit(command_mode)


func toggle_command_mode() -> void:
	set_command_mode(
		CommandMode.AIRCRAFT
		if command_mode == CommandMode.SHIP
		else CommandMode.SHIP
	)


func get_command_mode() -> CommandMode:
	return command_mode


func cancel_selected_commands() -> void:
	ship_command_controller.clear_navigation_targets()


func _handle_primary_click(screen_position: Vector2) -> void:
	var clicked_ship := world_pointer_resolver.pick_ship(
		camera,
		screen_position
	)
	if carrier_command_controller != null \
			and carrier_command_controller.is_targeting():
		carrier_command_controller.try_issue_strike(clicked_ship)
		return
	if clicked_ship != null and clicked_ship.team != FactionRelations.ENEMY:
		if aircraft_selection_controller != null \
				and not Input.is_action_pressed(&"selection_additive"):
			aircraft_selection_controller.clear_selection()
		if Input.is_action_pressed(&"selection_additive"):
			selection_coordinator.toggle(clicked_ship)
		else:
			selection_coordinator.select_only(clicked_ship)
		return
	var aim_point: Variant = world_pointer_resolver.screen_to_sea(
		camera,
		screen_position,
		battle_environment.sea_level_m \
			if battle_environment != null else 0.0
	)
	if aim_point is Vector3:
		if aircraft_selection_controller != null \
				and not Input.is_action_pressed(&"selection_additive"):
			aircraft_selection_controller.clear_selection()
		ship_command_controller.set_aim_point(aim_point)


func _select_only(ship: ShipUnit) -> void:
	selection_coordinator.select_only(ship)


func _toggle_selection(ship: ShipUnit) -> void:
	selection_coordinator.toggle(ship)


func _prune_selection() -> void:
	if selection_coordinator.prune():
		_sync_carrier_selection()


func _is_pointer_over_interactive_ui() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	while hovered != null:
		if hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE and (
				hovered is Button
				or hovered is Slider
				or hovered is LineEdit
				or hovered is ItemList
				or hovered is ScrollContainer
				or hovered.has_meta(&"blocks_world_input")
		):
			return true
		hovered = hovered.get_parent() as Control
	return false


func _is_text_input_focused() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused is LineEdit \
		or focused is TextEdit \
		or focused is SpinBox


func _sync_carrier_selection() -> void:
	if carrier_command_controller == null:
		return
	var carrier: ShipUnit
	for candidate in selection_coordinator.get_selected_ships():
		if candidate.player_controlled \
				and candidate.ship_data != null \
				and candidate.ship_data.carrier_air_group_data != null:
			carrier = candidate
			break
	carrier_command_controller.set_selected_carrier(carrier)


func _apply_command_mode() -> void:
	aircraft_command_controller.set_input_enabled(
		command_mode == CommandMode.AIRCRAFT
	)
	if command_mode == CommandMode.SHIP:
		aircraft_command_controller.cancel_targeting()
	else:
		ship_command_controller.suspend_combat_input()


func _on_ship_selection_changed(
		next_selected_ships: Array[ShipUnit]
) -> void:
	selection_changed.emit(next_selected_ships)
	_sync_carrier_selection()


func _on_move_command_issued(
		target: Vector3,
		ships: Array[ShipUnit]
) -> void:
	move_command_issued.emit(target, ships)


func _on_aircraft_command_requested() -> void:
	set_command_mode(CommandMode.AIRCRAFT)

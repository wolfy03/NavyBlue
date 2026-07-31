extends RefCounted
class_name ShipCommandController

signal move_command_issued(target: Vector3, ships: Array[ShipUnit])
signal manual_aim_changed(
	ship: ShipUnit,
	command: ShipManualAimCommand
)
signal manual_aim_cleared(ship: ShipUnit)

var selection: SelectionCoordinator
var battlefield_bounds: BattlefieldBounds
var rules: BattlefieldRules
var formation_data: FleetFormationData
var formation_planner: FleetFormationPlanner
var movement_marker: Node3D
var manual_aim_resolver := ShipManualAimResolver.new()


func setup(
		next_selection: SelectionCoordinator,
		bounds: BattlefieldBounds,
		next_rules: BattlefieldRules,
		next_formation_data: FleetFormationData,
		next_formation_planner: FleetFormationPlanner,
		next_movement_marker: Node3D
) -> void:
	selection = next_selection
	battlefield_bounds = bounds
	rules = next_rules
	formation_data = next_formation_data
	formation_planner = next_formation_planner
	movement_marker = next_movement_marker


func update_direct_control() -> void:
	var controlled_ship := selection.controlled_ship \
		if selection != null else null
	if controlled_ship == null or not is_instance_valid(controlled_ship):
		return
	controlled_ship.set_player_commands(
		Input.get_axis(
			&"ship_throttle_reverse",
			&"ship_throttle_forward"
		),
		Input.get_axis(&"ship_rudder_right", &"ship_rudder_left"),
		Input.is_action_pressed(&"ship_fire_cannon")
			or Input.is_action_pressed(&"ship_fire"),
		Input.is_action_just_pressed(&"ship_fire_torpedo")
	)


func suspend_combat_input() -> void:
	var controlled_ship := selection.controlled_ship \
		if selection != null else null
	if controlled_ship != null and is_instance_valid(controlled_ship):
		controlled_ship.suspend_player_combat_input(true)


func clear_navigation_targets() -> void:
	if selection == null:
		return
	for ship in selection.get_selected_ships():
		ship.clear_navigation_target()
	if movement_marker != null:
		movement_marker.visible = false


func set_aim_point(point: Vector3) -> void:
	if selection == null:
		return
	for ship in selection.get_selected_ships():
		var command := manual_aim_resolver.create_command(
			ship,
			point
		)
		ship.apply_manual_aim_command(command)
	var controlled_ship := selection.controlled_ship
	if controlled_ship != null \
			and is_instance_valid(controlled_ship) \
			and controlled_ship.combat != null:
		var preview_command := controlled_ship.combat \
			.get_manual_aim_command()
		if preview_command != null:
			manual_aim_changed.emit(
				controlled_ship,
				preview_command
			)


func refresh_manual_aim_preview() -> void:
	var controlled_ship := selection.controlled_ship \
		if selection != null else null
	if controlled_ship == null \
			or not is_instance_valid(controlled_ship) \
			or controlled_ship.combat == null:
		manual_aim_cleared.emit(null)
		return
	var command := controlled_ship.combat.get_manual_aim_command()
	if command == null:
		manual_aim_cleared.emit(controlled_ship)
		return
	manual_aim_changed.emit(controlled_ship, command)


func adjust_turret_pitch(delta_degrees: float) -> void:
	if selection == null:
		return
	for ship in selection.get_selected_ships():
		ship.adjust_turret_pitch(delta_degrees)


func issue_move_command(center: Vector3) -> bool:
	if selection == null or formation_planner == null:
		return false
	var ships := selection.get_selected_ships()
	if ships.is_empty():
		return false
	var margin := rules.ship_command_margin_m if rules != null else 250.0
	var command_center := battlefield_bounds.clamp_to_bounds(center, margin) \
		if battlefield_bounds != null else center
	var positions := formation_planner.build_positions(
		command_center,
		ships.size(),
		formation_data
	)
	for index in ships.size():
		var target := positions[index]
		if battlefield_bounds != null:
			target = battlefield_bounds.clamp_to_bounds(target, margin)
		ships[index].set_navigation_target(target)
	if movement_marker != null:
		movement_marker.visible = true
		movement_marker.global_position = command_center \
			+ Vector3(0.0, 2.0, 0.0)
	move_command_issued.emit(command_center, ships)
	return true

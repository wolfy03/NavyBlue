extends Node
class_name CarrierCommandController

var camera: Camera3D
var panel: CarrierAirGroupPanel
var aircraft_selection_controller: AircraftSelectionController
var _selected_carrier_ref: WeakRef
var _selected_squadron_id := ""
var _targeting := false


func setup(
		next_camera: Camera3D,
		next_panel: CarrierAirGroupPanel,
		next_aircraft_selection_controller: AircraftSelectionController = null
) -> void:
	camera = next_camera
	panel = next_panel
	aircraft_selection_controller = next_aircraft_selection_controller
	if aircraft_selection_controller != null \
			and not aircraft_selection_controller.selection_changed \
				.is_connected(_on_aircraft_selection_changed):
		aircraft_selection_controller.selection_changed.connect(
			_on_aircraft_selection_changed
		)
	if panel != null \
			and not panel.strike_targeting_requested.is_connected(
				begin_strike_targeting
			):
		panel.strike_targeting_requested.connect(begin_strike_targeting)
	if panel != null \
			and not panel.manual_launch_requested.is_connected(
				_on_manual_launch_requested
			):
		panel.manual_launch_requested.connect(_on_manual_launch_requested)
	if panel != null \
			and not panel.active_squadron_selection_requested.is_connected(
				_on_active_squadron_selection_requested
			):
		panel.active_squadron_selection_requested.connect(
			_on_active_squadron_selection_requested
		)


func set_selected_carrier(carrier: ShipUnit) -> void:
	cancel_targeting()
	_selected_carrier_ref = weakref(carrier) \
		if _is_carrier(carrier) else null
	if panel != null:
		panel.set_selected_carrier(get_selected_carrier())


func begin_strike_targeting(squadron_id: String) -> bool:
	var carrier := get_selected_carrier()
	if carrier == null or carrier.carrier_air_group == null \
			or not carrier.carrier_air_group.can_launch_strike(squadron_id):
		return false
	_selected_squadron_id = squadron_id
	_targeting = true
	if panel != null:
		panel.set_targeting(true)
	return true


func cancel_targeting() -> void:
	_targeting = false
	_selected_squadron_id = ""
	if panel != null:
		panel.set_targeting(false)


func try_issue_strike(target_ship: ShipUnit) -> bool:
	if not _targeting:
		return false
	var carrier := get_selected_carrier()
	if carrier == null or target_ship == null \
			or not is_instance_valid(target_ship) \
			or not target_ship.is_alive() \
			or not carrier.is_hostile_to(target_ship):
		return false
	var squadron := carrier.carrier_air_group.launch_strike_squadron(
		_selected_squadron_id,
		target_ship,
		carrier.carrier_air_group.get_default_strike_mission(
			_selected_squadron_id
		)
	)
	if squadron == null:
		return false
	cancel_targeting()
	return true


func command_carrier_intercept(
		carrier: ShipUnit,
		target_squadron: AircraftSquadron,
		squadron_id: String
) -> bool:
	if not _is_carrier(carrier) \
			or target_squadron == null \
			or not is_instance_valid(target_squadron) \
			or carrier.carrier_air_group == null:
		return false
	return carrier.carrier_air_group.launch_intercept_squadron(
		squadron_id,
		target_squadron,
		carrier.carrier_air_group.get_default_mission(squadron_id)
	) != null


func is_targeting() -> bool:
	return _targeting


func get_selected_carrier() -> ShipUnit:
	if _selected_carrier_ref == null:
		return null
	var carrier := _selected_carrier_ref.get_ref() as ShipUnit
	return carrier if _is_carrier(carrier) else null


static func _is_carrier(candidate: ShipUnit) -> bool:
	return candidate != null \
		and is_instance_valid(candidate) \
		and candidate.is_alive() \
		and candidate.player_controlled \
		and candidate.ship_data != null \
		and candidate.ship_data.carrier_air_group_data != null \
		and candidate.carrier_air_group != null


func _on_manual_launch_requested(squadron_id: String) -> void:
	var carrier := get_selected_carrier()
	if carrier == null or carrier.carrier_air_group == null:
		return
	var squadron := carrier.carrier_air_group.launch_manual_squadron(
		squadron_id
	)
	if squadron != null and aircraft_selection_controller != null:
		aircraft_selection_controller.select_squadron(squadron)


func _on_active_squadron_selection_requested(
		squadron: AircraftSquadron
) -> void:
	if aircraft_selection_controller != null:
		aircraft_selection_controller.select_squadron(squadron)


func _on_aircraft_selection_changed(
		squadrons: Array[AircraftSquadron]
) -> void:
	if panel != null:
		panel.set_world_selected_squadrons(squadrons)

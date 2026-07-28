extends Node
class_name CarrierCommandController

var camera: Camera3D
var panel: CarrierAirGroupPanel
var _selected_carrier_ref: WeakRef
var _selected_squadron_id := ""
var _targeting := false


func setup(
		next_camera: Camera3D,
		next_panel: CarrierAirGroupPanel
) -> void:
	camera = next_camera
	panel = next_panel
	if panel != null \
			and not panel.strike_targeting_requested.is_connected(
				begin_strike_targeting
			):
		panel.strike_targeting_requested.connect(begin_strike_targeting)


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

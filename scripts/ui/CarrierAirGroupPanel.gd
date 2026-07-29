extends PanelContainer
class_name CarrierAirGroupPanel

signal strike_targeting_requested(squadron_id: String)
signal manual_launch_requested(squadron_id: String)
signal active_squadron_selection_requested(squadron: AircraftSquadron)
signal aircraft_command_requested

@export var debug_air_group_data := false

@onready var title_label: Label = %TitleLabel
@onready var squadron_selector: OptionButton = %SquadronSelector
@onready var status_label: Label = %StatusLabel
@onready var strike_button: Button = %StrikeButton
@onready var manual_launch_button: Button = %ManualLaunchButton
@onready var select_active_button: Button = %SelectActiveButton
@onready var return_button: Button = %ReturnButton
@onready var return_all_button: Button = %ReturnAllButton
@onready var targeting_label: Label = %TargetingLabel

var _carrier_ref: WeakRef
var _refresh_left := 0.0
var _selected_squadron_id := ""
var _targeting := false
var _missing_data_warnings: Dictionary = {}


func _ready() -> void:
	visible = false
	strike_button.pressed.connect(_on_strike_pressed)
	manual_launch_button.pressed.connect(_on_manual_launch_pressed)
	select_active_button.pressed.connect(_on_select_active_pressed)
	return_button.pressed.connect(_on_return_pressed)
	return_all_button.pressed.connect(_on_return_all_pressed)
	squadron_selector.item_selected.connect(_on_squadron_selected)


func _process(delta: float) -> void:
	_refresh_left -= maxf(delta, 0.0)
	if _refresh_left <= 0.0:
		_refresh_left = 0.2
		_refresh_status()


func set_selected_carrier(carrier: ShipUnit) -> void:
	var previous := _get_carrier()
	if previous == carrier:
		visible = carrier != null \
			and is_instance_valid(carrier) \
			and carrier.carrier_air_group != null
		if not visible:
			_selected_squadron_id = ""
			squadron_selector.clear()
			set_targeting(false)
		return
	_disconnect_carrier(previous)
	_carrier_ref = weakref(carrier) \
		if carrier != null and is_instance_valid(carrier) else null
	var selected := _get_carrier()
	if selected != null and selected.carrier_air_group != null:
		_connect_carrier(selected)
		_rebuild_squadron_selector()
		visible = true
	else:
		_selected_squadron_id = ""
		squadron_selector.clear()
		visible = false
	set_targeting(false)
	_refresh_status()


func set_targeting(active: bool) -> void:
	_targeting = active
	if targeting_label != null:
		targeting_label.visible = active
		targeting_label.text = "Select an enemy ship" if active else ""


func get_selected_squadron_id() -> String:
	return _selected_squadron_id


func set_world_selected_squadrons(
		squadrons: Array[AircraftSquadron]
) -> void:
	var carrier := _get_carrier()
	if carrier == null:
		return
	for squadron in squadrons:
		if squadron != null \
				and is_instance_valid(squadron) \
				and squadron.get_owner_carrier() == carrier \
				and squadron.squadron_data != null:
			_select_squadron_id(squadron.squadron_data.id)
			return


func _refresh_status() -> void:
	var carrier := _get_carrier()
	if carrier == null or carrier.carrier_air_group == null:
		visible = false
		return
	visible = true
	var air_group := carrier.carrier_air_group
	if _selected_squadron_id.is_empty() \
			or air_group.get_squadron_data(_selected_squadron_id) == null:
		_rebuild_squadron_selector()
	var snapshot := air_group.get_squadron_status_snapshot(
		_selected_squadron_id
	)
	var state_data: Dictionary = snapshot.get("state", {})
	if state_data.is_empty():
		status_label.text = "No squadron data"
		strike_button.disabled = true
		return
	var availability := int(state_data.get(
		"availability_state",
		SquadronRuntimeState.AvailabilityState.DESTROYED
	))
	var state_name := str(SquadronRuntimeState.AvailabilityState.keys()[
		clampi(
			availability,
			0,
			SquadronRuntimeState.AvailabilityState.size() - 1
		)
	])
	var role_name := _aircraft_role_name(
		int(snapshot.get("aircraft_role", -1))
	)
	var mission_text := str(snapshot.get("mission_id", ""))
	if mission_text.is_empty():
		mission_text = "None"
	var target_text := str(snapshot.get("target_name", ""))
	if target_text.is_empty():
		target_text = "None"
	status_label.text = (
		"%s | %s\n"
		+ "%s\n"
		+ "Ready %d  Active %d  Lost %d\n"
		+ "%s  Rearm %.1fs\n"
		+ "Mission %s  Target %s\n"
		+ "Ammunition %d active / %d per aircraft"
	) % [
		str(snapshot.get("display_name", _selected_squadron_id)),
		role_name,
		str(snapshot.get("weapon_name", "Unarmed")),
		int(state_data.get("available_aircraft", 0)),
		int(state_data.get("active_aircraft", 0)),
		int(state_data.get("lost_aircraft", 0)),
		state_name,
		float(state_data.get("rearm_time_left", 0.0)),
		mission_text,
		target_text,
		int(snapshot.get("active_ammunition", 0)),
		int(snapshot.get("ammunition_per_aircraft", 0)),
	]
	var role := int(snapshot.get("aircraft_role", -1))
	strike_button.visible = role \
		== AircraftData.AircraftRole.DIVE_BOMBER
	strike_button.disabled = _targeting \
		or not air_group.can_launch_strike(_selected_squadron_id)
	manual_launch_button.disabled = _targeting \
		or not air_group.can_launch_squadron(_selected_squadron_id)
	select_active_button.disabled = air_group \
		.get_active_squadron_by_id(_selected_squadron_id) == null
	return_button.disabled = int(state_data.get("active_aircraft", 0)) <= 0
	return_all_button.disabled = air_group.get_active_squadron_count() <= 0


func _rebuild_squadron_selector() -> void:
	var carrier := _get_carrier()
	squadron_selector.clear()
	if carrier == null or carrier.carrier_air_group == null:
		_selected_squadron_id = ""
		return
	var states := carrier.carrier_air_group.get_all_squadron_states()
	for state in states:
		var data := carrier.carrier_air_group.get_squadron_data(
			state.squadron_id
		)
		if data == null:
			if not _missing_data_warnings.has(state.squadron_id):
				_missing_data_warnings[state.squadron_id] = true
				push_warning(
					"Carrier panel cannot resolve squadron data: %s"
					% state.squadron_id
				)
			continue
		var role_name := _aircraft_role_name(
			int(data.aircraft_data.role) \
			if data.aircraft_data != null else -1
		)
		squadron_selector.add_item(
			"%s [%s]" % [data.display_name, role_name]
		)
		squadron_selector.set_item_metadata(
			squadron_selector.item_count - 1,
			state.squadron_id
		)
	if squadron_selector.item_count > 0:
		var selected_index := 0
		for index in squadron_selector.item_count:
			if str(squadron_selector.get_item_metadata(index)) \
					== _selected_squadron_id:
				selected_index = index
				break
		squadron_selector.select(selected_index)
		_selected_squadron_id = str(
			squadron_selector.get_item_metadata(selected_index)
		)
	else:
		_selected_squadron_id = ""
		if debug_air_group_data:
			var snapshot := carrier.carrier_air_group \
				.get_debug_snapshot()
			status_label.text = (
				"Air group templates: %d\nRuntime squadrons: %d"
				% [
					int(snapshot.get("template_count", 0)),
					(snapshot.get("runtime_state_ids", []) as Array).size(),
				]
			)


func _connect_carrier(carrier: ShipUnit) -> void:
	var air_group := carrier.carrier_air_group
	if not air_group.squadron_state_changed.is_connected(
		_on_squadron_state_changed
	):
		air_group.squadron_state_changed.connect(
			_on_squadron_state_changed
		)
	for signal_value in [
		air_group.squadron_launched,
		air_group.squadron_recovered,
		air_group.squadron_destroyed,
	]:
		if not signal_value.is_connected(_on_squadron_lifecycle_changed):
			signal_value.connect(_on_squadron_lifecycle_changed)


func _disconnect_carrier(carrier: ShipUnit) -> void:
	if carrier == null or not is_instance_valid(carrier) \
			or carrier.carrier_air_group == null:
		return
	var air_group := carrier.carrier_air_group
	if air_group.squadron_state_changed.is_connected(
		_on_squadron_state_changed
	):
		air_group.squadron_state_changed.disconnect(
			_on_squadron_state_changed
		)
	for signal_value in [
		air_group.squadron_launched,
		air_group.squadron_recovered,
		air_group.squadron_destroyed,
	]:
		if signal_value.is_connected(_on_squadron_lifecycle_changed):
			signal_value.disconnect(_on_squadron_lifecycle_changed)


func _on_squadron_state_changed(
		_squadron_id: String,
		_state: SquadronRuntimeState
) -> void:
	_refresh_left = 0.0


func _on_squadron_lifecycle_changed(_squadron: Variant) -> void:
	_refresh_left = 0.0


func _on_squadron_selected(index: int) -> void:
	_selected_squadron_id = str(
		squadron_selector.get_item_metadata(index)
	)
	_refresh_status()
	_emit_active_squadron_selection()


func _on_strike_pressed() -> void:
	if not _selected_squadron_id.is_empty():
		aircraft_command_requested.emit()
		strike_targeting_requested.emit(_selected_squadron_id)


func _on_manual_launch_pressed() -> void:
	if not _selected_squadron_id.is_empty():
		aircraft_command_requested.emit()
		manual_launch_requested.emit(_selected_squadron_id)


func _on_select_active_pressed() -> void:
	aircraft_command_requested.emit()
	_emit_active_squadron_selection()


func _emit_active_squadron_selection() -> void:
	var carrier := _get_carrier()
	if carrier == null or carrier.carrier_air_group == null:
		return
	var squadron := carrier.carrier_air_group.get_active_squadron_by_id(
		_selected_squadron_id
	)
	if squadron != null:
		active_squadron_selection_requested.emit(squadron)


func _select_squadron_id(squadron_id: String) -> void:
	for index in squadron_selector.item_count:
		if str(squadron_selector.get_item_metadata(index)) \
				== squadron_id:
			squadron_selector.select(index)
			_selected_squadron_id = squadron_id
			_refresh_status()
			return


func _on_return_pressed() -> void:
	var carrier := _get_carrier()
	if carrier != null and carrier.carrier_air_group != null:
		carrier.carrier_air_group.request_squadron_return_by_id(
			_selected_squadron_id
		)


func _on_return_all_pressed() -> void:
	var carrier := _get_carrier()
	if carrier != null:
		carrier.recall_air_squadrons()


func _get_carrier() -> ShipUnit:
	if _carrier_ref == null:
		return null
	var carrier := _carrier_ref.get_ref() as ShipUnit
	return carrier if carrier != null and is_instance_valid(carrier) else null


static func _aircraft_role_name(role: int) -> String:
	if role < 0 or role >= AircraftData.AircraftRole.size():
		return "Unknown"
	return AircraftData.AircraftRole.keys()[role].capitalize()

extends RefCounted
class_name RunShipStateRestorer

var run_session: RunSessionReader


func setup(next_run_session: RunSessionReader) -> void:
	shutdown()
	run_session = next_run_session


func shutdown() -> void:
	run_session = null


func get_player_weapon_loadout(ship_id: StringName) -> ShipWeaponLoadout:
	var state := _get_matching_player_state(ship_id)
	var value: Variant = state.get("weapon_loadout", null)
	if value is ShipWeaponLoadout:
		return (value as ShipWeaponLoadout).duplicate_loadout()
	if value is Dictionary and not value.is_empty():
		return ShipWeaponLoadout.from_dictionary(value)
	return null


func get_player_weapon_runtime_stats(
		ship_id: StringName
) -> Dictionary:
	var state := _get_matching_player_state(ship_id)
	var value: Variant = state.get("weapon_runtime_stats", {})
	return (value as Dictionary).duplicate(true) \
		if value is Dictionary else {}


func restore_player_ship(ship: ShipUnit) -> void:
	if ship == null or run_session == null:
		return
	var state := _get_matching_player_state(
		StringName(ship.ship_data.id) if ship.ship_data != null else &""
	)
	if not state.is_empty():
		ship.restore_run_state(state.duplicate(true))
	run_session.restore_carrier_air_group(ship)


func _get_matching_player_state(ship_id: StringName) -> Dictionary:
	if run_session == null:
		return {}
	var state := run_session.get_player_ship_state()
	var saved_ship_id := StringName(str(state.get("ship_id", "")))
	if not saved_ship_id.is_empty() and saved_ship_id != ship_id:
		return {}
	return state

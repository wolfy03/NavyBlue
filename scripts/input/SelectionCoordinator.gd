extends RefCounted
class_name SelectionCoordinator

signal selection_changed(selected_ships: Array[ShipUnit])

var controlled_ship: ShipUnit
var selected_ships: Array[ShipUnit] = []


func setup(ship: ShipUnit) -> void:
	controlled_ship = ship
	select_only(ship)


func select_only(ship: ShipUnit) -> void:
	selected_ships.clear()
	if ship != null and is_instance_valid(ship):
		selected_ships.append(ship)
	selection_changed.emit(get_selected_ships())


func toggle(ship: ShipUnit) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	var index := selected_ships.find(ship)
	if index >= 0:
		selected_ships.remove_at(index)
	else:
		selected_ships.append(ship)
	selection_changed.emit(get_selected_ships())


func prune() -> bool:
	var changed := false
	for index in range(selected_ships.size() - 1, -1, -1):
		if not is_instance_valid(selected_ships[index]):
			selected_ships.remove_at(index)
			changed = true
	if changed:
		selection_changed.emit(get_selected_ships())
	return changed


func get_selected_ships() -> Array[ShipUnit]:
	prune()
	return selected_ships.duplicate()

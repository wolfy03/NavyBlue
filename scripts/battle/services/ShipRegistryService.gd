extends RefCounted
class_name ShipRegistryService
## Battle-wide ship roster. Ships register on setup and unregister when they
## sink or leave the tree, so target-selection code reads a maintained list
## instead of walking the SceneTree on every query.
##
## Holds only weak references: the registry can never keep a freed ship
## alive, and stale entries are pruned lazily on read.

var _ship_refs: Dictionary = {}


func register_ship(ship: ShipUnit) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	_ship_refs[ship.get_instance_id()] = weakref(ship)


func unregister_ship(ship: ShipUnit) -> void:
	if ship == null:
		return
	_ship_refs.erase(ship.get_instance_id())


## Every registered ship that is still valid and alive. Insertion order is
## preserved, which keeps downstream deterministic tie-breaks stable.
func get_alive_ships() -> Array[ShipUnit]:
	var result: Array[ShipUnit] = []
	var stale_ids: Array[int] = []
	for instance_id in _ship_refs.keys():
		var ship_ref := _ship_refs[instance_id] as WeakRef
		var value: Variant = ship_ref.get_ref() if ship_ref != null else null
		if value == null or not is_instance_valid(value):
			stale_ids.append(int(instance_id))
			continue
		var ship := value as ShipUnit
		if ship == null or not ship.is_alive():
			continue
		result.append(ship)
	for stale_id in stale_ids:
		_ship_refs.erase(stale_id)
	return result


func get_hostile_ships_for_team(team: StringName) -> Array[ShipUnit]:
	var result: Array[ShipUnit] = []
	for ship in get_alive_ships():
		if FactionRelations.are_hostile(team, ship.team):
			result.append(ship)
	return result


func get_registered_count() -> int:
	return _ship_refs.size()


func clear() -> void:
	_ship_refs.clear()

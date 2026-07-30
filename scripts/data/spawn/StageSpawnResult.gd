extends RefCounted
class_name StageSpawnResult

var player_ship: ShipUnit
var allies: Array[ShipUnit] = []
var enemies: Array[ShipUnit] = []
var errors := PackedStringArray()


static func failed(next_errors: PackedStringArray) -> StageSpawnResult:
	var result := StageSpawnResult.new()
	result.errors = next_errors.duplicate()
	return result


func get_all_ships() -> Array[ShipUnit]:
	var result: Array[ShipUnit] = []
	if player_ship != null:
		result.append(player_ship)
	result.append_array(allies)
	result.append_array(enemies)
	return result

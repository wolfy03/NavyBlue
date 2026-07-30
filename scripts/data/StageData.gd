extends Resource
class_name StageData

@export var id: String = "test_level"
@export var display_name: String = "Test Level"
@export var sea_id: String = "test_sea"
@export var difficulty: float = 1.0
@export var player_spawn: ShipSpawnData
@export var ally_spawns: Array[ShipSpawnData] = []
@export var enemy_spawns: Array[ShipSpawnData] = []
@export var reward_table_id: String = "test_rewards"
@export var next_stage_candidates: Array[String] = []


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var spawn_names: Dictionary = {}
	_validate_spawn(
		player_spawn,
		"player_spawn",
		true,
		errors,
		spawn_names
	)
	for index in ally_spawns.size():
		_validate_spawn(
			ally_spawns[index],
			"ally_spawns[%d]" % index,
			false,
			errors,
			spawn_names
		)
	for index in enemy_spawns.size():
		_validate_spawn(
			enemy_spawns[index],
			"enemy_spawns[%d]" % index,
			false,
			errors,
			spawn_names
		)
	return errors


func _validate_spawn(
		spawn: ShipSpawnData,
		label: String,
		expect_player: bool,
		errors: PackedStringArray,
		spawn_names: Dictionary
) -> void:
	if spawn == null:
		errors.append("%s must be a ShipSpawnData Resource." % label)
		return
	errors.append_array(spawn.validate(expect_player, label))
	var spawn_name := spawn.display_name \
		if not spawn.display_name.is_empty() \
		else String(spawn.spawn_marker_id)
	if spawn_name.is_empty():
		return
	if spawn_names.has(spawn_name):
		errors.append("Duplicate spawn name: %s" % spawn_name)
	else:
		spawn_names[spawn_name] = true

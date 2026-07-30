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
	var marker_names: Dictionary = {}
	_validate_spawn(
		player_spawn,
		"player_spawn",
		ShipSpawnData.SpawnRole.PLAYER,
		errors,
		spawn_names,
		marker_names
	)
	for index in ally_spawns.size():
		_validate_spawn(
			ally_spawns[index],
			"ally_spawns[%d]" % index,
			ShipSpawnData.SpawnRole.ALLY,
			errors,
			spawn_names,
			marker_names
		)
	for index in enemy_spawns.size():
		_validate_spawn(
			enemy_spawns[index],
			"enemy_spawns[%d]" % index,
			ShipSpawnData.SpawnRole.ENEMY,
			errors,
			spawn_names,
			marker_names
		)
	return errors


func _validate_spawn(
		spawn: ShipSpawnData,
		label: String,
		expected_role: ShipSpawnData.SpawnRole,
		errors: PackedStringArray,
		spawn_names: Dictionary,
		marker_names: Dictionary
) -> void:
	if spawn == null:
		errors.append("%s must be a ShipSpawnData Resource." % label)
		return
	errors.append_array(spawn.validate(expected_role, label))
	if not spawn.display_name.is_empty():
		if spawn_names.has(spawn.display_name):
			errors.append("Duplicate spawn display_name: %s" % spawn.display_name)
		else:
			spawn_names[spawn.display_name] = true
	if not spawn.spawn_marker_id.is_empty():
		if marker_names.has(spawn.spawn_marker_id):
			errors.append(
				"Duplicate spawn marker: %s" % spawn.spawn_marker_id
			)
		else:
			marker_names[spawn.spawn_marker_id] = true

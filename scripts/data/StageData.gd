extends Resource
class_name StageData

@export var id: String = "test_level"
@export var display_name: String = "Test Level"
@export var sea_id: String = "test_sea"
@export var difficulty: float = 1.0
@export var player_ship_id: String = GameConfig.DEFAULT_PLAYER_SHIP_ID
@export var player_spawn: Dictionary = {}
@export var ally_spawns: Array = []
@export var enemy_spawns: Array = []
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
	if player_ship_id.is_empty():
		errors.append("player_ship_id must not be empty.")
	elif not ShipDatabase.SHIP_PATHS.has(player_ship_id):
		errors.append("Unsupported player_ship_id: %s" % player_ship_id)
	return errors


func _validate_spawn(
		value: Variant,
		label: String,
		expect_player: bool,
		errors: PackedStringArray,
		spawn_names: Dictionary
) -> void:
	if not value is Dictionary:
		errors.append("%s must be a Dictionary." % label)
		return
	var spawn := value as Dictionary
	var ship_id := str(spawn.get("ship_id", ""))
	if ship_id.is_empty():
		errors.append("%s is missing ship_id." % label)
	elif not ShipDatabase.SHIP_PATHS.has(ship_id):
		errors.append("%s has unsupported ship_id '%s'." % [label, ship_id])
	var team := str(spawn.get("team", ""))
	if team.is_empty():
		errors.append("%s is missing team." % label)
	elif team not in ["player", "ally", "enemy", "neutral"]:
		errors.append("%s has unsupported team '%s'." % [label, team])
	if not spawn.has("is_player") \
			or bool(spawn.get("is_player", false)) != expect_player:
		errors.append(
			"%s must set is_player=%s." % [label, expect_player]
		)
	if not spawn.get("position", null) is Vector3:
		errors.append("%s position must be Vector3." % label)
	var rotation: Variant = spawn.get("rotation_y", null)
	if not rotation is int and not rotation is float:
		errors.append("%s rotation_y must be numeric." % label)
	var spawn_name := str(spawn.get("name", ""))
	if spawn_name.is_empty():
		errors.append("%s is missing name." % label)
	elif spawn_names.has(spawn_name):
		errors.append("Duplicate spawn name: %s" % spawn_name)
	else:
		spawn_names[spawn_name] = true

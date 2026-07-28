extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const WEAPON_STAGE: StageData = preload(
	"res://resources/stages/tests/weapon_combat_test.tres"
)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = WEAPON_STAGE
	root.add_child(battle)
	await process_frame
	await physics_frame
	var player := battle.player_ship as ShipUnit
	var enemy := battle.enemies[0] as ShipUnit \
		if not battle.enemies.is_empty() else null
	_check(
		player != null and player.team == FactionRelations.PLAYER \
			and player.player_controlled,
		"spawned player receives team and command authority"
	)
	_check(
		enemy != null and enemy.team == FactionRelations.ENEMY \
			and not enemy.player_controlled,
		"spawned enemy receives team and AI authority"
	)
	if player != null:
		for mount in player.get_weapon_mounts():
			_check(
				mount.owner_team == FactionRelations.PLAYER,
				"player weapon mount inherits owner team"
			)
	if enemy != null:
		for mount in enemy.get_weapon_mounts():
			_check(
				mount.owner_team == FactionRelations.ENEMY,
				"enemy weapon mount inherits owner team"
			)
	battle.queue_free()
	await process_frame
	_finish()


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	for failure in _failures:
		push_error("WEAPON TEAM INITIALIZATION TEST: %s" % failure)
	print(
		"WEAPON_TEAM_INITIALIZATION_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)

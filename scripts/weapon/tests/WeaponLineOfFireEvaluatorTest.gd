extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_player_test.tres"
)

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = STAGE
	root.add_child(battle)
	await process_frame
	var carrier := battle.player_ship
	var ally := battle.allies[0] as ShipUnit
	var enemy := battle.enemies[0] as ShipUnit
	var mounts := carrier.combat.get_secondary_cannon_mounts()
	_check(not mounts.is_empty(), "fixture has a secondary mount")
	if not mounts.is_empty():
		carrier.set_physics_process(false)
		ally.set_physics_process(false)
		enemy.set_physics_process(false)
		var mount := mounts[0]
		var evaluator := WeaponLineOfFireEvaluator.new()
		var clear_result := evaluator.evaluate(
			mount,
			enemy,
			enemy.global_position
		)
		_check(clear_result.safe, "clear hostile firing line is accepted")
		var blocker := StaticBody3D.new()
		var blocker_shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(100.0, 100.0, 100.0)
		blocker_shape.shape = box
		blocker.add_child(blocker_shape)
		ally.add_child(blocker)
		blocker.global_position = mount.get_muzzle_position().lerp(
			enemy.global_position,
			0.5
		)
		await physics_frame
		var blocked_result := evaluator.evaluate(
			mount,
			enemy,
			enemy.global_position
		)
		_check(
			not blocked_result.safe \
				and blocked_result.blocked_reason == &"friendly_blocked",
			"friendly ship on the muzzle line blocks automatic fire"
		)
	battle.shutdown()
	battle.queue_free()
	await process_frame
	print("WEAPON_LINE_OF_FIRE_EVALUATOR_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if condition:
		return
	_failures.append(description)
	push_error("WEAPON LINE OF FIRE: %s" % description)

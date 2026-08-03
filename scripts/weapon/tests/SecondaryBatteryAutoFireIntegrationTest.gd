extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_player_test.tres"
)
const PLAYER_PROFILE: AIGunneryDifficultyProfile = preload(
	"res://resources/ai_difficulty/gunnery_normal.tres"
)

var _failures := PackedStringArray()
var _fired_count := 0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = STAGE
	root.add_child(battle)
	await process_frame
	var carrier := battle.player_ship
	# Keep this fixture inside the configured 4.5 km secondary range. The stage
	# itself remains a general carrier-flow fixture with a 5 km separation.
	if carrier != null and not battle.enemies.is_empty():
		var enemy := battle.enemies[0]
		if enemy != null and is_instance_valid(enemy):
			var toward_carrier := carrier.global_position - enemy.global_position
			toward_carrier.y = 0.0
			if toward_carrier.length_squared() > 0.0001:
				enemy.global_position = carrier.global_position \
					- toward_carrier.normalized() * 3800.0
	var controller := carrier.combat.get_secondary_battery_controller() \
		if carrier != null else null
	_check(controller != null, "player carrier owns a secondary controller")
	if controller != null:
		_check(
			controller.fire_control.difficulty_profile == PLAYER_PROFILE,
			"player automatic secondaries use the player Normal profile"
		)
		for mount in carrier.combat.get_secondary_cannon_mounts():
			mount.fired.connect(_on_secondary_fired)
	for _frame in 600:
		await physics_frame
		if _fired_count > 0:
			break
	_check(
		controller != null and controller.get_current_target() != null,
		"player carrier automatically selects an enemy"
	)
	_check(_fired_count > 0, "secondary battery fires through CannonMount")
	_check(
		carrier.combat.get_ai_fire_control() == null,
		"automatic secondaries do not create main AI fire control"
	)
	battle.shutdown()
	battle.queue_free()
	await process_frame
	print(
		"SECONDARY_BATTERY_AUTO_FIRE_INTEGRATION_TEST failures=%d fired=%d"
		% [_failures.size(), _fired_count]
	)
	quit(0 if _failures.is_empty() else 1)


func _on_secondary_fired(_projectile: Node) -> void:
	_fired_count += 1


func _check(condition: bool, description: String) -> void:
	if condition:
		return
	_failures.append(description)
	push_error("SECONDARY BATTERY AUTO FIRE: %s" % description)

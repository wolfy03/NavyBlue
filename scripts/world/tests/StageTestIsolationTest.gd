extends SceneTree

const WEAPON_STAGE: StageData = preload(
	"res://resources/stages/tests/weapon_combat_test.tres"
)
const CARRIER_PLAYER_STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_player_test.tres"
)
const CARRIER_AI_STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_ai_test.tres"
)
const BATTLE_LOOP_STAGE: StageData = preload(
	"res://resources/stages/tests/battle_loop_test.tres"
)

var _failures: Array[String] = []


func _initialize() -> void:
	_check(
		WEAPON_STAGE.player_ship_id == "dd_bluewind" \
			and not _contains_ship(WEAPON_STAGE.ally_spawns, "cv_seabastion"),
		"weapon stage is carrier-independent"
	)
	_check(
		CARRIER_PLAYER_STAGE.player_ship_id == "cv_seabastion" \
			and bool(CARRIER_PLAYER_STAGE.player_spawn.get(
				"is_player",
				false
			)),
		"carrier player stage owns the player carrier"
	)
	_check(
		CARRIER_AI_STAGE.player_ship_id == "dd_bluewind" \
			and _contains_ship(
				CARRIER_AI_STAGE.ally_spawns,
				"cv_seabastion"
			),
		"carrier AI stage owns a non-player allied carrier"
	)
	_check(
		BATTLE_LOOP_STAGE.player_ship_id == "dd_bluewind" \
			and BATTLE_LOOP_STAGE.enemy_spawns.size() == 3,
		"battle loop stage preserves the general battle fixture"
	)
	_finish()


func _contains_ship(spawns: Array, ship_id: String) -> bool:
	for value in spawns:
		if value is Dictionary \
				and str(value.get("ship_id", "")) == ship_id:
			return true
	return false


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	for failure in _failures:
		push_error("STAGE TEST ISOLATION TEST: %s" % failure)
	print(
		"STAGE_TEST_ISOLATION_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)

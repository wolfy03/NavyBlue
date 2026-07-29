extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_player_test.tres"
)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = STAGE
	root.add_child(battle)
	var input := battle.input_manager as PlayerInputManager
	var ship := battle.player_ship as ShipUnit
	_check(
		input.get_command_mode() == PlayerInputManager.CommandMode.SHIP,
		"battle starts in ship command mode"
	)
	_check(
		not battle.aircraft_selection_controller.is_input_enabled(),
		"aircraft selection is isolated while ship mode is active"
	)
	ship.set_player_commands(0.75, 1.0, true, true)
	input.set_command_mode(PlayerInputManager.CommandMode.AIRCRAFT)
	_check(
		battle.aircraft_selection_controller.is_input_enabled(),
		"aircraft mode enables aircraft selection"
	)
	_check(
		is_equal_approx(float(ship.get("_player_throttle_axis")), 0.75),
		"aircraft mode preserves current ship throttle"
	)
	_check(
		is_zero_approx(float(ship.get("_player_rudder_axis"))) \
			and not bool(ship.get("_player_cannon_fire_pressed")) \
			and not bool(ship.get("_player_torpedo_fire_pressed")),
		"aircraft mode neutralizes ship rudder and weapon input"
	)
	input.set_command_mode(PlayerInputManager.CommandMode.SHIP)
	_check(
		not battle.aircraft_selection_controller.is_input_enabled(),
		"returning to ship mode disables aircraft world commands"
	)
	battle.carrier_air_group_panel.aircraft_command_requested.emit()
	_check(
		input.get_command_mode() == PlayerInputManager.CommandMode.AIRCRAFT,
		"carrier UI commands enter aircraft command mode"
	)
	_check(
		battle.hud.mode_label.text == "AIRCRAFT COMMAND",
		"HUD reflects the active command mode"
	)
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("COMMAND MODE TOGGLE TEST: %s" % failure)
	print(
		"COMMAND_MODE_TOGGLE_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)

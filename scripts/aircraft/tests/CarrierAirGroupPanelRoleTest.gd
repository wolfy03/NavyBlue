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
	var carrier := battle.player_ship as ShipUnit
	var panel := battle.carrier_air_group_panel
	panel.set_selected_carrier(carrier)
	var selector := panel.squadron_selector
	var ids: Array[String] = []
	for index in selector.item_count:
		ids.append(str(selector.get_item_metadata(index)))
	_check(selector.item_count == 3, "carrier panel has three squadron rows")
	_check(
		ids.has("basic_bomber_squadron"),
		"carrier panel lists the dive bomber squadron"
	)
	_check(
		ids.has("basic_fighter_squadron"),
		"carrier panel lists the fighter squadron"
	)
	_check(
		ids.has("basic_torpedo_squadron"),
		"carrier panel lists the torpedo bomber squadron"
	)
	var torpedo_index := ids.find("basic_torpedo_squadron")
	if torpedo_index >= 0:
		panel.squadron_selector.select(torpedo_index)
		panel._on_squadron_selected(torpedo_index)
		_check(
			"Torpedo Bomber" in panel.squadron_selector.get_item_text(
				torpedo_index
			),
			"torpedo bomber row displays its role"
		)
		_check(
			panel.strike_button.visible,
			"torpedo bomber selection exposes Auto Strike"
		)
	var fighter_index := ids.find("basic_fighter_squadron")
	if fighter_index >= 0:
		panel.squadron_selector.select(fighter_index)
		panel._on_squadron_selected(fighter_index)
		_check(
			"Fighter" in panel.squadron_selector.get_item_text(
				fighter_index
			),
			"fighter row displays its role"
		)
		_check(
			not panel.strike_button.visible,
			"fighter selection hides Auto Strike"
		)
		_check(
			not panel.manual_launch_button.disabled,
			"fighter selection enables Manual Launch"
		)
	var fighter := carrier.carrier_air_group.launch_manual_squadron(
		"basic_fighter_squadron"
	)
	_check(
		fighter != null and fighter.is_player_commanded(),
		"fighter manual launch uses player command authority"
	)
	_check(
		fighter != null \
			and fighter.mission_controller.mission_data == null,
		"manual fighter launch has no automatic intercept mission"
	)
	if fighter != null:
		panel._refresh_status()
		_check(
			not panel.select_active_button.disabled,
			"active fighter can be selected from the panel"
		)
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("CARRIER AIR GROUP PANEL ROLE TEST: %s" % failure)
	print(
		"CARRIER_AIR_GROUP_PANEL_ROLE_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)

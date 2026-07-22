extends SceneTree

var _failures: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var battle_scene := load("res://scenes/world/battle_scene.tscn") as PackedScene
	var battle: Node = battle_scene.instantiate()
	root.add_child(battle)
	for _frame: int in 4:
		await process_frame

	var overlay_root := battle.get_node("HUD/ShipStatusOverlayRoot") as Control
	_expect_equal("indicator count", overlay_root.get_child_count(), 6)
	var visible_count: int = 0
	for child: Node in overlay_root.get_children():
		var indicator := child as ShipStatusIndicator
		if indicator != null and indicator.visible:
			visible_count += 1
			_expect_true("minimum indicator width", indicator.size.x >= indicator.minimum_frame_size.x)
			_expect_true("health bar space", indicator.size.y > indicator.minimum_frame_size.y)
	_expect_true("visible indicator", visible_count > 0)

	var player_ship: Node3D = battle.get("player_ship") as Node3D
	var player_indicator: ShipStatusIndicator = _find_indicator(overlay_root, player_ship)
	_expect_true("player indicator", player_indicator != null)
	if player_indicator != null:
		var health: ShipHealth = player_ship.get_node("ShipHealth") as ShipHealth
		health.apply_damage(20.0)
		await process_frame
		var stats: ShipDefenseStats = health.get_defense_stats()
		var expected_ratio: float = stats.current_hp / stats.max_hp
		_expect_approx("health ratio", float(player_indicator.get("_health_ratio")), expected_ratio)
		var state_label := player_indicator.get_node("StatusPanel/StatusLabel") as Label
		_expect_true("player status", state_label.text == "CMD")

	if _failures == 0:
		print("SHIP_STATUS_INDICATOR_TEST PASS indicators=%d visible=%d" % [
			overlay_root.get_child_count(),
			visible_count,
		])
		battle.queue_free()
		quit(0)
		return
	push_error("SHIP_STATUS_INDICATOR_TEST FAILURES=%d" % _failures)
	battle.queue_free()
	quit(1)


func _find_indicator(overlay_root: Control, ship: Node3D) -> ShipStatusIndicator:
	for child: Node in overlay_root.get_children():
		var indicator := child as ShipStatusIndicator
		if indicator != null and indicator.target_ship == ship:
			return indicator
	return null


func _expect_equal(label: String, actual: int, expected: int) -> void:
	if actual == expected:
		return
	_failures += 1
	push_error("%s expected %d, got %d" % [label, expected, actual])


func _expect_true(label: String, condition: bool) -> void:
	if condition:
		return
	_failures += 1
	push_error("%s failed" % label)


func _expect_approx(label: String, actual: float, expected: float) -> void:
	if is_equal_approx(actual, expected):
		return
	_failures += 1
	push_error("%s expected %.4f, got %.4f" % [label, expected, actual])

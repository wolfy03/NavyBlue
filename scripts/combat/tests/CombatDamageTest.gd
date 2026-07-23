extends SceneTree

const EPSILON: float = 0.001

var _failures: int = 0


class DamageTarget:
	extends Node3D

	var health: ShipHealth
	var sink_called: bool = false

	func configure(stats: ShipDefenseStats) -> void:
		health = ShipHealth.new()
		health.debug_damage_log = false
		add_child(health)
		health.setup(stats)
		health.died.connect(_on_died)

	func get_defense_stats() -> ShipDefenseStats:
		return health.get_defense_stats()

	func apply_damage(damage: float, penetration_result: int, hit_info: HitInfo) -> float:
		return health.apply_damage(damage, penetration_result, hit_info)

	func apply_damage_result(result: DamageResult) -> float:
		return health.apply_damage_result(result)

	func _on_died() -> void:
		sink_called = true


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var defense := ShipDefenseStats.new()
	defense.max_hp = 1000.0
	defense.current_hp = 1000.0
	defense.belt_armor = 100.0
	defense.damage_reduction = 0.0
	var target := DamageTarget.new()
	root.add_child(target)
	target.configure(defense)

	var ap := load("res://scripts/combat/default_ap_shell.tres").duplicate(true) as ShellStats
	var he := load("res://scripts/combat/default_he_shell.tres").duplicate(true) as ShellStats
	_test_case("AP penetration", target, ap, 200.0, Vector3.LEFT, PenetrationResolver.Result.PENETRATED, 60.0)
	_test_case("AP non-penetration", target, ap, 50.0, Vector3.LEFT, PenetrationResolver.Result.NON_PENETRATED, 2.0)
	_test_case("AP ricochet", target, ap, 500.0, Vector3(-0.05, 0.0, 1.0), PenetrationResolver.Result.RICOCHET, 0.0)
	_test_case("HE penetration", target, he, 200.0, Vector3.LEFT, PenetrationResolver.Result.PENETRATED, 80.0)
	_test_case("HE non-penetration", target, he, 35.0, Vector3.LEFT, PenetrationResolver.Result.NON_PENETRATED, 46.4)
	_test_case("HE ricochet", target, he, 500.0, Vector3(-0.05, 0.0, 1.0), PenetrationResolver.Result.RICOCHET, 26.0)
	_test_torpedo_outcome(target)

	target.get_defense_stats().damage_reduction = 0.25
	_test_case("Damage reduction", target, ap, 200.0, Vector3.LEFT, PenetrationResolver.Result.PENETRATED, 45.0)
	target.get_defense_stats().damage_reduction = 0.0
	target.get_defense_stats().current_hp = 10.0
	_resolve(target, ap, 200.0, Vector3.LEFT)
	_expect_true("Sink signal", target.sink_called)

	if _failures == 0:
		print("COMBAT_DAMAGE_TEST PASS")
		quit(0)
	else:
		push_error("COMBAT_DAMAGE_TEST FAILURES=%d" % _failures)
		quit(1)


func _test_case(
		label: String,
		target: DamageTarget,
		shell: ShellStats,
		penetration: float,
		direction: Vector3,
		expected_result: int,
		expected_damage: float
) -> void:
	target.get_defense_stats().current_hp = target.get_defense_stats().max_hp
	shell.penetration = penetration
	var result: DamageResult = _resolve(target, shell, penetration, direction)
	_expect_true("%s result" % label, result.penetration_result == expected_result)
	_expect_true(
		"%s outcome" % label,
		result.hit_outcome
			== HitOutcome.from_penetration_result(expected_result)
	)
	_expect_approx("%s damage" % label, result.applied_damage, expected_damage)


func _test_torpedo_outcome(target: DamageTarget) -> void:
	target.get_defense_stats().current_hp = target.get_defense_stats().max_hp
	var torpedo_data := TorpedoProjectileData.new()
	torpedo_data.direct_damage = 100.0
	torpedo_data.explosion_damage = 0.0
	torpedo_data.flooding_chance = 0.0
	var hit_info := HitInfo.new()
	hit_info.target_ship = target
	hit_info.damage_type = DamageType.Type.TORPEDO
	hit_info.torpedo_data = torpedo_data
	hit_info.armor_part = ArmorPart.Type.BELT
	var result := DamageResolver.resolve_hit(hit_info)
	_expect_true(
		"Torpedo damage type",
		result.damage_type == DamageType.Type.TORPEDO
	)
	_expect_true(
		"Torpedo hit outcome",
		result.hit_outcome == HitOutcome.Type.TORPEDO_HIT
	)
	_expect_true(
		"Torpedo is not AP penetration",
		result.penetration_result != PenetrationResolver.Result.PENETRATED
	)
	_expect_approx("Torpedo damage", result.applied_damage, 100.0)


func _resolve(
		target: DamageTarget,
		shell: ShellStats,
		_penetration: float,
		direction: Vector3
) -> DamageResult:
	var hit_info := HitInfo.new().setup(
		shell,
		target,
		Vector3.ZERO,
		Vector3.RIGHT,
		direction,
		ArmorPart.Type.BELT
	)
	return DamageResolver.resolve_hit(hit_info)


func _expect_true(label: String, condition: bool) -> void:
	if condition:
		return
	_failures += 1
	push_error("%s failed" % label)


func _expect_approx(label: String, actual: float, expected: float) -> void:
	if absf(actual - expected) <= EPSILON:
		return
	_failures += 1
	push_error("%s expected %.3f, got %.3f" % [label, expected, actual])

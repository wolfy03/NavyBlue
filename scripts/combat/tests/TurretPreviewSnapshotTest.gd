extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/tests/weapon_combat_test.tres"
)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = STAGE
	root.add_child(battle)
	await process_frame
	var ship := battle.player_ship
	var cannons := ship.combat.get_weapons_by_type(
		WeaponTypes.Type.CANNON
	)
	_check(not cannons.is_empty(), "fixture provides cannon mounts")
	if cannons.is_empty():
		await _finish(battle)
		return
	var builder := TurretPreviewSnapshotBuilder.new()
	var cannon := cannons[0] as CannonMount
	var snapshot := builder.build(cannon)
	_check(snapshot.visible, "valid cannon mount is preview-visible")
	_check(
		snapshot.origin.is_equal_approx(
			cannon.get_preview_muzzle_position()
		),
		"snapshot uses the actual preview muzzle position"
	)
	_check(
		snapshot.direction.is_equal_approx(
			cannon.get_projectile_launch_direction_world()
		),
		"snapshot uses the projectile launch direction"
	)
	_check(
		is_equal_approx(
			snapshot.maximum_range_m,
			cannon.get_runtime_maximum_range_m()
		),
		"snapshot uses the individual runtime range"
	)
	_verify_runtime_range(builder, cannons)
	_verify_blocked_states(builder, cannon, ship)
	_verify_transform_tracking(builder, cannon, ship)
	await _finish(battle)


func _verify_runtime_range(
		builder: TurretPreviewSnapshotBuilder,
		cannons: Array[WeaponMount]
) -> void:
	var targets := [10000.0, 12000.0, 15000.0]
	for index in mini(cannons.size(), targets.size()):
		var mount := cannons[index]
		var base_range := mount.weapon_data.range_meters
		mount.runtime_stats.range_multiplier = targets[index] / base_range
		var snapshot := builder.build(mount)
		_check(
			is_equal_approx(
				snapshot.maximum_range_m,
				targets[index]
			),
			"mount %d preserves its own runtime range" % index
		)


func _verify_blocked_states(
		builder: TurretPreviewSnapshotBuilder,
		cannon: CannonMount,
		ship: ShipUnit
) -> void:
	var original_ammunition := cannon.runtime_state.ammunition
	var original_reload := cannon.reload_left
	var original_enabled := cannon.runtime_state.enabled
	cannon.runtime_state.ammunition = 0
	var no_ammo := builder.build(cannon)
	_check(
		no_ammo.visible \
			and not no_ammo.can_fire_now \
			and no_ammo.blocked_reason == &"no_ammunition",
		"no-ammunition cannon remains visible and blocked"
	)
	cannon.runtime_state.ammunition = -1
	cannon.reload_left = 1.0
	var reloading := builder.build(cannon)
	_check(
		reloading.visible \
			and not reloading.can_fire_now \
			and reloading.blocked_reason == &"reloading",
		"reloading cannon remains visible and blocked"
	)
	cannon.reload_left = 0.0
	cannon.runtime_state.enabled = false
	var disabled := builder.build(cannon)
	_check(
		disabled.visible \
			and not disabled.can_fire_now \
			and disabled.blocked_reason == &"weapon_disabled",
		"disabled cannon remains visible and blocked"
	)
	cannon.runtime_state.enabled = true
	var target := ship.to_global(Vector3(0.0, 0.0, -1000.0))
	cannon.aim_at(target)
	cannon.rotation.y = cannon.base_local_yaw_radians \
		+ deg_to_rad(20.0)
	var unaligned := builder.build(cannon)
	_check(
		unaligned.visible \
			and not unaligned.can_fire_now \
			and unaligned.blocked_reason == &"not_aligned",
		"unaligned cannon reports the existing readiness reason"
	)
	cannon.rotation.y = cannon.base_local_yaw_radians
	cannon.call(&"_turn_toward", target, 10.0)
	var ready := builder.build(cannon)
	_check(
		ready.visible \
			and ready.can_fire_now \
			and ready.blocked_reason.is_empty(),
		"aligned cannon becomes green-ready through actual readiness"
	)
	cannon.runtime_state.ammunition = original_ammunition
	cannon.reload_left = original_reload
	cannon.runtime_state.enabled = original_enabled


func _verify_transform_tracking(
		builder: TurretPreviewSnapshotBuilder,
		cannon: CannonMount,
		ship: ShipUnit
) -> void:
	var before := builder.build(cannon)
	cannon.rotation.y += deg_to_rad(12.0)
	var rotated := builder.build(cannon)
	_check(
		before.direction.angle_to(rotated.direction) > deg_to_rad(10.0),
		"preview direction follows the rotating barrel"
	)
	var origin_before := rotated.origin
	ship.global_position += Vector3(250.0, 0.0, -175.0)
	var translated := builder.build(cannon)
	_check(
		translated.origin.distance_to(origin_before) > 200.0,
		"preview muzzle follows ship translation"
	)
	var direction_before_hull_rotation := translated.direction
	ship.rotate_y(deg_to_rad(30.0))
	var hull_rotated := builder.build(cannon)
	_check(
		direction_before_hull_rotation.angle_to(
			hull_rotated.direction
		) > deg_to_rad(25.0),
		"preview direction follows ship rotation"
	)


func _finish(battle: BattleScene) -> void:
	battle.shutdown()
	battle.queue_free()
	await process_frame
	await process_frame
	for failure in _failures:
		push_error("TURRET PREVIEW SNAPSHOT TEST: %s" % failure)
	print(
		"TURRET_PREVIEW_SNAPSHOT_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)

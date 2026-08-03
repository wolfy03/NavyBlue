extends RefCounted
class_name SecondaryBatteryController

const DEFAULT_PROFILE: SecondaryBatteryProfile = preload(
	"res://resources/settings/default_secondary_battery_profile.tres"
)
const PLAYER_AUTO_DIFFICULTY: AIGunneryDifficultyProfile = preload(
	"res://resources/ai_difficulty/gunnery_normal.tres"
)
const SECONDARY_ACCURACY: GunneryWeaponAccuracyProfile = preload(
	"res://resources/weapon_accuracy/secondary_gun_accuracy.tres"
)

var owner_ship: ShipUnit
var ship_combat: ShipCombat
var profile: SecondaryBatteryProfile
var secondary_mounts: Array[CannonMount] = []
var target_selector := SecondaryBatteryTargetSelector.new()
var fire_control := ShipGunneryFireControl.new()
var line_of_fire := WeaponLineOfFireEvaluator.new()

var current_target_ref: WeakRef
var current_target_instance_id := 0
var current_target_score := 0.0
var scan_elapsed_sec := 0.0
var target_switch_elapsed_sec := 0.0
var _candidate_provider := Callable()
var _debug_snapshot := SecondaryBatteryDebugSnapshot.new()
var _configured := false


func setup(
		next_owner_ship: ShipUnit,
		next_ship_combat: ShipCombat,
		next_mounts: Array[CannonMount],
		next_profile: SecondaryBatteryProfile,
		candidate_provider: Callable = Callable()
) -> bool:
	shutdown()
	if next_owner_ship == null or not is_instance_valid(next_owner_ship) \
			or next_ship_combat == null:
		return false
	owner_ship = next_owner_ship
	ship_combat = next_ship_combat
	profile = next_profile \
		if next_profile != null and next_profile.validate().is_empty() \
		else DEFAULT_PROFILE
	secondary_mounts.assign(next_mounts)
	_candidate_provider = candidate_provider
	var services := owner_ship.battle_services
	var difficulty := PLAYER_AUTO_DIFFICULTY \
		if owner_ship.player_controlled \
		else (services.ai_gunnery_difficulty if services != null else null)
	var crew := owner_ship.ship_data.secondary_gunnery_crew_stats \
		if owner_ship.ship_data != null else null
	if crew == null and owner_ship.ship_data != null:
		crew = owner_ship.ship_data.gunnery_crew_stats
	fire_control.configure(
		difficulty,
		crew,
		services.debug_settings if services != null else null,
		SECONDARY_ACCURACY
	)
	scan_elapsed_sec = maxf(profile.scan_interval_sec, 0.01)
	_configured = not secondary_mounts.is_empty()
	_refresh_debug_snapshot(0, 0)
	return _configured


func shutdown() -> void:
	_clear_target(&"shutdown")
	fire_control.clear()
	secondary_mounts.clear()
	_candidate_provider = Callable()
	owner_ship = null
	ship_combat = null
	profile = null
	_configured = false
	_refresh_debug_snapshot(0, 0)


func set_candidate_provider(provider: Callable) -> void:
	_candidate_provider = provider
	scan_elapsed_sec = maxf(profile.scan_interval_sec, 0.01) \
		if profile != null else 0.0


func update(delta: float) -> void:
	if not _configured or owner_ship == null \
			or not is_instance_valid(owner_ship) \
			or not owner_ship.is_alive():
		_clear_target(&"owner_unavailable")
		return
	_prune_invalid_mounts()
	if secondary_mounts.is_empty():
		_clear_target(&"all_mounts_lost")
		_configured = false
		return
	if profile == null or not profile.enabled:
		_clear_target(&"disabled")
		_update_idle_mounts(delta)
		return
	target_switch_elapsed_sec += maxf(delta, 0.0)
	scan_elapsed_sec += maxf(delta, 0.0)
	var current_target := get_current_target()
	if not _is_valid_target(current_target) \
			or count_engaging_mounts(current_target) \
				< maxi(profile.minimum_engaging_mount_count, 1):
		_clear_target(&"target_unavailable")
		current_target = null
		scan_elapsed_sec = maxf(profile.scan_interval_sec, 0.01)
	if scan_elapsed_sec >= maxf(profile.scan_interval_sec, 0.01):
		_scan_for_target()
		scan_elapsed_sec = 0.0
		current_target = get_current_target()
	if current_target == null:
		_update_idle_mounts(delta)
		_refresh_debug_snapshot(0, 0)
		return
	_update_fire_control(current_target)
	var engaging := count_engaging_mounts(current_target)
	var fired := 0
	if not profile.hold_fire:
		fire_control.begin_salvo_for_mounts(_as_weapon_mounts())
		for mount in secondary_mounts:
			if mount == null or not is_instance_valid(mount) \
					or not fire_control.has_solution_for_mount(mount):
				continue
			var aim := fire_control.get_aim_point_for_mount(
				mount,
				current_target.global_position
			)
			if mount.get_fire_readiness_at(aim) \
					!= WeaponFireReadiness.State.READY:
				continue
			var safety := line_of_fire.evaluate(mount, current_target, aim)
			if not safety.safe:
				_debug_snapshot.last_fire_control_failure = safety.blocked_reason
				continue
			if mount.fire():
				fired += 1
	_refresh_debug_snapshot(engaging, fired)


func count_engaging_mounts(target_ship: ShipUnit) -> int:
	if not _is_valid_target(target_ship):
		return 0
	var count := 0
	for mount in secondary_mounts:
		if mount != null and is_instance_valid(mount) \
				and mount.can_engage_world_point(target_ship.global_position):
			count += 1
	return count


func get_current_target() -> ShipUnit:
	if current_target_ref == null:
		return null
	var value: Variant = current_target_ref.get_ref()
	if value == null or not is_instance_valid(value):
		return null
	var target := value as ShipUnit
	return target if target != null \
		and target.get_instance_id() == current_target_instance_id else null


func get_debug_snapshot() -> SecondaryBatteryDebugSnapshot:
	return _debug_snapshot


func is_configured() -> bool:
	return _configured


func _scan_for_target() -> void:
	var candidates := _get_candidates()
	var main_target := ship_combat.get_main_target() \
		if ship_combat != null else null
	var result := target_selector.select_target(
		owner_ship,
		secondary_mounts,
		candidates,
		profile,
		main_target
	)
	_debug_snapshot.candidate_count = result.candidate_count
	var current_target := get_current_target()
	if result.target == null:
		if current_target == null:
			return
		_clear_target(&"no_candidate")
		return
	if current_target == null:
		_set_target(result.target, result.score, &"acquired")
		return
	var current_context := target_selector.evaluate_candidate(
		owner_ship,
		secondary_mounts,
		current_target,
		profile,
		main_target
	)
	current_target_score = current_context.total_score
	if result.target == current_target:
		return
	if target_switch_elapsed_sec < maxf(profile.target_switch_cooldown_sec, 0.0):
		return
	if result.score < current_target_score \
			* maxf(profile.target_switch_score_ratio, 1.0):
		return
	_set_target(result.target, result.score, &"better_candidate")


func _set_target(
		target_ship: ShipUnit,
		score: float,
		reason: StringName
) -> void:
	if not _is_valid_target(target_ship):
		return
	if get_current_target() == target_ship:
		current_target_score = score
		return
	_clear_target(&"target_changed")
	current_target_ref = weakref(target_ship)
	current_target_instance_id = target_ship.get_instance_id()
	current_target_score = score
	target_switch_elapsed_sec = 0.0
	_debug_snapshot.last_target_change_reason = reason
	fire_control.begin_tracking_target(target_ship)


func _clear_target(reason: StringName) -> void:
	var had_target := current_target_ref != null or current_target_instance_id != 0
	fire_control.release_provider_bindings()
	fire_control.clear_tracking_target(reason)
	current_target_ref = null
	current_target_instance_id = 0
	current_target_score = 0.0
	if had_target:
		_debug_snapshot.last_target_change_reason = reason
	for mount in secondary_mounts:
		if mount != null and is_instance_valid(mount) \
				and mount.shell_deviation_provider == fire_control:
			mount.shell_deviation_provider = null


func _update_fire_control(target_ship: ShipUnit) -> void:
	var weapon_mounts := _as_weapon_mounts()
	fire_control.update(owner_ship, target_ship, weapon_mounts)
	for mount in secondary_mounts:
		if mount == null or not is_instance_valid(mount):
			continue
		if not fire_control.has_solution_for_mount(mount):
			mount.clear_aim()
			continue
		var aim := fire_control.get_aim_point_for_mount(
			mount,
			target_ship.global_position
		)
		if not mount.can_engage_world_point(aim):
			mount.clear_aim()
			continue
		mount.aim_at(aim)
		fire_control.bind_mount_provider(mount)


func _update_idle_mounts(delta: float) -> void:
	if profile == null \
			or profile.idle_behavior == SecondaryBatteryProfile.IdleBehavior.HOLD_LAST_AIM:
		return
	for mount in secondary_mounts:
		if mount == null or not is_instance_valid(mount):
			continue
		mount.clear_aim()
		mount.return_to_rest(delta)


func _prune_invalid_mounts() -> void:
	for index in range(secondary_mounts.size() - 1, -1, -1):
		var value: Variant = secondary_mounts[index]
		if value == null or not is_instance_valid(value):
			secondary_mounts.remove_at(index)


func _get_candidates() -> Array:
	if not _candidate_provider.is_valid():
		return []
	var values: Variant = _candidate_provider.call()
	return values if values is Array else []


func _is_valid_target(target_ship: ShipUnit) -> bool:
	return target_ship != null \
		and is_instance_valid(target_ship) \
		and owner_ship != null \
		and is_instance_valid(owner_ship) \
		and target_ship.is_valid_attack_target_for(owner_ship.team)


func _as_weapon_mounts() -> Array[WeaponMount]:
	var result: Array[WeaponMount] = []
	for mount in secondary_mounts:
		if mount != null and is_instance_valid(mount):
			result.append(mount)
	return result


func _refresh_debug_snapshot(engaging: int, firing: int) -> void:
	_debug_snapshot.enabled = _configured and profile != null and profile.enabled
	_debug_snapshot.hold_fire = profile.hold_fire if profile != null else false
	_debug_snapshot.current_target_instance_id = current_target_instance_id
	_debug_snapshot.current_target_score = current_target_score
	_debug_snapshot.total_mount_count = secondary_mounts.size()
	_debug_snapshot.valid_mount_count = secondary_mounts.size()
	_debug_snapshot.engaging_mount_count = engaging
	_debug_snapshot.firing_mount_count = firing
	_debug_snapshot.maximum_range_m = get_max_secondary_range_m()
	_debug_snapshot.scan_elapsed_sec = scan_elapsed_sec
	_debug_snapshot.target_switch_elapsed_sec = target_switch_elapsed_sec
	var snapshots := fire_control.get_debug_snapshots()
	if not snapshots.is_empty():
		_debug_snapshot.predicted_impact_position = snapshots[0].ideal_aim_point
		_debug_snapshot.actual_aim_position = snapshots[0].actual_aim_point
		_debug_snapshot.last_fire_control_failure = snapshots[0].failure_reason


func get_max_secondary_range_m() -> float:
	var result := 0.0
	for mount in secondary_mounts:
		if mount != null and is_instance_valid(mount):
			result = maxf(result, mount.get_range_m())
	return result


extends RefCounted
class_name SecondaryBatteryTargetSelector


func select_target(
		owner_ship: ShipUnit,
		mounts: Array[CannonMount],
		candidate_values: Array,
		profile: SecondaryBatteryProfile,
		main_target: ShipUnit = null
) -> SecondaryBatteryTargetResult:
	var result := SecondaryBatteryTargetResult.new()
	if owner_ship == null or not is_instance_valid(owner_ship) \
			or profile == null:
		return result
	var candidate_limit := maxi(profile.maximum_candidates_per_scan, 1)
	for candidate_value: Variant in candidate_values:
		if result.candidate_count >= candidate_limit:
			break
		if candidate_value == null or not is_instance_valid(candidate_value):
			continue
		var candidate := candidate_value as ShipUnit
		if not _is_valid_candidate(owner_ship, candidate):
			continue
		result.candidate_count += 1
		var context := evaluate_candidate(
			owner_ship,
			mounts,
			candidate,
			profile,
			main_target
		)
		result.contexts.append(context)
		if context.engaging_mount_count \
				< maxi(profile.minimum_engaging_mount_count, 1):
			continue
		if result.target == null or context.total_score > result.score:
			result.target = candidate
			result.score = context.total_score
			result.engaging_mount_count = context.engaging_mount_count
	return result


func evaluate_candidate(
		owner_ship: ShipUnit,
		mounts: Array[CannonMount],
		candidate: ShipUnit,
		profile: SecondaryBatteryProfile,
		main_target: ShipUnit = null
) -> SecondaryBatteryTargetContext:
	var context := SecondaryBatteryTargetContext.new()
	context.target = candidate
	context.maximum_mount_count = mounts.size()
	if not _is_valid_candidate(owner_ship, candidate):
		return context
	context.distance_m = CombatGeometryXZ.distance_xz(
		owner_ship.global_position,
		candidate.global_position
	)
	var maximum_range_m := 0.0
	for mount in mounts:
		if mount == null or not is_instance_valid(mount):
			continue
		maximum_range_m = maxf(maximum_range_m, mount.get_range_m())
		if mount.can_engage_world_point(candidate.global_position):
			context.engaging_mount_count += 1
	context.distance_score = clampf(
		1.0 - context.distance_m / maxf(maximum_range_m, 1.0),
		0.0,
		1.0
	)
	context.mount_availability_score = float(context.engaging_mount_count) \
		/ float(maxi(context.maximum_mount_count, 1))
	context.threat_score = clampf(
		candidate.combat.get_total_sustained_dps() / 200.0 \
			if candidate.combat != null else 0.0,
		0.0,
		1.0
	)
	context.target_size_score = clampf(
		candidate.get_navigation_safety_radius_m() / 250.0,
		0.0,
		1.0
	)
	context.is_main_target = main_target != null \
		and is_instance_valid(main_target) \
		and candidate == main_target
	context.total_score = (
		context.distance_score * maxf(profile.distance_score_weight, 0.0)
		+ context.mount_availability_score
			* maxf(profile.available_mount_score_weight, 0.0)
		+ context.threat_score * maxf(profile.threat_score_weight, 0.0)
		+ context.target_size_score * maxf(profile.target_size_score_weight, 0.0)
	)
	if profile.prefer_main_target and context.is_main_target:
		context.total_score *= 1.0 + maxf(profile.main_target_score_bonus, 0.0)
	return context


func _is_valid_candidate(
		owner_ship: ShipUnit,
		candidate: ShipUnit
) -> bool:
	return candidate != null \
		and is_instance_valid(candidate) \
		and candidate != owner_ship \
		and candidate.is_valid_attack_target_for(owner_ship.team)


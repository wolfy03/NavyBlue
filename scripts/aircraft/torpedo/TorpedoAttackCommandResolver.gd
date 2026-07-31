extends RefCounted
class_name TorpedoAttackCommandResolver

const EPSILON := 0.0001
static var _next_command_id := 1


func resolve(
		squadron: AircraftSquadron,
		entry_point: Vector3,
		requested_release_point: Vector3,
		attack_profile: TorpedoAttackProfile,
		battle_environment: BattleEnvironment,
		target_ship: ShipUnit = null
) -> TorpedoAttackResolveResult:
	if squadron == null or not is_instance_valid(squadron):
		return TorpedoAttackResolveResult.failed(&"invalid_squadron")
	if attack_profile == null or not attack_profile.validate().is_empty():
		return TorpedoAttackResolveResult.failed(&"invalid_profile")
	var plane_height := battle_environment.sea_level_m \
		if battle_environment != null else entry_point.y
	var entry := entry_point
	var requested := requested_release_point
	entry.y = plane_height
	requested.y = plane_height
	var flat_delta := requested - entry
	flat_delta.y = 0.0
	var requested_distance := flat_delta.length()
	var direction := Vector3.ZERO
	if requested_distance >= attack_profile.minimum_direction_drag_m:
		direction = flat_delta / requested_distance
	else:
		direction = squadron.get_formation_forward()
		direction.y = 0.0
	if direction.length_squared() <= EPSILON:
		return TorpedoAttackResolveResult.failed(&"direction_unavailable")
	direction = direction.normalized()
	var actual_distance := maxf(
		requested_distance,
		attack_profile.minimum_attack_run_distance_m
	)
	var command := TorpedoAttackCommand.new()
	command.command_id = _allocate_command_id()
	command.entry_point = entry
	command.requested_release_point = requested
	command.actual_release_point = entry + direction * actual_distance
	command.approach_point = entry \
		- direction * attack_profile.approach_distance_m
	command.escape_point = command.actual_release_point \
		+ direction * attack_profile.escape_distance_m
	command.attack_direction = direction
	command.requested_run_distance_m = requested_distance
	command.actual_run_distance_m = actual_distance
	command.minimum_run_distance_m = \
		attack_profile.minimum_attack_run_distance_m
	command.command_plane_height_m = plane_height
	command.target_ship = target_ship \
		if target_ship != null and is_instance_valid(target_ship) else null
	if not _fit_command_to_battle_area(
		command,
		battle_environment
	):
		return TorpedoAttackResolveResult.failed(&"insufficient_attack_space")
	command.actual_run_distance_m = _distance_xz(
		command.entry_point,
		command.actual_release_point
	)
	if command.actual_run_distance_m + 0.01 \
			< command.minimum_run_distance_m:
		return TorpedoAttackResolveResult.failed(&"insufficient_attack_space")
	return TorpedoAttackResolveResult.completed(command)


func build_preview(
		squadron: AircraftSquadron,
		entry_point: Vector3,
		cursor_point: Vector3,
		attack_profile: TorpedoAttackProfile,
		battle_environment: BattleEnvironment,
		tail_locked: bool
) -> TorpedoAttackPreview:
	var preview := TorpedoAttackPreview.new()
	preview.entry_point = entry_point
	preview.cursor_point = cursor_point
	preview.tail_locked = tail_locked
	preview.minimum_distance_m = attack_profile.minimum_attack_run_distance_m \
		if attack_profile != null else 0.0
	var requested := cursor_point - entry_point
	requested.y = 0.0
	preview.requested_distance_m = requested.length()
	preview.distance_satisfied = preview.requested_distance_m + 0.01 \
		>= preview.minimum_distance_m
	var result := resolve(
		squadron,
		entry_point,
		cursor_point,
		attack_profile,
		battle_environment
	)
	preview.valid = result.success
	preview.invalid_reason = result.failure_reason
	if result.command != null:
		preview.actual_release_point = result.command.actual_release_point
		preview.attack_direction = result.command.attack_direction
		preview.displayed_distance_m = result.command.actual_run_distance_m
	return preview


func apply_lateral_offset(
		command: TorpedoAttackCommand,
		centered_index: float,
		attack_profile: TorpedoAttackProfile,
		battle_environment: BattleEnvironment
) -> TorpedoAttackResolveResult:
	if command == null or attack_profile == null:
		return TorpedoAttackResolveResult.failed(&"invalid_command")
	var lateral := command.attack_direction.cross(Vector3.UP)
	if lateral.length_squared() <= EPSILON:
		return TorpedoAttackResolveResult.failed(&"direction_unavailable")
	var offset := lateral.normalized() * centered_index \
		* attack_profile.multi_squadron_attack_spacing_m
	var shifted := command.translated(offset)
	shifted.command_id = _allocate_command_id()
	if not _fit_command_to_battle_area(shifted, battle_environment):
		return TorpedoAttackResolveResult.failed(&"insufficient_attack_space")
	return TorpedoAttackResolveResult.completed(shifted)


func _fit_command_to_battle_area(
		command: TorpedoAttackCommand,
		battle_environment: BattleEnvironment
) -> bool:
	if battle_environment == null \
			or battle_environment.battlefield_bounds == null \
			or battle_environment.battlefield_bounds.settings == null:
		return true
	var half_extents := battle_environment.battlefield_bounds.settings \
		.get_half_extents_m()
	var margin := battle_environment.rules.aircraft_command_margin_m \
		if battle_environment.rules != null else 100.0
	var minimum := Vector2(
		-half_extents.x + margin,
		-half_extents.y + margin
	)
	var maximum := Vector2(
		half_extents.x - margin,
		half_extents.y - margin
	)
	var points: Array[Vector3] = [
		command.approach_point,
		command.entry_point,
		command.actual_release_point,
		command.escape_point,
	]
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for point in points:
		min_point.x = minf(min_point.x, point.x)
		min_point.y = minf(min_point.y, point.z)
		max_point.x = maxf(max_point.x, point.x)
		max_point.y = maxf(max_point.y, point.z)
	if max_point.x - min_point.x > maximum.x - minimum.x + 0.01 \
			or max_point.y - min_point.y > maximum.y - minimum.y + 0.01:
		return false
	var translation := Vector2.ZERO
	if min_point.x < minimum.x:
		translation.x += minimum.x - min_point.x
	if max_point.x + translation.x > maximum.x:
		translation.x += maximum.x - (max_point.x + translation.x)
	if min_point.y < minimum.y:
		translation.y += minimum.y - min_point.y
	if max_point.y + translation.y > maximum.y:
		translation.y += maximum.y - (max_point.y + translation.y)
	var world_translation := Vector3(translation.x, 0.0, translation.y)
	command.entry_point += world_translation
	command.requested_release_point += world_translation
	command.actual_release_point += world_translation
	command.approach_point += world_translation
	command.escape_point += world_translation
	for point in [
		command.approach_point,
		command.entry_point,
		command.actual_release_point,
		command.escape_point,
	]:
		if not battle_environment.battlefield_bounds.is_inside_bounds(point):
			return false
	return true


func _distance_xz(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x - second.x, first.z - second.z).length()


func _allocate_command_id() -> int:
	var command_id := _next_command_id
	_next_command_id += 1
	if _next_command_id <= 0:
		_next_command_id = 1
	return command_id

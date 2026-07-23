extends Node
class_name ShipNavigationController

signal path_changed(path: PackedVector3Array)
signal navigation_target_changed(target: Vector3)
signal navigation_finished(target: Vector3)
signal path_calculation_failed(target: Vector3)

const DEFAULT_SETTINGS := preload("res://resources/settings/default_battlefield_settings.tres")

@export var settings: BattlefieldSettings = DEFAULT_SETTINGS
@export var waypoint_reach_radius_m := 100.0
@export var destination_reach_radius_m := 140.0
@export var path_recalculation_interval_sec := 1.0
@export var path_deviation_threshold_m := 320.0
@export var target_change_threshold_m := 100.0
@export var deviation_recalculation_cooldown_sec := 0.5
@export var failed_path_retry_interval_sec := 1.5

var target_position := Vector3.ZERO
var current_path := PackedVector3Array()
var current_waypoint_index := 0
var has_navigation_target := false
var path_recalculation_elapsed_sec := 0.0
var path_calculation_failed_state := false
var path_calculation_count := 0

var owner_ship: CharacterBody3D
var battlefield_bounds: BattlefieldBounds
var _recalculation_requested := false
var _last_path_origin := Vector3.ZERO
var _schedule_offset_sec := 0.0

func setup(ship: CharacterBody3D, battlefield_settings: BattlefieldSettings, bounds: BattlefieldBounds) -> void:
	owner_ship = ship
	settings = battlefield_settings if battlefield_settings != null else DEFAULT_SETTINGS
	battlefield_bounds = bounds
	waypoint_reach_radius_m = settings.waypoint_reach_radius_m
	destination_reach_radius_m = settings.destination_reach_radius_m
	path_recalculation_interval_sec = settings.path_recalculation_interval_sec
	path_deviation_threshold_m = settings.path_deviation_threshold_m
	# Instance IDs distribute periodic work without delaying the initial command.
	var offset_window := minf(path_recalculation_interval_sec * 0.4, 0.4)
	_schedule_offset_sec = fmod(float(ship.get_instance_id() % 997) * 0.037, maxf(offset_window, 0.01))
	path_recalculation_elapsed_sec = -_schedule_offset_sec

func update_navigation(delta: float) -> void:
	if owner_ship == null:
		return
	_resolve_bounds()
	_request_return_when_outside()
	if not has_navigation_target:
		return

	advance_waypoint_if_reached()
	if not has_navigation_target:
		return

	path_recalculation_elapsed_sec += delta
	if _recalculation_requested:
		_calculate_path()
	elif path_calculation_failed_state \
			and path_recalculation_elapsed_sec >= failed_path_retry_interval_sec:
		_calculate_path()
	elif _has_deviated_from_path() \
			and path_recalculation_elapsed_sec >= deviation_recalculation_cooldown_sec:
		_calculate_path()


func constrain_owner_to_bounds() -> bool:
	if owner_ship == null:
		return false
	_resolve_bounds()
	if battlefield_bounds == null \
			or battlefield_bounds.is_inside_bounds(owner_ship.global_position):
		return false
	var constrained := battlefield_bounds.clamp_to_bounds(
		owner_ship.global_position
	)
	constrained.y = _get_sea_level_m()
	owner_ship.global_position = constrained
	return true

func set_navigation_target(target: Vector3) -> void:
	if owner_ship == null:
		return
	_resolve_bounds()
	var normalized_target := target
	normalized_target.y = _get_sea_level_m()
	if battlefield_bounds != null:
		normalized_target = battlefield_bounds.clamp_to_bounds(normalized_target, _get_navigation_margin_m())

	var is_meaningful_change := not has_navigation_target \
		or target_position.distance_squared_to(normalized_target) >= target_change_threshold_m * target_change_threshold_m
	target_position = normalized_target
	has_navigation_target = true
	navigation_target_changed.emit(target_position)
	if is_meaningful_change or not has_valid_path():
		_calculate_path()

func clear_navigation_target() -> void:
	has_navigation_target = false
	current_path = PackedVector3Array()
	current_waypoint_index = 0
	path_calculation_failed_state = false
	_recalculation_requested = false
	path_changed.emit(current_path)

func request_path_recalculation() -> void:
	if has_navigation_target:
		_recalculation_requested = true

func get_current_waypoint() -> Vector3:
	if not has_valid_path():
		return target_position if has_navigation_target else Vector3.ZERO
	return current_path[current_waypoint_index]

func advance_waypoint_if_reached() -> void:
	if not has_valid_path() or owner_ship == null:
		return

	while current_waypoint_index < current_path.size():
		var waypoint := current_path[current_waypoint_index]
		var flat_offset := waypoint - owner_ship.global_position
		flat_offset.y = 0.0
		var reached := flat_offset.length_squared() <= waypoint_reach_radius_m * waypoint_reach_radius_m
		if not reached and current_waypoint_index > 0:
			var previous := current_path[current_waypoint_index - 1]
			var segment := waypoint - previous
			segment.y = 0.0
			if segment.length_squared() > 0.001:
				reached = (owner_ship.global_position - waypoint).dot(segment.normalized()) >= 0.0
		if not reached:
			break
		current_waypoint_index += 1

	if has_reached_destination() or current_waypoint_index >= current_path.size():
		var completed_target := target_position
		clear_navigation_target()
		navigation_finished.emit(completed_target)

func has_valid_path() -> bool:
	return has_navigation_target and current_path.size() > 0 and current_waypoint_index < current_path.size()

func has_reached_destination() -> bool:
	if not has_navigation_target or owner_ship == null:
		return false
	var offset := target_position - owner_ship.global_position
	offset.y = 0.0
	return offset.length_squared() <= destination_reach_radius_m * destination_reach_radius_m

func get_remaining_distance_m() -> float:
	if owner_ship == null or not has_navigation_target:
		return 0.0
	if not has_valid_path():
		return _flat_distance(owner_ship.global_position, target_position)
	var distance := _flat_distance(owner_ship.global_position, current_path[current_waypoint_index])
	for index in range(current_waypoint_index, current_path.size() - 1):
		distance += _flat_distance(current_path[index], current_path[index + 1])
	return distance


func is_path_deviated(threshold_m: float = -1.0) -> bool:
	var active_threshold_m := path_deviation_threshold_m if threshold_m < 0.0 else threshold_m
	return _has_deviated_from_path(active_threshold_m)


func _calculate_path() -> void:
	if owner_ship == null or not has_navigation_target:
		return
	path_calculation_count += 1
	path_recalculation_elapsed_sec = -_schedule_offset_sec
	_recalculation_requested = false
	var origin := owner_ship.global_position
	origin.y = _get_sea_level_m()
	var candidate := PackedVector3Array()
	var navigation_map := owner_ship.get_world_3d().navigation_map
	var has_baked_navigation := navigation_map.is_valid() \
		and NavigationServer3D.map_get_iteration_id(navigation_map) > 0
	if has_baked_navigation:
		candidate = NavigationServer3D.map_get_path(navigation_map, origin, target_position, true)
	else:
		# Open ocean needs no 20 km high-density NavigationMesh.
		candidate.append(origin)
		candidate.append(target_position)

	var simplified := _simplify_path(candidate, origin)
	if simplified.is_empty():
		path_calculation_failed_state = true
		path_calculation_failed.emit(target_position)
		# Preserve a previously usable path when a rebake or obstacle update temporarily fails.
		return

	current_path = simplified
	current_waypoint_index = 0
	_last_path_origin = origin
	path_calculation_failed_state = false
	path_changed.emit(current_path)

func _simplify_path(source: PackedVector3Array, origin: Vector3) -> PackedVector3Array:
	var filtered := PackedVector3Array()
	var minimum_segment := maxf(settings.minimum_path_segment_m, 1.0)
	for point in source:
		var normalized := point
		normalized.y = _get_sea_level_m()
		if battlefield_bounds != null:
			normalized = battlefield_bounds.clamp_to_bounds(normalized, _get_navigation_margin_m())
		if _flat_distance(origin, normalized) < minimum_segment and filtered.is_empty():
			continue
		if not filtered.is_empty() and _flat_distance(filtered[-1], normalized) < minimum_segment:
			continue
		filtered.append(normalized)

	if filtered.is_empty() or _flat_distance(filtered[-1], target_position) >= minimum_segment:
		filtered.append(target_position)
	if filtered.size() < 3:
		return filtered

	var result := PackedVector3Array([filtered[0]])
	var tolerance := deg_to_rad(settings.path_collinear_tolerance_deg)
	for index in range(1, filtered.size() - 1):
		var direction_a := filtered[index] - result[-1]
		var direction_b := filtered[index + 1] - filtered[index]
		direction_a.y = 0.0
		direction_b.y = 0.0
		if direction_a.length_squared() <= 0.001 or direction_b.length_squared() <= 0.001:
			continue
		if direction_a.normalized().angle_to(direction_b.normalized()) > tolerance:
			result.append(filtered[index])
	result.append(filtered[-1])
	return result

func _has_deviated_from_path(threshold_m: float = -1.0) -> bool:
	if not has_valid_path() or owner_ship == null:
		return false
	var segment_start := _last_path_origin if current_waypoint_index == 0 else current_path[current_waypoint_index - 1]
	var segment_end := current_path[current_waypoint_index]
	var active_threshold_m := path_deviation_threshold_m if threshold_m < 0.0 else threshold_m
	return _distance_to_segment_xz(owner_ship.global_position, segment_start, segment_end) > active_threshold_m

func _request_return_when_outside() -> void:
	if battlefield_bounds == null or battlefield_bounds.is_inside_bounds(owner_ship.global_position):
		return
	var return_target := battlefield_bounds.clamp_to_bounds(owner_ship.global_position, _get_navigation_margin_m())
	return_target.y = _get_sea_level_m()
	if not has_navigation_target or _flat_distance(target_position, return_target) > target_change_threshold_m:
		set_navigation_target(return_target)

func _get_navigation_margin_m() -> float:
	var ship_margin := 0.0
	if owner_ship != null:
		var data: Variant = owner_ship.get(&"ship_data")
		if data != null:
			ship_margin = float(data.get(&"navigation_safety_radius_m"))
	return maxf(settings.boundary_margin_m, ship_margin)

func _resolve_bounds() -> void:
	if battlefield_bounds == null and get_tree() != null:
		battlefield_bounds = get_tree().get_first_node_in_group(&"battlefield_bounds") as BattlefieldBounds

func _get_sea_level_m() -> float:
	return settings.sea_level_m if settings != null else 0.0

func _flat_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()

func _distance_to_segment_xz(point: Vector3, segment_start: Vector3, segment_end: Vector3) -> float:
	var point_2d := Vector2(point.x, point.z)
	var start_2d := Vector2(segment_start.x, segment_start.z)
	var end_2d := Vector2(segment_end.x, segment_end.z)
	var segment := end_2d - start_2d
	if segment.length_squared() <= 0.001:
		return point_2d.distance_to(start_2d)
	var ratio := clampf((point_2d - start_2d).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point_2d.distance_to(start_2d + segment * ratio)

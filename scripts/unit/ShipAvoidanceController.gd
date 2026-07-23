extends Node
class_name ShipAvoidanceController

const DEFAULT_SETTINGS := preload("res://resources/settings/default_battlefield_settings.tres")

@export var settings: BattlefieldSettings = DEFAULT_SETTINGS
@export var update_interval_sec := 0.35
@export var prediction_time_sec := 15.0
@export var direction_hold_sec := 2.0
@export_range(0.0, 1.0, 0.05) var maximum_steering_offset := 0.65
@export_range(0.0, 1.0, 0.05) var minimum_speed_scale := 0.15
@export var max_query_results := 24

var owner_ship: CharacterBody3D
var avoidance_radius_m := 500.0
var steering_offset := 0.0
var speed_scale := 1.0
var collision_risk_ship: Node3D
var predicted_closest_distance_m := INF
var predicted_closest_time_sec := INF

var _elapsed_sec := 0.0
var _held_side := 0.0
var _hold_remaining_sec := 0.0
var _query_shape := SphereShape3D.new()

func setup(ship: CharacterBody3D, battlefield_settings: BattlefieldSettings) -> void:
	owner_ship = ship
	settings = battlefield_settings if battlefield_settings != null else DEFAULT_SETTINGS
	update_interval_sec = settings.local_avoidance_update_interval_sec
	prediction_time_sec = settings.local_avoidance_prediction_sec
	direction_hold_sec = settings.local_avoidance_hold_sec
	avoidance_radius_m = _get_class_avoidance_radius_m()
	_query_shape.radius = avoidance_radius_m
	_elapsed_sec = fmod(float(ship.get_instance_id() % 541) * 0.029, maxf(update_interval_sec, 0.05))

func update_avoidance(delta: float) -> void:
	if owner_ship == null:
		return
	_elapsed_sec += delta
	_hold_remaining_sec = maxf(_hold_remaining_sec - delta, 0.0)
	if _elapsed_sec < maxf(update_interval_sec, 0.05):
		return
	_elapsed_sec = 0.0
	_evaluate_nearby_ships()

func has_collision_risk() -> bool:
	return is_instance_valid(collision_risk_ship)

func _evaluate_nearby_ships() -> void:
	collision_risk_ship = null
	predicted_closest_distance_m = INF
	predicted_closest_time_sec = INF
	var world := owner_ship.get_world_3d()
	if world == null:
		_clear_avoidance()
		return

	_query_shape.radius = avoidance_radius_m
	var parameters := PhysicsShapeQueryParameters3D.new()
	parameters.shape = _query_shape
	parameters.transform = Transform3D(Basis.IDENTITY, owner_ship.global_position)
	parameters.exclude = [owner_ship.get_rid()]
	parameters.collide_with_bodies = true
	parameters.collide_with_areas = false
	var hits := world.direct_space_state.intersect_shape(parameters, max_query_results)
	var best_risk_score := 0.0
	var best_relative_position := Vector3.ZERO
	var best_safety_distance := 1.0
	for hit: Dictionary in hits:
		var candidate := hit.get("collider") as Node3D
		if candidate == null or candidate == owner_ship or not candidate.is_in_group(&"ships"):
			continue
		var relative_position := candidate.global_position - owner_ship.global_position
		relative_position.y = 0.0
		var relative_velocity := _get_velocity_xz(candidate) - _get_velocity_xz(owner_ship)
		var closest_time := 0.0
		if relative_velocity.length_squared() > 0.01:
			closest_time = clampf(-relative_position.dot(relative_velocity) / relative_velocity.length_squared(), 0.0, prediction_time_sec)
		var closest_offset := relative_position + relative_velocity * closest_time
		var closest_distance := closest_offset.length()
		var safety_distance := _get_safety_radius_m(owner_ship) + _get_safety_radius_m(candidate)
		if closest_distance >= safety_distance * 1.35:
			continue
		var distance_risk := 1.0 - clampf(closest_distance / maxf(safety_distance * 1.35, 1.0), 0.0, 1.0)
		var time_risk := 1.0 - clampf(closest_time / maxf(prediction_time_sec, 0.1), 0.0, 1.0)
		var risk_score := distance_risk * 0.7 + time_risk * 0.3
		if risk_score > best_risk_score:
			best_risk_score = risk_score
			collision_risk_ship = candidate
			predicted_closest_distance_m = closest_distance
			predicted_closest_time_sec = closest_time
			best_relative_position = relative_position
			best_safety_distance = safety_distance

	if collision_risk_ship == null:
		_clear_avoidance()
		return
	_apply_avoidance(best_risk_score, best_relative_position, best_safety_distance)

func _apply_avoidance(risk: float, relative_position: Vector3, safety_distance_m: float) -> void:
	if _hold_remaining_sec <= 0.0 or is_zero_approx(_held_side):
		var forward := -owner_ship.global_transform.basis.z
		forward.y = 0.0
		var side_value := forward.normalized().cross(relative_position.normalized()).y
		# Prefer a stable turn away; exact head-on cases use instance IDs as a deterministic tie-break.
		if absf(side_value) < 0.08:
			_held_side = -1.0 if owner_ship.get_instance_id() < collision_risk_ship.get_instance_id() else 1.0
		else:
			_held_side = -signf(side_value)
		_hold_remaining_sec = direction_hold_sec
	steering_offset = _held_side * maximum_steering_offset * clampf(risk, 0.2, 1.0)
	var proximity := 1.0 - clampf(predicted_closest_distance_m / maxf(safety_distance_m, 1.0), 0.0, 1.0)
	speed_scale = lerpf(1.0, minimum_speed_scale, clampf(risk * 0.65 + proximity * 0.35, 0.0, 1.0))
	var forward_dot := (-owner_ship.global_transform.basis.z).normalized().dot(relative_position.normalized())
	if forward_dot > 0.7 and predicted_closest_distance_m < safety_distance_m * 0.5:
		speed_scale = minimum_speed_scale

func _clear_avoidance() -> void:
	steering_offset = 0.0
	speed_scale = 1.0
	if _hold_remaining_sec <= 0.0:
		_held_side = 0.0

func _get_velocity_xz(ship: Node3D) -> Vector3:
	var value: Variant = ship.get(&"velocity")
	if value is Vector3:
		return Vector3(value.x, 0.0, value.z)
	return Vector3.ZERO

func _get_safety_radius_m(ship: Node3D) -> float:
	var data: Variant = ship.get(&"ship_data")
	if data != null:
		return maxf(float(data.get(&"navigation_safety_radius_m")), 25.0)
	return 90.0

func _get_class_avoidance_radius_m() -> float:
	var data: Variant = owner_ship.get(&"ship_data")
	if data == null:
		return settings.local_avoidance_radius_m
	match int(data.get(&"ship_class")):
		ShipData.ShipClass.DESTROYER:
			return 400.0
		ShipData.ShipClass.CRUISER:
			return 550.0
		ShipData.ShipClass.BATTLESHIP:
			return 700.0
		ShipData.ShipClass.AIRCRAFT_CARRIER:
			return 750.0
	return settings.local_avoidance_radius_m

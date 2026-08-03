extends RefCounted
class_name TacticalPositionSolver

var battlefield_bounds: BattlefieldBounds
var boundary_margin_m := 250.0


func setup(bounds: BattlefieldBounds, margin_m := 250.0) -> TacticalPositionSolver:
	battlefield_bounds = bounds
	boundary_margin_m = margin_m
	return self


func calculate_line_combat_position(
		owner_ship: ShipUnit,
		target_ship: ShipUnit,
		preferred_distance_m: float,
		side_sign: float,
		lateral_offset_m: float,
		allow_side_switch: bool = true
) -> TacticalPositionResult:
	var primary := _calculate_line_side(
		owner_ship,
		target_ship,
		preferred_distance_m,
		side_sign,
		lateral_offset_m
	)
	if not primary.was_clamped or not allow_side_switch:
		return primary
	var opposite := _calculate_line_side(
		owner_ship,
		target_ship,
		preferred_distance_m,
		-side_sign,
		lateral_offset_m
	)
	if opposite.clamp_distance_m + 1.0 < primary.clamp_distance_m:
		opposite.requires_side_switch = true
		opposite.reason = &"line_opposite_side"
		return opposite
	if primary.clamp_distance_m > 500.0 and opposite.clamp_distance_m > 500.0:
		return _calculate_safe_fallback(owner_ship, primary.heading, side_sign, &"line_boundary_fallback")
	return primary


func calculate_escort_position(
		_escort_ship: ShipUnit,
		protected_ship: ShipUnit,
		threat_position: Vector3,
		slot_index: int
) -> TacticalPositionResult:
	var threat_direction := _flat_direction(protected_ship.global_position, threat_position)
	if threat_direction.length_squared() < 0.01:
		threat_direction = -protected_ship.global_transform.basis.z
	threat_direction = threat_direction.normalized()
	var lateral := Vector3(-threat_direction.z, 0.0, threat_direction.x)
	var side := -1.0 if slot_index % 2 == 0 else 1.0
	@warning_ignore("integer_division")
	var distance_m := 900.0 + float(slot_index / 2) * 250.0
	return _make_result(
		protected_ship.global_position + lateral * side * distance_m,
		threat_direction,
		side,
		&"escort"
	)


func calculate_screen_position(
		_screen_ship: ShipUnit,
		protected_ship: ShipUnit,
		threat_direction: Vector3,
		slot_index: int
) -> TacticalPositionResult:
	threat_direction.y = 0.0
	if threat_direction.length_squared() < 0.01:
		threat_direction = -protected_ship.global_transform.basis.z
	threat_direction = threat_direction.normalized()
	var lateral := Vector3(-threat_direction.z, 0.0, threat_direction.x)
	var slot_offset := (float(slot_index) - 0.5) * 500.0
	return _make_result(
		protected_ship.global_position + threat_direction * 1500.0 + lateral * slot_offset,
		threat_direction,
		-1.0 if slot_offset < 0.0 else 1.0,
		&"screen"
	)


func calculate_intercept_position(
		interceptor: ShipUnit,
		protected_ship: ShipUnit,
		threat_ship: ShipUnit,
		intercept_distance_m: float,
		prediction_sec: float = 2.0
) -> TacticalPositionResult:
	if interceptor == null or protected_ship == null or threat_ship == null:
		return TacticalPositionResult.new().setup(
			Vector3.ZERO, Vector3.FORWARD, false, false, 1.0, &"invalid_intercept"
		)
	var predicted_threat_position := threat_ship.global_position + threat_ship.velocity * maxf(prediction_sec, 0.0)
	var toward_protected := _flat_direction(predicted_threat_position, protected_ship.global_position)
	if toward_protected.length_squared() < 0.01:
		toward_protected = _flat_direction(threat_ship.global_position, protected_ship.global_position)
	if toward_protected.length_squared() < 0.01:
		toward_protected = Vector3.BACK
	toward_protected = toward_protected.normalized()
	var desired := predicted_threat_position + toward_protected * maxf(intercept_distance_m, 1.0)
	var heading := _flat_direction(interceptor.global_position, desired)
	return _make_result(desired, heading, 1.0, &"intercept")


func calculate_flank_position(
		owner_ship: ShipUnit,
		target_ship: ShipUnit,
		side_sign: float,
		allow_side_switch: bool = true
) -> TacticalPositionResult:
	var primary := _calculate_flank_side(owner_ship, target_ship, side_sign)
	if not primary.was_clamped or not allow_side_switch:
		return primary
	var opposite := _calculate_flank_side(owner_ship, target_ship, -side_sign)
	if opposite.clamp_distance_m + 1.0 < primary.clamp_distance_m:
		opposite.requires_side_switch = true
		opposite.reason = &"flank_opposite_side"
		return opposite
	if primary.clamp_distance_m > 500.0 and opposite.clamp_distance_m > 500.0:
		return _calculate_safe_fallback(owner_ship, primary.heading, side_sign, &"flank_boundary_fallback")
	return primary


func calculate_support_position(
		support_ship: ShipUnit,
		fleet_center: Vector3,
		safe_rear_direction: Vector3,
		slot_index: int
) -> TacticalPositionResult:
	var rear := safe_rear_direction
	rear.y = 0.0
	if rear.length_squared() < 0.01:
		rear = Vector3.BACK
	rear = rear.normalized()
	var lateral := Vector3(-rear.z, 0.0, rear.x)
	var offset := (float(slot_index) - 0.5) * 650.0
	var desired := fleet_center + rear * 2800.0 + lateral * offset
	if support_ship.global_position.distance_squared_to(desired) < 250.0 * 250.0:
		desired = support_ship.global_position
	return _make_result(desired, -rear, 1.0, &"support")


func calculate_disengage_position(
		owner_ship: ShipUnit,
		fleet_center: Vector3,
		threat_direction: Vector3
) -> TacticalPositionResult:
	threat_direction.y = 0.0
	var away := -threat_direction.normalized() \
		if threat_direction.length_squared() > 0.01 else Vector3.BACK
	var toward_fleet := _flat_direction(owner_ship.global_position, fleet_center)
	var toward_center := -owner_ship.global_position
	toward_center.y = 0.0
	var direction := away * 0.55
	if toward_fleet.length_squared() > 0.01:
		direction += toward_fleet.normalized() * 0.3
	if toward_center.length_squared() > 0.01:
		direction += toward_center.normalized() * 0.15
	if direction.length_squared() < 0.01:
		direction = away
	direction = direction.normalized()
	return _make_result(
		owner_ship.global_position + direction * 3000.0,
		direction,
		1.0,
		&"disengage"
	)


func _calculate_line_side(
		owner_ship: ShipUnit,
		target_ship: ShipUnit,
		preferred_distance_m: float,
		side_sign: float,
		lateral_offset_m: float
) -> TacticalPositionResult:
	var radial := _flat_direction(target_ship.global_position, owner_ship.global_position)
	if radial.length_squared() < 0.01:
		radial = Vector3.BACK
	radial = radial.normalized()
	var resolved_side := -1.0 if side_sign < 0.0 else 1.0
	var tangent := Vector3(-radial.z, 0.0, radial.x) * resolved_side
	return _make_result(
		target_ship.global_position + radial * preferred_distance_m + tangent * lateral_offset_m,
		tangent,
		resolved_side,
		&"line"
	)


func _calculate_flank_side(
		owner_ship: ShipUnit,
		target_ship: ShipUnit,
		side_sign: float
) -> TacticalPositionResult:
	var radial := _flat_direction(target_ship.global_position, owner_ship.global_position)
	if radial.length_squared() < 0.01:
		radial = Vector3.BACK
	radial = radial.normalized()
	var resolved_side := -1.0 if side_sign < 0.0 else 1.0
	var tangent := Vector3(-radial.z, 0.0, radial.x) * resolved_side
	return _make_result(
		target_ship.global_position + radial * 3200.0 + tangent * 2600.0,
		tangent,
		resolved_side,
		&"flank"
	)


func _make_result(
		desired_position: Vector3,
		heading: Vector3,
		side_sign: float,
		reason: StringName
) -> TacticalPositionResult:
	desired_position.y = 0.0
	heading.y = 0.0
	if not desired_position.is_finite() or not heading.is_finite():
		return TacticalPositionResult.new().setup(
			Vector3.ZERO, Vector3.FORWARD, false, false, side_sign, &"non_finite"
		)
	var clamped_position := _clamp(desired_position)
	var clamp_distance := desired_position.distance_to(clamped_position)
	return TacticalPositionResult.new().setup(
		clamped_position,
		heading,
		true,
		clamp_distance > 1.0,
		side_sign,
		reason,
		clamp_distance
	)


func _calculate_safe_fallback(
		owner_ship: ShipUnit,
		heading: Vector3,
		side_sign: float,
		reason: StringName
) -> TacticalPositionResult:
	var toward_center := -owner_ship.global_position
	toward_center.y = 0.0
	if toward_center.length_squared() < 0.01:
		toward_center = Vector3.FORWARD
	var result := _make_result(
		owner_ship.global_position + toward_center.normalized() * 1200.0,
		heading,
		side_sign,
		reason
	)
	result.was_clamped = true
	return result


func clamp_position(position: Vector3) -> Vector3:
	return _clamp(position)


func _clamp(position: Vector3) -> Vector3:
	position.y = 0.0
	if battlefield_bounds != null:
		return battlefield_bounds.clamp_to_bounds(position, boundary_margin_m)
	return position


func _flat_direction(from: Vector3, to: Vector3) -> Vector3:
	var direction := to - from
	direction.y = 0.0
	return direction

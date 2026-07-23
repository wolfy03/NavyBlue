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
		lateral_offset_m: float
) -> Vector3:
	var radial := owner_ship.global_position - target_ship.global_position
	radial.y = 0.0
	if radial.length_squared() < 1.0:
		radial = Vector3.BACK
	radial = radial.normalized()
	var tangent := Vector3(-radial.z, 0.0, radial.x) * signf(side_sign)
	return _clamp(
		target_ship.global_position
			+ radial * preferred_distance_m
			+ tangent * lateral_offset_m
	)


func calculate_escort_position(
		_escort_ship: ShipUnit,
		protected_ship: ShipUnit,
		threat_position: Vector3,
		slot_index: int
) -> Vector3:
	var threat_direction := threat_position - protected_ship.global_position
	threat_direction.y = 0.0
	if threat_direction.length_squared() < 1.0:
		threat_direction = -protected_ship.global_transform.basis.z
	var lateral := Vector3(
		-threat_direction.normalized().z,
		0.0,
		threat_direction.normalized().x
	)
	var side := -1.0 if slot_index % 2 == 0 else 1.0
	var distance_m := 900.0 + float(slot_index / 2) * 250.0
	return _clamp(protected_ship.global_position + lateral * side * distance_m)


func calculate_screen_position(
		_screen_ship: ShipUnit,
		protected_ship: ShipUnit,
		threat_direction: Vector3,
		slot_index: int
) -> Vector3:
	threat_direction.y = 0.0
	if threat_direction.length_squared() < 1.0:
		threat_direction = -protected_ship.global_transform.basis.z
	threat_direction = threat_direction.normalized()
	var lateral := Vector3(-threat_direction.z, 0.0, threat_direction.x)
	var slot_offset := (float(slot_index) - 0.5) * 500.0
	return _clamp(
		protected_ship.global_position
			+ threat_direction * 1500.0
			+ lateral * slot_offset
	)


func calculate_flank_position(
		owner_ship: ShipUnit,
		target_ship: ShipUnit,
		side_sign: float
) -> Vector3:
	var radial := owner_ship.global_position - target_ship.global_position
	radial.y = 0.0
	if radial.length_squared() < 1.0:
		radial = Vector3.BACK
	radial = radial.normalized()
	var tangent := Vector3(-radial.z, 0.0, radial.x) * signf(side_sign)
	return _clamp(target_ship.global_position + radial * 3200.0 + tangent * 2600.0)


func calculate_support_position(
		support_ship: ShipUnit,
		fleet_center: Vector3,
		safe_rear_direction: Vector3,
		slot_index: int
) -> Vector3:
	var rear := safe_rear_direction
	rear.y = 0.0
	if rear.length_squared() < 1.0:
		rear = Vector3.BACK
	rear = rear.normalized()
	var lateral := Vector3(-rear.z, 0.0, rear.x)
	var offset := (float(slot_index) - 0.5) * 650.0
	var desired := fleet_center + rear * 2800.0 + lateral * offset
	if support_ship.global_position.distance_squared_to(desired) < 250.0 * 250.0:
		desired = support_ship.global_position
	return _clamp(desired)


func calculate_disengage_position(
		owner_ship: ShipUnit,
		fleet_center: Vector3,
		threat_direction: Vector3
) -> Vector3:
	threat_direction.y = 0.0
	var away := -threat_direction.normalized() \
		if threat_direction.length_squared() > 1.0 else Vector3.BACK
	var toward_fleet := fleet_center - owner_ship.global_position
	toward_fleet.y = 0.0
	var toward_center := -owner_ship.global_position
	toward_center.y = 0.0
	var direction := away * 0.55
	if toward_fleet.length_squared() > 1.0:
		direction += toward_fleet.normalized() * 0.3
	if toward_center.length_squared() > 1.0:
		direction += toward_center.normalized() * 0.15
	if direction.length_squared() < 1.0:
		direction = away
	return _clamp(owner_ship.global_position + direction.normalized() * 3000.0)


func _clamp(position: Vector3) -> Vector3:
	position.y = 0.0
	if battlefield_bounds != null:
		return battlefield_bounds.clamp_to_bounds(position, boundary_margin_m)
	return position

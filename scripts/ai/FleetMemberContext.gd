extends RefCounted
class_name FleetMemberContext

enum TacticalRole {
	LINE_COMBATANT,
	ESCORT,
	SCREEN,
	FLANKER,
	SUPPORT,
	INTERCEPT,
	DISENGAGE,
}

var ship_ref: WeakRef
var tactical_role: TacticalRole = TacticalRole.LINE_COMBATANT
var assigned_target_ref: WeakRef
var protected_ship_ref: WeakRef
var formation_slot_index := -1
var tactical_side_sign := 1.0
var tactical_position := Vector3.ZERO
var tactical_heading := Vector3.FORWARD
var tactical_position_valid := false
var tactical_heading_valid := false
var tactical_position_was_clamped := false
var last_side_change_sec := 0.0
var last_tactical_target_instance_id := 0
var tactical_error_offset := Vector3.ZERO
var tactical_error_expire_sec := 0.0
var tactical_error_target_instance_id := 0
var tactical_error_role: TacticalRole = TacticalRole.LINE_COMBATANT
var tactical_error_side_sign := 1.0
var tactical_error_profile_id: StringName = &""
var previous_tactical_role: TacticalRole = TacticalRole.LINE_COMBATANT
var temporary_role_reason: StringName = &""
var tactical_path_failure_count := 0
var last_tactical_path_failure_sec := -INF
var tactical_position_invalid_until_sec := 0.0
var last_role_change_sec := 0.0
var last_tactical_update_sec := 0.0
var assignment_priority := 0.0


func setup(ship: ShipUnit) -> FleetMemberContext:
	ship_ref = weakref(ship)
	tactical_side_sign = -1.0 if ship.get_instance_id() % 2 == 0 else 1.0
	tactical_error_side_sign = tactical_side_sign
	return self


func apply_tactical_result(result: TacticalPositionResult, target: ShipUnit, now_sec: float) -> void:
	if result == null or not result.valid:
		tactical_position_valid = false
		tactical_heading_valid = false
		return
	tactical_position = result.position
	tactical_heading = result.heading
	tactical_position_valid = true
	tactical_heading_valid = result.heading.length_squared() > 0.01
	tactical_position_was_clamped = result.was_clamped
	last_tactical_update_sec = now_sec
	last_tactical_target_instance_id = target.get_instance_id() if target != null else 0


func get_ship() -> ShipUnit:
	return ship_ref.get_ref() as ShipUnit if ship_ref != null else null


func set_assigned_target(target: ShipUnit) -> void:
	assigned_target_ref = weakref(target) if target != null else null


func get_assigned_target() -> ShipUnit:
	return assigned_target_ref.get_ref() as ShipUnit \
		if assigned_target_ref != null else null


func set_protected_ship(ship: ShipUnit) -> void:
	protected_ship_ref = weakref(ship) if ship != null else null


func get_protected_ship() -> ShipUnit:
	return protected_ship_ref.get_ref() as ShipUnit \
		if protected_ship_ref != null else null


func get_role_name() -> StringName:
	return StringName(TacticalRole.keys()[tactical_role].to_lower())

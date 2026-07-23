extends Resource
class_name ShipData

enum ShipClass {
	DESTROYER,
	CRUISER,
	BATTLESHIP,
	AIRCRAFT_CARRIER,
}

@export var id := ""
@export var display_name := ""
@export var ship_class: ShipClass = ShipClass.DESTROYER
@export_category("Mobility (SI units)")
@export var max_speed_mps := 42.0
@export var cruise_speed_mps := 34.0
@export var max_reverse_speed_mps := 8.0
@export var acceleration_mps2 := 2.1
@export var deceleration_mps2 := 3.0
@export var max_turn_rate_deg_sec := 7.0
@export var turn_acceleration_deg_sec2 := 2.5
@export var arrival_slowdown_distance_m := 700.0
@export var minimum_turning_speed_mps := 8.0
@export var navigation_safety_radius_m := 90.0

# Runtime mobility code uses the SI fields above as its canonical values.
# Compatibility aliases remain serialized for saves/upgrades made before the SI migration.
# TODO: Migrate upgrade resources, then remove these aliases in a versioned data migration.
@export var max_forward_speed := 42.0
@export var max_reverse_speed := 8.0
@export var engine_response := 0.55
@export var turn_rate_degrees := 7.0
@export var hull_size := Vector3(2.2, 0.8, 7.0)
@export var turret_count := 2
@export var turret_spacing := 1.8
@export var shell_muzzle_velocity := 34.0
@export var reload_seconds := 1.2
@export var default_weapon_id: String = "destroyer_cannon"
@export var defense_stats: ShipDefenseStats


func validate_compatibility_fields(context: String = "") -> PackedStringArray:
	var warnings := PackedStringArray()
	var label := context if not context.is_empty() else id
	_append_mismatch_warning(warnings, label, "max_speed_mps", max_speed_mps, "max_forward_speed", max_forward_speed)
	_append_mismatch_warning(
		warnings,
		label,
		"max_reverse_speed_mps",
		max_reverse_speed_mps,
		"max_reverse_speed",
		max_reverse_speed
	)
	_append_mismatch_warning(
		warnings,
		label,
		"max_turn_rate_deg_sec",
		max_turn_rate_deg_sec,
		"turn_rate_degrees",
		turn_rate_degrees
	)
	return warnings


func _append_mismatch_warning(
		warnings: PackedStringArray,
		context: String,
		canonical_name: String,
		canonical_value: float,
		compatibility_name: String,
		compatibility_value: float
) -> void:
	if is_equal_approx(canonical_value, compatibility_value):
		return
	warnings.append(
		"ShipData '%s' uses %s=%.3f at runtime, but compatibility field %s=%.3f differs." % [
			context,
			canonical_name,
			canonical_value,
			compatibility_name,
			compatibility_value,
		]
	)

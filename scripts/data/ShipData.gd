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

@export var hull_size := Vector3(2.2, 0.8, 7.0)
@export_category("Weapons")
@export var weapon_slots: Array[ShipWeaponSlotData] = []
## Optional scripted Resource exposing build_slots() -> Array[ShipWeaponSlotData].
## Kept at the Resource boundary so headless validation does not depend on the
## editor's global class cache discovering a newly added layout script first.
@export var secondary_battery_layout: Resource

@export_group("Legacy Weapon Configuration")
# Deprecated: compatibility only. Do not use in new ship definitions.
@export var turret_count := 2
# Deprecated: compatibility only. Do not use in new ship definitions.
@export var turret_spacing := 1.8
# Deprecated: compatibility only. New weapon velocity lives in WeaponData.
@export var shell_muzzle_velocity := 34.0
# Deprecated: compatibility only. New weapon reload lives in WeaponData.
@export var reload_seconds := 1.2
# Deprecated: compatibility only. New defaults live on ShipWeaponSlotData.
@export var default_weapon_id: String = "destroyer_cannon"
@export_group("")
@export var defense_stats: ShipDefenseStats
@export var ai_role_profile: ShipAIRoleProfile
## Gunnery crew proficiency. Null falls back to default mid skills (0.5) in
## ShipGunneryFireControl until a full crew system exists.
@export var gunnery_crew_stats: GunneryCrewStats
@export var secondary_battery_profile: SecondaryBatteryProfile
@export var secondary_gunnery_crew_stats: GunneryCrewStats
@export_category("Combat Role")
@export var strategic_value := 1.0
@export var combat_role: StringName = &"line_combatant"

@export_category("Carrier")
@export var carrier_air_group_data: CarrierAirGroupData


func get_runtime_weapon_slots() -> Array[ShipWeaponSlotData]:
	var result: Array[ShipWeaponSlotData] = []
	for slot in weapon_slots:
		if slot != null:
			result.append(slot)
	if secondary_battery_layout != null \
			and secondary_battery_layout.has_method(&"build_slots"):
		var generated_value: Variant = secondary_battery_layout.call(
			&"build_slots"
		)
		if generated_value is Array:
			for generated_slot_value: Variant in generated_value:
				var generated_slot := generated_slot_value \
					as ShipWeaponSlotData
				if generated_slot != null:
					result.append(generated_slot)
	return result

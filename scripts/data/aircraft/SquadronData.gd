extends Resource
class_name SquadronData

@export var id: String = ""
@export var display_name: String = ""
@export var aircraft_data: AircraftData
@export_range(1, 64, 1, "or_greater") var aircraft_count: int = 4
@export var formation_spacing_m: float = 24.0
@export var launch_interval_sec: float = 0.25
@export var rearm_duration_sec: float = 15.0
@export var default_mission_data: AirMissionData

@export_category("Loiter")
@export var loiter_radius_m: float = 180.0
@export var loiter_angular_speed_deg_sec: float = 20.0
@export var loiter_clockwise: bool = true


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id.is_empty():
		errors.append("id must not be empty.")
	if aircraft_data == null:
		errors.append("aircraft_data must be assigned.")
		return errors
	if aircraft_count <= 0:
		errors.append("aircraft_count must be positive.")
	if loiter_radius_m <= 0.0:
		errors.append("loiter_radius_m must be positive.")
	if loiter_angular_speed_deg_sec <= 0.0:
		errors.append("loiter_angular_speed_deg_sec must be positive.")
	if aircraft_data.aircraft_scene == null:
		errors.append("aircraft_data.aircraft_scene must be assigned.")
	if aircraft_data.weapon_data == null:
		errors.append("aircraft_data.weapon_data must be assigned.")
	elif not aircraft_data.weapon_data.is_valid_configuration():
		errors.append("aircraft_data.weapon_data is invalid.")
	if default_mission_data == null:
		errors.append("default_mission_data must be assigned.")
		return errors

	match aircraft_data.role:
		AircraftData.AircraftRole.FIGHTER:
			if aircraft_data.weapon_data != null \
					and aircraft_data.weapon_data.weapon_type \
					!= AircraftWeaponData.WeaponType.AIR_TO_AIR_GUN:
				errors.append(
					"fighter squadrons require an AIR_TO_AIR_GUN."
				)
			if default_mission_data.mission_type \
					!= AirMissionData.MissionType.INTERCEPT_AIRCRAFT:
				errors.append(
					"fighter squadrons require an INTERCEPT_AIRCRAFT mission."
				)
		AircraftData.AircraftRole.DIVE_BOMBER:
			if aircraft_data.weapon_data != null \
					and aircraft_data.weapon_data.weapon_type \
					!= AircraftWeaponData.WeaponType.BOMB:
				errors.append("dive bomber squadrons require a BOMB.")
			if default_mission_data.mission_type \
					!= AirMissionData.MissionType.STRIKE_SHIP:
				errors.append(
					"dive bomber squadrons require a STRIKE_SHIP mission."
				)
	return errors

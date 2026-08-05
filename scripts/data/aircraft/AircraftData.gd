extends Resource
class_name AircraftData

enum AircraftRole {
	FIGHTER,
	DIVE_BOMBER,
	TORPEDO_BOMBER,
	RECON,
}

@export var id: String = ""
@export var display_name: String = ""
@export var role: AircraftRole = AircraftRole.DIVE_BOMBER

@export_category("Movement")
@export var cruise_speed_mps: float = 120.0
@export var maximum_speed_mps: float = 170.0
@export var turn_rate_deg_sec: float = 45.0
@export var operating_altitude_m: float = 180.0
@export var combat_radius_m: float = 8000.0
@export var arrival_distance_m: float = 40.0

@export_category("Survivability")
@export var maximum_hp: float = 30.0

@export_category("Armament")
@export var weapon_data: AircraftWeaponData

@export_category("Fighter")
@export var fighter_combat_data: FighterCombatData

@export_category("Dive Bomber")
@export var dive_bomber_combat_data: DiveBomberCombatData

@export_category("Torpedo Bomber")
@export var torpedo_attack_profile: TorpedoAttackProfile

@export_category("Visual")
@export var aircraft_scene: PackedScene
## Visual-only turn banking of the aircraft model. Null uses built-in
## defaults; the physics root never rolls either way.
@export var bank_visual_settings: AircraftBankVisualSettings

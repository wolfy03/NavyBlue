extends Resource
class_name AircraftWeaponData

enum WeaponType {
	BOMB,
	TORPEDO,
	AIR_TO_AIR_GUN,
	AIR_TO_AIR_MISSILE,
	RECON_PAYLOAD,
}

enum ReleaseMode {
	SINGLE,
	RIPPLE,
	SALVO,
}

@export var id: String = ""
@export var display_name: String = ""
@export var weapon_type: WeaponType = WeaponType.BOMB

@export_category("Payload")
@export var projectile_data: ProjectileData
@export var projectile_scene: PackedScene
@export_range(0, 64, 1) var ammunition_per_sortie: int = 1

@export_category("Release")
@export var release_mode: ReleaseMode = ReleaseMode.SINGLE
@export_range(1, 16, 1) var projectiles_per_release: int = 1
@export var release_interval_sec: float = 0.2
# Legacy release-envelope fields below are consumed only by BOMB / dive-bomber
# weapons (see supports_release()). Torpedo bombers do NOT read them: their
# release altitude/distance envelope lives on TorpedoAttackProfile, which is the
# authoritative source for all torpedo attack-run geometry. Do not reference
# these from torpedo controllers or resolvers.
@export var minimum_release_distance_m: float = 80.0
@export var maximum_release_distance_m: float = 350.0
@export var minimum_release_altitude_m: float = 50.0
@export var maximum_release_altitude_m: float = 180.0
@export var downward_release_speed_mps: float = 20.0

@export_category("Mission")
# Legacy dive-bomb approach/egress distances. Torpedo bombers use
# TorpedoAttackProfile.approach_distance_m / escape_distance_m instead; these two
# fields are retained for BOMB weapons and must not be used by the torpedo path.
@export var attack_approach_distance_m: float = 1000.0
@export var attack_egress_distance_m: float = 700.0
@export var return_after_ammunition_depleted: bool = true

@export_category("Gun")
@export var gun_data: AircraftGunData


func is_valid_configuration() -> bool:
	if id.is_empty():
		return false
	match weapon_type:
		WeaponType.BOMB, WeaponType.TORPEDO:
			return _is_valid_released_payload()
		WeaponType.AIR_TO_AIR_GUN:
			return gun_data != null \
				and gun_data.is_valid_configuration() \
				and ammunition_per_sortie > 0
		WeaponType.AIR_TO_AIR_MISSILE:
			return projectile_data != null \
				and projectile_scene != null
		WeaponType.RECON_PAYLOAD:
			return true
	return false


func supports_release(distance_m: float, altitude_m: float) -> bool:
	return distance_m >= maxf(minimum_release_distance_m, 0.0) \
		and distance_m <= maxf(maximum_release_distance_m, 0.0) \
		and altitude_m >= maxf(minimum_release_altitude_m, 0.0) \
		and altitude_m <= maxf(maximum_release_altitude_m, 0.0)


func _is_valid_released_payload() -> bool:
	return projectile_data != null \
		and projectile_scene != null \
		and ammunition_per_sortie > 0 \
		and projectiles_per_release > 0 \
		and maximum_release_distance_m >= minimum_release_distance_m \
		and maximum_release_altitude_m >= minimum_release_altitude_m

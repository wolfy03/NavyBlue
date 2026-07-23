extends Resource
class_name WeaponData

# Treat this Resource as immutable runtime configuration. Per-ship changes belong
# in WeaponRuntimeStats or a WeaponMount instance.

@export_category("Identity")
@export var id: String = ""
@export var display_name: String = ""
@export var weapon_type: WeaponTypes.Type = WeaponTypes.Type.CANNON

@export_category("Mount")
@export var required_slot_size: WeaponTypes.SlotSize = WeaponTypes.SlotSize.MEDIUM
@export var mount_scene: PackedScene

@export_category("Combat")
@export var reload_seconds: float = 1.0
@export var range_meters: float = 8000.0
@export var minimum_range_meters: float = 0.0

@export_category("Cannon Compatibility")
@export var muzzle_velocity: float = 30.0
@export var turret_turn_speed_degrees: float = 7.5
@export var max_pitch_degrees: float = 55.0

@export_category("Projectile")
@export var projectile_data: ProjectileData
@export var projectile_scene: PackedScene

@export_category("AI")
@export var preferred_engagement_range_ratio := 0.75
@export var tactical_value := 1.0

@export_category("Legacy")
@export var damage: float = 10.0

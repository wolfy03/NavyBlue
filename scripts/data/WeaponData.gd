extends Resource
class_name WeaponData

@export var id: String = ""
@export var display_name: String = ""
@export var weapon_type: String = "cannon"
@export var reload_seconds: float = 1.0
@export var muzzle_velocity: float = 30.0
@export var turret_turn_speed_degrees: float = 7.5
@export var max_pitch_degrees: float = 55.0
@export var range_meters: float = 8000.0
@export var projectile_data: ProjectileData
@export var projectile_scene: PackedScene

# Compatibility field for systems that still inspect weapon damage directly.
@export var damage: float = 10.0

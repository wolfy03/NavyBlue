extends Resource
class_name ProjectileData

@export var id: String = ""
@export var display_name: String = ""
@export var projectile_type: String = "shell"

@export var damage: float = 100.0
@export var penetration: float = 50.0
@export var muzzle_velocity: float = 120.0
@export var gravity_scale: float = 1.0
@export var lifetime_seconds: float = 8.0

@export var splash_strength: float = 1.0
@export var explosion_radius: float = 0.0

@export var armor_damage_multiplier: float = 1.0
@export var non_penetration_damage_multiplier: float = 0.1
@export var always_damage_multiplier: float = 0.0

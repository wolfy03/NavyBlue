extends Resource
class_name ProjectileData

# Treat this Resource as immutable runtime configuration. Projectile instances
# own movement, lifetime, target, and damage modifier state.

@export var id: String = ""
@export var display_name: String = ""
@export var damage: float = 100.0
@export var lifetime_seconds: float = 8.0
@export var explosion_radius: float = 0.0
@export var splash_strength: float = 1.0
@export var projectile_scene: PackedScene

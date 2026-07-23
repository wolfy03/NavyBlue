extends ProjectileData
class_name ShellProjectileData

@export var shell_type: ShellStats.ShellType = ShellStats.ShellType.AP
@export var penetration := 50.0
@export var muzzle_velocity := 120.0
@export var gravity_scale := 1.0
@export var penetration_damage_multiplier := 1.0
@export var non_penetration_damage_multiplier := 0.1
@export var ricochet_damage_multiplier := 0.0

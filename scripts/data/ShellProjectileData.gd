extends ProjectileData
class_name ShellProjectileData

@export var shell_type: ShellStats.ShellType = ShellStats.ShellType.AP
@export var penetration := 50.0
@export var muzzle_velocity := 120.0
@export var gravity_scale := 1.0
@export_range(0.01, 1000.0, 0.01, "or_greater") var mass_kg := 25.0
@export var penetration_damage_multiplier := 1.0
@export var non_penetration_damage_multiplier := 0.1
@export var ricochet_damage_multiplier := 0.0

@export_category("Visual Trail")
## Per-shell visual profile. Defaults preserve the existing main-gun trail;
## individual ProjectileData resources can distinguish smaller-calibre rounds
## without duplicating the shared shell scene or projectile lifecycle.
@export var trail_enabled := true
@export_range(0.1, 3.0, 0.025, "or_greater") \
	var trail_lifetime_sec := 1.15
@export_range(0.5, 20.0, 0.25, "or_greater") var trail_width_m := 5.0
@export_range(16, 384, 1, "or_greater") var trail_particle_count := 160
@export var trail_color := Color(1.0, 0.66, 0.24, 0.9)

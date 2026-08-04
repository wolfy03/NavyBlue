extends Resource
class_name BattleDebugSettings

@export_category("Spawning")
@export var log_spawn_resolution := false

@export_category("Aircraft")
@export var log_aircraft_missions := false
@export var log_payload_release := false

@export_category("Projectile")
@export var log_projectile_lifecycle := false
@export var log_projectile_impacts := false

@export_category("Damage")
@export var log_damage_resolution := false

@export_category("AI")
@export var log_fleet_ai := false
@export var log_battle_ai := false
@export var log_gunnery_fire_control := false

@export_category("Effects")
@export var log_effect_spawns := false

@export_category("Performance Diagnostics")
## Development-only switches for isolating a frame-time bottleneck. These are
## diagnostic tools, not gameplay balance: all default to off and the shipping
## game never sets them.
@export var show_performance_overlay := false
## Stops secondary target search, aiming and firing while leaving main
## batteries and every other combat system untouched.
@export var disable_secondary_battery_runtime := false
## Secondary shells still spawn and fly normally; only their trail is skipped.
@export var disable_secondary_projectile_trails := false
## Everything up to and including the fire request runs; only the projectile
## instantiation is skipped.
@export var disable_secondary_projectile_spawn := false
## Spreads the expensive per-mount fire decision across frames.
@export var use_budgeted_secondary_mount_updates := false

@export_category("Visualization")
@export var show_command_markers := true

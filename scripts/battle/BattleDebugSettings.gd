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

@export_category("Effects")
@export var log_effect_spawns := false

@export_category("Visualization")
@export var show_command_markers := true

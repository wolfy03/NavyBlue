extends ProjectileData
class_name TorpedoProjectileData

enum GuidanceType {
	NONE,
	PASSIVE_HOMING,
	ACTIVE_HOMING,
	WAYPOINT,
}

@export_category("Movement")
@export var launch_speed_mps := 15.0
@export var max_speed_mps := 30.0
@export var acceleration_mps2 := 3.0
@export var running_depth_m := 1.0
@export var max_turn_rate_deg_sec := 0.0
@export var maximum_range_m := 8000.0

@export_category("Guidance")
@export var guidance_type: GuidanceType = GuidanceType.NONE
@export var seeker_activation_distance_m := 0.0
@export var seeker_range_m := 0.0
@export_range(0.0, 360.0, 1.0) var seeker_field_of_view_degrees := 90.0

@export_category("Warhead")
@export var direct_damage := 250.0
@export var explosion_damage := 150.0
@export_range(0.0, 1.0, 0.01) var flooding_chance := 0.35
@export var flooding_duration_seconds := 12.0
@export var flooding_damage_per_second := 4.0

@export_category("Safety")
@export var arming_distance_m := 50.0
@export var airborne_timeout_sec := 8.0
@export var water_entry_effect_strength := 1.0

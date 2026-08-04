extends RefCounted
class_name ProjectileLaunchContext

# A projectile source may be a ShipUnit, AircraftUnit, or future combat actor.
var source_actor: Node
# Deprecated: compatibility only. New code should use source_actor.
var source_ship: Node:
	get:
		return source_actor
	set(value):
		source_actor = value
var source_team: StringName = &"neutral"
var source_weapon_id: StringName
var source_projectile_data: ProjectileData
var initial_transform := Transform3D.IDENTITY
var initial_velocity := Vector3.ZERO
var aim_point := Vector3.ZERO
var target: Node3D
var runtime_stats := WeaponRuntimeStats.new()
## True when an automatic secondary battery fired this shell. Used only by
## diagnostic counters and the trail isolation toggle.
var from_secondary_battery := false
var torpedo_launch_mode: TorpedoLaunchMode.Type = \
	TorpedoLaunchMode.Type.SURFACE
var intended_launch_direction := Vector3.ZERO
var attack_command_id := 0

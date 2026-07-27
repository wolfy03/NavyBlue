extends RefCounted
class_name ProjectileLaunchContext

# A projectile source may be a ShipUnit or an AircraftUnit.
var source_ship: Node
var source_team: StringName = &"neutral"
var source_weapon_id: StringName
var initial_transform := Transform3D.IDENTITY
var initial_velocity := Vector3.ZERO
var aim_point := Vector3.ZERO
var target: Node3D
var runtime_stats := WeaponRuntimeStats.new()

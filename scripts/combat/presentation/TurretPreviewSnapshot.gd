extends RefCounted
class_name TurretPreviewSnapshot

var mount: WeaponMount
var mount_instance_id := 0
var origin := Vector3.ZERO
var direction := Vector3.FORWARD
var maximum_range_m := 0.0
var can_fire_now := false
var blocked_reason: StringName = &""
var visible := false

var has_weapon_data := false
var enabled := false
var has_ammunition := false
var reload_ready := false
var within_traverse_arc := false
var has_projectile_source := false
var muzzle_valid := false

extends RefCounted
class_name DamageRequest

var source_actor: Node
var source_team: StringName
var weapon_id: StringName
var projectile_data: ProjectileData
var target: Node3D
var hit_position := Vector3.ZERO
var hit_normal := Vector3.UP
var incoming_direction := Vector3.ZERO
var relative_velocity := Vector3.ZERO
var hit_info: HitInfo


static func from_hit_info(info: HitInfo) -> DamageRequest:
	var request := DamageRequest.new()
	request.hit_info = info
	if info == null:
		return request
	request.source_actor = info.get_attacker_ship()
	request.weapon_id = info.source_weapon_id
	request.target = info.target_ship
	request.hit_position = info.hit_position
	request.hit_normal = info.hit_normal
	request.incoming_direction = info.shell_direction
	return request

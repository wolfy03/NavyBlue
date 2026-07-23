class_name HitInfo
extends RefCounted

var shell_stats: ShellStats
var target_ship: Node3D
var hit_position: Vector3 = Vector3.ZERO
var hit_normal: Vector3 = Vector3.UP
var shell_direction: Vector3 = Vector3.FORWARD
var armor_part: ArmorPart.Type = ArmorPart.Type.BELT
var projectile_info: Dictionary = {}
var source_ship_instance_id := 0
var source_weapon_id: StringName
var _attacker_ref: WeakRef


func setup(
		stats: ShellStats,
		target: Node3D,
		position: Vector3,
		normal: Vector3,
		direction: Vector3,
		part: ArmorPart.Type
) -> HitInfo:
	shell_stats = stats
	target_ship = target
	hit_position = position
	hit_normal = normal.normalized() if normal.length_squared() > 0.000001 else Vector3.UP
	shell_direction = direction.normalized() if direction.length_squared() > 0.000001 else -hit_normal
	armor_part = part
	return self


func set_damage_source(
		attacker: Node,
		attacker_instance_id: int,
		weapon_id: StringName
) -> HitInfo:
	_attacker_ref = weakref(attacker) if attacker != null and is_instance_valid(attacker) else null
	source_ship_instance_id = attacker_instance_id
	source_weapon_id = weapon_id
	return self


func get_attacker_ship() -> Node:
	if _attacker_ref == null:
		return null
	return _attacker_ref.get_ref() as Node

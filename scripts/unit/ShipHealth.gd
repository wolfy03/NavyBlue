extends Node
class_name ShipHealth

signal died
signal damage_applied(amount: float, penetration_result: int, hit_info: HitInfo)
signal damage_result_applied(result: DamageResult)

@export var defense_stats: ShipDefenseStats
@export var debug_damage_log: bool = true

var _death_emitted: bool = false

var max_health: float:
	get:
		return defense_stats.max_hp if defense_stats != null else 0.0
	set(value):
		_ensure_defense_stats()
		defense_stats.max_hp = maxf(value, 1.0)
		defense_stats.current_hp = minf(defense_stats.current_hp, defense_stats.max_hp)

var current_health: float:
	get:
		return defense_stats.current_hp if defense_stats != null else 0.0
	set(value):
		_ensure_defense_stats()
		defense_stats.current_hp = clampf(value, 0.0, defense_stats.max_hp)

func _ready() -> void:
	setup(defense_stats)


func setup(stats: ShipDefenseStats) -> void:
	if stats == null:
		defense_stats = ShipDefenseStats.new()
	else:
		defense_stats = stats.duplicate(true) as ShipDefenseStats
	defense_stats.resource_local_to_scene = true
	defense_stats.reset_health()
	_death_emitted = false


func get_defense_stats() -> ShipDefenseStats:
	_ensure_defense_stats()
	return defense_stats


func apply_damage(
		amount: float,
		penetration_result: int = PenetrationResolver.Result.NON_PENETRATED,
		hit_info: HitInfo = null
) -> float:
	var result := DamageResult.new()
	result.hit_info = hit_info
	result.target_ship = get_parent() as Node3D
	result.damage_type = hit_info.damage_type \
		if hit_info != null else DamageType.Type.SHELL_AP
	result.hit_outcome = HitOutcome.from_damage(
		result.damage_type,
		penetration_result
	)
	result.penetration_result = penetration_result
	result.raw_damage = amount
	return apply_damage_result(result)


func apply_damage_result(result: DamageResult) -> float:
	if result == null:
		return 0.0
	_ensure_defense_stats()
	var raw_damage: float = maxf(result.raw_damage, 0.0)
	var reduction: float = clampf(defense_stats.damage_reduction, 0.0, 0.95)
	var final_damage: float = raw_damage * (1.0 - reduction)
	defense_stats.current_hp = maxf(0.0, defense_stats.current_hp - final_damage)
	result.target_ship = get_parent() as Node3D
	result.applied_damage = final_damage
	result.final_damage = final_damage
	result.resolved = true
	damage_applied.emit(
		final_damage,
		result.penetration_result,
		result.hit_info
	)
	damage_result_applied.emit(result)
	if has_node("/root/EventBus"):
		var damage_info := {
			"damage_type": result.damage_type,
			"hit_outcome": result.hit_outcome,
			"penetration_result": result.penetration_result,
			"hit_info": result.hit_info,
		}
		if result.hit_info != null:
			damage_info.merge(result.hit_info.projectile_info, true)
			damage_info["attacker_ship"] = result.hit_info.get_attacker_ship()
			damage_info["source_ship_instance_id"] = result.hit_info.source_ship_instance_id
			damage_info["weapon_id"] = result.hit_info.source_weapon_id
		get_node("/root/EventBus").ship_damaged.emit(
			get_parent(),
			final_damage,
			damage_info
		)

	if debug_damage_log:
		_log_damage(result)
	if defense_stats.current_hp <= 0.0 and not _death_emitted:
		_death_emitted = true
		died.emit()
	return final_damage


func _ensure_defense_stats() -> void:
	if defense_stats == null:
		defense_stats = ShipDefenseStats.new()
		defense_stats.resource_local_to_scene = true


func _log_damage(result: DamageResult) -> void:
	var part_name: StringName = &"UNKNOWN"
	if result.hit_info != null:
		part_name = ArmorPart.get_part_name(result.hit_info.armor_part)
	print(
		"[ShipDamage] target=%s type=%d result=%s part=%s damage=%.2f hp=%.2f/%.2f" % [
			get_parent().name if get_parent() != null else name,
			result.damage_type,
			HitOutcome.get_type_name(result.hit_outcome),
			part_name,
			result.final_damage,
			defense_stats.current_hp,
			defense_stats.max_hp,
		]
	)

extends Node
class_name ShipHealth

signal died
signal damage_applied(amount: float, penetration_result: int, hit_info: HitInfo)

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
	_ensure_defense_stats()
	var raw_damage: float = maxf(amount, 0.0)
	var reduction: float = clampf(defense_stats.damage_reduction, 0.0, 0.95)
	var final_damage: float = raw_damage * (1.0 - reduction)
	defense_stats.current_hp = maxf(0.0, defense_stats.current_hp - final_damage)
	damage_applied.emit(final_damage, penetration_result, hit_info)
	if has_node("/root/EventBus"):
		var damage_info := {
			"penetration_result": penetration_result,
			"hit_info": hit_info,
		}
		if hit_info != null:
			damage_info.merge(hit_info.projectile_info, true)
		get_node("/root/EventBus").ship_damaged.emit(
			get_parent(),
			final_damage,
			damage_info
		)

	if debug_damage_log:
		_log_damage(final_damage, penetration_result, hit_info)
	if defense_stats.current_hp <= 0.0 and not _death_emitted:
		_death_emitted = true
		died.emit()
	return final_damage


func _ensure_defense_stats() -> void:
	if defense_stats == null:
		defense_stats = ShipDefenseStats.new()
		defense_stats.resource_local_to_scene = true


func _log_damage(final_damage: float, penetration_result: int, hit_info: HitInfo) -> void:
	var part_name: StringName = &"UNKNOWN"
	if hit_info != null:
		part_name = ArmorPart.get_part_name(hit_info.armor_part)
	print(
		"[ShipDamage] target=%s result=%s part=%s damage=%.2f hp=%.2f/%.2f" % [
			get_parent().name if get_parent() != null else name,
			PenetrationResolver.get_result_name(penetration_result),
			part_name,
			final_damage,
			defense_stats.current_hp,
			defense_stats.max_hp,
		]
	)

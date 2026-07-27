extends Node
class_name ShipDamageStatus

signal flooding_started
signal flooding_updated(time_left: float)
signal flooding_ended

@export_range(0.1, 1.0, 0.05) var flooding_speed_multiplier := 0.75

var flooding_time_left := 0.0
var flooding_damage_per_second := 0.0
var flooding_source: HitInfo
var health: ShipHealth


func _ready() -> void:
	health = get_parent().get_node_or_null("ShipHealth") as ShipHealth


func _physics_process(delta: float) -> void:
	if flooding_time_left <= 0.0 or health == null:
		return
	flooding_time_left = maxf(0.0, flooding_time_left - delta)
	var damage := flooding_damage_per_second * delta
	if damage > 0.0:
		var result := DamageResult.new()
		result.hit_info = flooding_source
		result.target_ship = get_parent() as Node3D
		result.damage_type = DamageType.Type.FLOODING
		result.hit_outcome = HitOutcome.Type.STATUS_DAMAGE
		result.raw_damage = damage
		health.apply_damage_result(result)
	flooding_updated.emit(flooding_time_left)
	if flooding_time_left <= 0.0:
		_clear_flooding()


func apply_flooding(
		duration_seconds: float,
		damage_per_second: float,
		source: HitInfo
) -> void:
	if duration_seconds <= 0.0 or damage_per_second <= 0.0:
		return
	var was_flooding := flooding_time_left > 0.0
	flooding_time_left = maxf(flooding_time_left, duration_seconds)
	flooding_damage_per_second = maxf(
		flooding_damage_per_second,
		damage_per_second
	)
	flooding_source = source
	if not was_flooding:
		flooding_started.emit()
		if has_node("/root/EventBus"):
			get_node("/root/EventBus").flooding_started.emit(
				get_parent(),
				flooding_time_left
			)


func is_flooding() -> bool:
	return flooding_time_left > 0.0


func get_movement_speed_multiplier() -> float:
	return flooding_speed_multiplier if is_flooding() else 1.0


func to_save_data() -> Dictionary:
	return {
		"flooding_time_left": flooding_time_left,
		"flooding_damage_per_second": flooding_damage_per_second,
	}


func restore_from_save_data(data: Dictionary) -> void:
	flooding_time_left = maxf(
		float(data.get("flooding_time_left", 0.0)),
		0.0
	)
	flooding_damage_per_second = maxf(
		float(data.get("flooding_damage_per_second", 0.0)),
		0.0
	)
	# HitInfo contains runtime Node references and is intentionally not saved.
	flooding_source = null
	if flooding_time_left > 0.0 and flooding_damage_per_second > 0.0:
		flooding_started.emit()
	elif flooding_time_left <= 0.0:
		flooding_damage_per_second = 0.0


func _clear_flooding() -> void:
	flooding_time_left = 0.0
	flooding_damage_per_second = 0.0
	flooding_source = null
	flooding_ended.emit()
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").flooding_ended.emit(get_parent())

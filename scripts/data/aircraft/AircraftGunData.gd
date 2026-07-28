extends Resource
class_name AircraftGunData

@export var id: String = ""
@export var display_name: String = ""

@export_category("Ballistics")
@export var projectile_speed_mps: float = 750.0
@export var effective_range_m: float = 700.0
@export var optimal_range_m: float = 300.0
@export_range(0.0, 1.0, 0.01) var mechanical_accuracy: float = 0.8

@export_category("Burst")
@export var rounds_per_second: float = 12.0
@export_range(1, 100, 1) var rounds_per_burst: int = 8
@export var burst_cooldown_sec: float = 0.75
@export var damage_per_hit: float = 5.0
@export_range(1, 20, 1) var tracer_interval: int = 3


func is_valid_configuration() -> bool:
	return not id.is_empty() \
		and projectile_speed_mps > 0.0 \
		and effective_range_m > 0.0 \
		and optimal_range_m > 0.0 \
		and optimal_range_m <= effective_range_m \
		and rounds_per_second > 0.0 \
		and rounds_per_burst > 0 \
		and burst_cooldown_sec >= 0.0 \
		and damage_per_hit > 0.0


func get_burst_duration_sec() -> float:
	return float(maxi(rounds_per_burst, 1)) \
		/ maxf(rounds_per_second, 0.01)

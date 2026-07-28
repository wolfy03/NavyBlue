extends Resource
class_name CarrierAirGroupAIProfile

@export var decision_interval_sec := 1.5
@export_range(0.0, 1.0, 0.01) var launch_health_threshold := 0.4
@export_range(0.0, 1.0, 0.01) var recall_health_threshold := 0.25
@export var distance_weight := 1.0
@export var damaged_target_bonus := 24.0
@export var duplicate_target_penalty := 35.0
@export var strategic_value_weight := 20.0
@export var threat_to_carrier_weight := 18.0
@export_category("Air Defense")
@export var intercept_detection_range_m: float = 3000.0
@export var prioritize_interception := true
@export_range(1, 8, 1) var maximum_interceptors_per_target: int = 2
@export var ship_class_weights: Dictionary = {
	0: 10.0,
	1: 14.0,
	2: 20.0,
	3: 24.0,
}

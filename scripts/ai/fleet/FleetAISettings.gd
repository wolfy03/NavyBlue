extends Resource
class_name FleetAISettings

@export_category("Target Scoring")
@export var strategic_value_weight := 28.0
@export var sustained_dps_divisor := 8.0
@export var sustained_dps_cap := 20.0
@export var ready_salvo_divisor := 800.0
@export var torpedo_salvo_divisor := 1200.0
@export var salvo_score_cap := 4.0
@export var distance_score_weight := 24.0
@export var distance_reference_m := 24000.0
@export var emergency_bonus := 35.0
@export var duplicate_assignment_penalty := 4.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if sustained_dps_divisor <= 0.0:
		errors.append("sustained_dps_divisor must be greater than zero.")
	if ready_salvo_divisor <= 0.0 or torpedo_salvo_divisor <= 0.0:
		errors.append("salvo divisors must be greater than zero.")
	if distance_reference_m <= 0.0:
		errors.append("distance_reference_m must be greater than zero.")
	return errors

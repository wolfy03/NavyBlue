extends Resource
class_name FleetAISettings

@export_category("Targeting")
@export var secondary_target_limit := 3
@export var nearby_candidate_radius_m := 5500.0
@export var primary_target_minimum_hold_sec := 6.0
@export var primary_target_switch_ratio := 1.15
@export var primary_target_current_bonus := 8.0

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

@export_category("Emergency")
@export var emergency_hold_sec := 6.0
@export var emergency_defense_radius_m := 2400.0
@export var emergency_primary_hold_sec := 3.0
@export var emergency_primary_switch_ratio := 1.1
@export var ally_damage_share_radius_m := 3000.0

@export_category("Roles")
@export var role_minimum_hold_sec := 7.0

@export_category("Tactical")
@export var tactical_path_failure_cooldown_sec := 2.0
@export var maximum_error_clamp_distance_m := 100.0

@export_category("Lifecycle")
@export var empty_fleet_grace_sec := 10.0

@export_category("Scheduling")
# These defaults preserve the previous normal-difficulty cadence.
@export var fleet_update_interval_sec := 1.7
@export var role_update_interval_sec := 4.0
@export var tactical_update_interval_sec := 3.0
@export var cleanup_interval_sec := 1.5
@export var debug_update_interval_sec := 0.4


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if secondary_target_limit < 0:
		errors.append("secondary_target_limit must not be negative.")
	if nearby_candidate_radius_m <= 0.0:
		errors.append("nearby_candidate_radius_m must be greater than zero.")
	if primary_target_minimum_hold_sec < 0.0:
		errors.append("primary_target_minimum_hold_sec must not be negative.")
	if primary_target_switch_ratio <= 0.0:
		errors.append("primary_target_switch_ratio must be greater than zero.")
	if sustained_dps_divisor <= 0.0:
		errors.append("sustained_dps_divisor must be greater than zero.")
	if ready_salvo_divisor <= 0.0 or torpedo_salvo_divisor <= 0.0:
		errors.append("salvo divisors must be greater than zero.")
	if distance_reference_m <= 0.0:
		errors.append("distance_reference_m must be greater than zero.")
	if emergency_hold_sec < 0.0:
		errors.append("emergency_hold_sec must not be negative.")
	if emergency_defense_radius_m <= 0.0:
		errors.append("emergency_defense_radius_m must be greater than zero.")
	if role_minimum_hold_sec < 0.0:
		errors.append("role_minimum_hold_sec must not be negative.")
	if tactical_path_failure_cooldown_sec < 0.0:
		errors.append("tactical_path_failure_cooldown_sec must not be negative.")
	if maximum_error_clamp_distance_m < 0.0:
		errors.append("maximum_error_clamp_distance_m must not be negative.")
	if empty_fleet_grace_sec < 0.0:
		errors.append("empty_fleet_grace_sec must not be negative.")
	if fleet_update_interval_sec <= 0.0:
		errors.append("fleet_update_interval_sec must be greater than zero.")
	if role_update_interval_sec <= 0.0:
		errors.append("role_update_interval_sec must be greater than zero.")
	if tactical_update_interval_sec <= 0.0:
		errors.append("tactical_update_interval_sec must be greater than zero.")
	if cleanup_interval_sec <= 0.0:
		errors.append("cleanup_interval_sec must be greater than zero.")
	if debug_update_interval_sec <= 0.0:
		errors.append("debug_update_interval_sec must be greater than zero.")
	return errors

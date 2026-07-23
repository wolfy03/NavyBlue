extends RefCounted
class_name TargetEvaluationContext

var owner_ship: ShipUnit
var candidate: ShipUnit
var distance_m := 0.0
var distance_squared := 0.0
var weapon_range_m := 0.0
var preferred_distance_m := 0.0
var owner_health_ratio := 1.0
var candidate_health_ratio := 1.0
var attackers_on_candidate := 0
var recent_damage_to_owner := 0.0
var recent_damage_to_allies := 0.0
var recent_damage_to_owner_ratio := 0.0
var recent_damage_to_allies_ratio := 0.0
var candidate_combat_power := 0.0
var candidate_strategic_value := 0.0
var is_current_target := false
var is_emergency_threat := false
var candidate_is_aiming_at_owner := false
var fleet_recommendation_score := 0.0
var fleet_is_primary_target := false
var fleet_is_secondary_target := false
var fleet_is_emergency_target := false

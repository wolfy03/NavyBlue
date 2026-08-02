extends RefCounted
class_name TorpedoSafeRunDistanceResult

# Typed outcome of TorpedoSafeRunDistanceResolver. Separates the individual
# safety terms so the planner, the debug snapshot, and unit tests can inspect
# exactly how the release distance was derived instead of trusting one opaque
# constant.
#
# Distance model (all measured in the XZ plane along the attack direction):
#   release ──airborne_travel──► water-entry ──preferred_run──► target centre
#                                                    │
#                                        hull surface is collision_margin
#                                        short of the centre, so the armed
#                                        underwater run to the hull is
#                                        (preferred_run - collision_margin).
#
# arming is only accumulated AFTER water entry (TorpedoProjectile resets its
# travelled distance there), so the airborne travel must NOT be counted toward
# the arming requirement — it is tracked separately and added to the release
# offset from the target centre.

var success := false

var arming_distance_m := 0.0
var collision_margin_m := 0.0
var prediction_error_margin_m := 0.0
var additional_safety_margin_m := 0.0
var airborne_travel_margin_m := 0.0

# Underwater run distance (water-entry -> predicted target centre) that is the
# minimum for the torpedo to be armed by the time it reaches the hull.
var minimum_safe_run_distance_m := 0.0
# Underwater run distance the AI actually intends to use (>= minimum, optionally
# clamped by profile bounds).
var preferred_run_distance_m := 0.0

# Distance from the predicted target centre back to the release point, i.e.
# airborne_travel + preferred_run. The planner subtracts this along the attack
# direction to place the drop point.
var release_offset_from_center_m := 0.0
# Armed underwater run from the water-entry point to the hull surface. Used to
# size the torpedo run time in the lead predictor. Always >= arming distance on
# success.
var underwater_run_to_hull_m := 0.0

var failure_reason: StringName = &""


static func failed(reason: StringName) -> TorpedoSafeRunDistanceResult:
	var result := TorpedoSafeRunDistanceResult.new()
	result.success = false
	result.failure_reason = reason
	return result

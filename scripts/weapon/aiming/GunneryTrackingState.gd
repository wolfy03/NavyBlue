extends RefCounted
class_name GunneryTrackingState
## Persistent per-target fire-control state: the AI's current estimate of the
## target, tracking confidence, and accumulated fall-of-shot correction.

var target_ref: WeakRef
var target_instance_id := 0

var estimated_position := Vector3.ZERO
var estimated_velocity := Vector3.ZERO
var previous_actual_velocity := Vector3.ZERO

var range_bias_m := 0.0
var lateral_bias_m := 0.0

## 0..1 trust in the velocity estimate; sharp target maneuvers reduce it.
var confidence := 0.5
## 0..1 accumulated correction from consecutive salvos on the same target.
var correction_level := 0.0
var salvo_index := 0
var observation_epoch := 0
var last_observation_time_sec := 0.0
var has_observation := false


func reset_for_target(target: Node, instance_id: int) -> void:
	target_ref = weakref(target) if target != null else null
	target_instance_id = instance_id
	estimated_position = Vector3.ZERO
	estimated_velocity = Vector3.ZERO
	previous_actual_velocity = Vector3.ZERO
	range_bias_m = 0.0
	lateral_bias_m = 0.0
	confidence = 0.5
	correction_level = 0.0
	salvo_index = 0
	observation_epoch = 0
	last_observation_time_sec = 0.0
	has_observation = false

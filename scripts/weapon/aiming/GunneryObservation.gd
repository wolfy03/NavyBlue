extends RefCounted
class_name GunneryObservation
## What the AI fire-control believes about the target: a delayed, noisy view
## of the target's real position and velocity.

var observed_position := Vector3.ZERO
var observed_velocity := Vector3.ZERO
var observation_delay_sec := 0.0
var position_sigma_m := 0.0
var velocity_sigma_mps := 0.0

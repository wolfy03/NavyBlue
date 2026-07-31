extends RefCounted
class_name TorpedoAttackPreview

var entry_point := Vector3.ZERO
var cursor_point := Vector3.ZERO
var actual_release_point := Vector3.ZERO
var attack_direction := Vector3.FORWARD
var requested_distance_m := 0.0
var displayed_distance_m := 0.0
var minimum_distance_m := 0.0
var tail_locked := false
var distance_satisfied := false
var valid := false
var invalid_reason: StringName

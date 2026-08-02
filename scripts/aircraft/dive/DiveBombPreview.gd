extends RefCounted
class_name DiveBombPreview

# Snapshot the targeting session hands the circular preview: where the cursor is
# and how large the accuracy circle should be.

var target_point := Vector3.ZERO
var dispersion_radius_m := 0.0
var valid := false
var invalid_reason: StringName

extends RefCounted
class_name GunnerySalvoSolution
## One salvo's shared fire-control solution: every shell of the salvo shares
## the same biased center; only per-shell dispersion differs.

var command_id := 0
var salvo_index := 0
var salvo_seed := 0
var weapon_group_id: StringName = &""

var ideal_aim_point := Vector3.ZERO
var biased_salvo_center := Vector3.ZERO

var shared_range_error_m := 0.0
var shared_lateral_error_m := 0.0

var range_direction := Vector3.FORWARD
var lateral_direction := Vector3.RIGHT

var range_sigma_m := 0.0
var lateral_sigma_m := 0.0
var shell_dispersion_sigma_m := 0.0

var projectile_flight_time_sec := 0.0

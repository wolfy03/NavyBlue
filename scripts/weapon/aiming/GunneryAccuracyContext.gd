extends RefCounted
class_name GunneryAccuracyContext
## Inputs for one accuracy resolution. Instance ids and command/salvo indices
## feed the deterministic RNG seeds; the profiles supply the error model.

var shooter_instance_id := 0
var target_instance_id := 0
var fire_command_id := 0
var salvo_index := 0
var turret_index := 0
var shell_index := 0
var weapon_group_id: StringName = &""

var launch_position := Vector3.ZERO
var ideal_aim_point := Vector3.ZERO

var range_m := 0.0
var projectile_flight_time_sec := 0.0

var actual_target_velocity := Vector3.ZERO
var observed_target_velocity := Vector3.ZERO

## 0..1 accumulated fall-of-shot correction toward this target; shrinks the
## shared salvo bias on consecutive salvos.
var salvo_correction_level := 0.0

var weapon_accuracy_profile: GunneryWeaponAccuracyProfile
var difficulty_profile: AIGunneryDifficultyProfile
var crew_stats: GunneryCrewStats

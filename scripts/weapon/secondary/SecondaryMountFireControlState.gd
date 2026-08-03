extends RefCounted
class_name SecondaryMountFireControlState
## Per-mount fire-control state for independently firing batteries.
##
## Every secondary mount engages the battery's shared target with the shared
## weapon-group lead solution, but owns its own error state: its own tracking
## bias, its own fall-of-shot correction, and its own fire sequence index that
## seeds the deterministic RNG. One gun's correction never moves another gun's
## point of aim.

var mount_instance_id := 0
var weapon_data_instance_id := 0
## Monotonic per-mount shot counter. It keeps rising for the mount's whole
## lifetime (including across target changes) so two engagements of the same
## target can never reuse a seed.
var fire_sequence_index := 0

var tracking_state := GunneryTrackingState.new()

var last_aim_point := Vector3.ZERO
var last_fire_time_sec := 0.0
var last_solution_revision := 0

var shots_fired := 0
var last_failure_reason: StringName = &""


static func create(mount: CannonMount) -> SecondaryMountFireControlState:
	var state := SecondaryMountFireControlState.new()
	if mount != null and is_instance_valid(mount):
		state.mount_instance_id = mount.get_instance_id()
		state.bind_weapon(mount)
	return state


func bind_weapon(mount: CannonMount) -> void:
	weapon_data_instance_id = mount.weapon_data.get_instance_id() \
		if mount != null and is_instance_valid(mount) \
		and mount.weapon_data != null else 0


func is_bound_to_weapon(mount: CannonMount) -> bool:
	if mount == null or not is_instance_valid(mount):
		return false
	var next_weapon_id := mount.weapon_data.get_instance_id() \
		if mount.weapon_data != null else 0
	return weapon_data_instance_id == next_weapon_id


func reset_for_weapon(mount: CannonMount) -> void:
	bind_weapon(mount)
	tracking_state.reset_for_target(null, 0)
	last_aim_point = Vector3.ZERO
	last_solution_revision = 0
	last_failure_reason = &""


## Called when the battery switches target. The accumulated aim correction is
## meaningless against a new ship, but fire_sequence_index deliberately keeps
## counting so RNG seeds stay unique across engagements.
func reset_for_target(target: Node, target_instance_id: int) -> void:
	tracking_state.reset_for_target(target, target_instance_id)
	last_aim_point = Vector3.ZERO
	last_solution_revision = 0
	last_failure_reason = &""

extends RefCounted
class_name TurretPreviewSnapshotBuilder


func build(mount: WeaponMount) -> TurretPreviewSnapshot:
	var snapshot := TurretPreviewSnapshot.new()
	if mount == null or not is_instance_valid(mount):
		snapshot.blocked_reason = &"invalid_mount"
		return snapshot
	snapshot.mount = mount
	snapshot.mount_instance_id = mount.get_instance_id()
	snapshot.has_weapon_data = mount.weapon_data != null
	snapshot.enabled = mount.runtime_state.enabled
	snapshot.has_ammunition = mount.runtime_state.has_ammunition()
	snapshot.reload_ready = mount.reload_left <= 0.0
	snapshot.within_traverse_arc = \
		mount.is_current_target_within_traverse_arc()
	snapshot.has_projectile_source = mount.has_projectile_source()
	snapshot.muzzle_valid = mount.has_valid_preview_muzzle()
	snapshot.maximum_range_m = mount.get_runtime_maximum_range_m()
	snapshot.visible = mount.is_available_for_range_preview()
	if not snapshot.visible:
		snapshot.blocked_reason = _get_hidden_reason(snapshot, mount)
		return snapshot
	snapshot.origin = mount.get_preview_muzzle_position()
	snapshot.direction = mount.get_projectile_launch_direction_world()
	if not snapshot.origin.is_finite() \
			or not snapshot.direction.is_finite() \
			or snapshot.direction.length_squared() <= 0.0001:
		snapshot.visible = false
		snapshot.blocked_reason = &"invalid_muzzle"
		return snapshot
	snapshot.direction = snapshot.direction.normalized()
	var readiness := mount.get_current_fire_readiness()
	snapshot.can_fire_now = readiness == WeaponFireReadiness.State.READY
	snapshot.blocked_reason = &"" if snapshot.can_fire_now \
		else WeaponFireReadiness.get_state_name(readiness)
	return snapshot


func _get_hidden_reason(
		snapshot: TurretPreviewSnapshot,
		mount: WeaponMount
) -> StringName:
	if not snapshot.has_weapon_data:
		return &"invalid_weapon_data"
	if mount.get_weapon_type() != WeaponTypes.Type.CANNON:
		return &"not_cannon"
	if snapshot.maximum_range_m <= 0.0:
		return &"invalid_range"
	if not snapshot.muzzle_valid:
		return &"invalid_muzzle"
	return &"unavailable"

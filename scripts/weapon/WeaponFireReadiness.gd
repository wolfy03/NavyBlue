extends RefCounted
class_name WeaponFireReadiness

enum State {
	READY,
	NO_WEAPON_DATA,
	NO_AIM_POINT,
	INVALID_TARGET,
	RELOADING,
	INSIDE_MINIMUM_RANGE,
	OUT_OF_RANGE,
	OUTSIDE_TRAVERSE,
	NOT_ALIGNED,
	FRIENDLY_BLOCKED,
	NO_PROJECTILE,
	NO_PROJECTILE_SCENE,
	NO_MUZZLE,
	NO_AMMUNITION,
	NO_BALLISTIC_SOLUTION,
	NOT_ELEVATION_ALIGNED,
	WEAPON_DISABLED,
}


static func get_state_name(state: State) -> StringName:
	var index := int(state)
	if index < 0 or index >= State.size():
		return &"unknown"
	return StringName(String(State.keys()[index]).to_lower())

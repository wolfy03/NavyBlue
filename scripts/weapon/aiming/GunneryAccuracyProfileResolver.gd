extends RefCounted
class_name GunneryAccuracyProfileResolver

const SHARED_DEFAULT: GunneryWeaponAccuracyProfile = preload(
	"res://resources/weapon_accuracy/default_cannon_accuracy.tres"
)

static var _runtime_fallback: GunneryWeaponAccuracyProfile


static func resolve(
		weapon_profile: GunneryWeaponAccuracyProfile,
		shared_default: GunneryWeaponAccuracyProfile = SHARED_DEFAULT
) -> GunneryWeaponAccuracyProfile:
	if _is_valid_profile(weapon_profile):
		return weapon_profile
	if _is_valid_profile(shared_default):
		return shared_default
	if _runtime_fallback == null:
		_runtime_fallback = GunneryWeaponAccuracyProfile.new()
	return _runtime_fallback


static func _is_valid_profile(
		profile: GunneryWeaponAccuracyProfile
) -> bool:
	return profile != null and profile.validate().is_empty()

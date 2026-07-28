extends SceneTree

const FIGHTER: AircraftData = preload(
	"res://resources/aircraft/types/basic_fighter.tres"
)
const FIGHTER_SQUADRON: SquadronData = preload(
	"res://resources/aircraft/squadrons/basic_fighter_squadron.tres"
)

var _failures: Array[String] = []


func _initialize() -> void:
	var combat := FIGHTER.fighter_combat_data
	var weapon := FIGHTER.weapon_data
	_check(FIGHTER.role == AircraftData.AircraftRole.FIGHTER, "fighter role")
	_check(combat != null and combat.validate().is_empty(), "combat data valid")
	_check(
		weapon != null \
			and weapon.weapon_type \
				== AircraftWeaponData.WeaponType.AIR_TO_AIR_GUN \
			and weapon.is_valid_configuration(),
		"gun weapon validates without projectile scene"
	)
	_check(
		weapon.projectile_data == null and weapon.projectile_scene == null,
		"gun does not require gameplay projectile"
	)
	_check(
		FIGHTER_SQUADRON.default_mission_data != null \
			and FIGHTER_SQUADRON.default_mission_data.mission_type \
				== AirMissionData.MissionType.INTERCEPT_AIRCRAFT,
		"fighter squadron owns intercept mission"
	)
	_finish()


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	for failure in _failures:
		push_error("FIGHTER COMBAT DATA TEST: %s" % failure)
	print(
		"FIGHTER_COMBAT_DATA_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)

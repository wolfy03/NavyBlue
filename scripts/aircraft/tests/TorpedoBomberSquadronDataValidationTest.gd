extends SceneTree

# Verifies the tightened torpedo-bomber validation in SquadronData.validate():
# missing weapon_data, wrong weapon type, missing payload and missing default
# mission are each reported explicitly instead of being silently skipped.

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	# Missing weapon_data.
	var missing_weapon := _make_squadron_data()
	missing_weapon.aircraft_data.weapon_data = null
	_check(
		missing_weapon.validate().has(
			"torpedo bomber squadrons require weapon_data."
		),
		"missing weapon_data reported explicitly"
	)

	# Wrong weapon type.
	var wrong_type := _make_squadron_data()
	wrong_type.aircraft_data.weapon_data.weapon_type = \
		AircraftWeaponData.WeaponType.AIR_TO_AIR_GUN
	_check(
		wrong_type.validate().has(
			"torpedo bomber squadrons require a TORPEDO weapon."
		),
		"wrong weapon type reported explicitly"
	)

	# Torpedo weapon but no projectile payload.
	var missing_payload := _make_squadron_data()
	missing_payload.aircraft_data.weapon_data.projectile_data = null
	_check(
		missing_payload.validate().has(
			"torpedo bomber squadrons require projectile_data."
		),
		"missing projectile_data reported explicitly"
	)

	# Missing default mission is handled without crashing.
	var missing_mission := _make_squadron_data()
	missing_mission.default_mission_data = null
	var mission_errors := missing_mission.validate()
	_check(
		not mission_errors.is_empty() \
			and mission_errors.has("default_mission_data must be assigned."),
		"missing default mission fails safely"
	)

	missing_weapon = null
	wrong_type = null
	missing_payload = null
	missing_mission = null
	print(
		"TORPEDO_BOMBER_SQUADRON_DATA_VALIDATION_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _make_squadron_data() -> SquadronData:
	var weapon := AircraftWeaponData.new()
	weapon.id = "test_torpedo_weapon"
	weapon.weapon_type = AircraftWeaponData.WeaponType.TORPEDO
	weapon.projectile_data = TorpedoProjectileData.new()
	weapon.projectile_scene = PackedScene.new()
	weapon.ammunition_per_sortie = 1

	var aircraft := AircraftData.new()
	aircraft.id = "test_torpedo_bomber"
	aircraft.role = AircraftData.AircraftRole.TORPEDO_BOMBER
	aircraft.weapon_data = weapon
	aircraft.torpedo_attack_profile = TorpedoAttackProfile.new()

	var mission := AirMissionData.new()
	mission.id = "test_torpedo_mission"
	mission.mission_type = AirMissionData.MissionType.TORPEDO_ATTACK

	var data := SquadronData.new()
	data.id = "test_torpedo_squadron"
	data.aircraft_data = aircraft
	data.default_mission_data = mission
	return data


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("TORPEDO DATA VALIDATION: %s" % label)

extends SceneTree

var _failures := PackedStringArray()
var _database := WeaponDatabase.new()


func _initialize() -> void:
	var destroyer := _database.get_weapon("destroyer_cannon")
	var cruiser := _database.get_weapon("cruiser_cannon")
	var battleship := _database.get_weapon("battleship_cannon")
	var secondary := _database.get_weapon("carrier_secondary")
	var profiles := [
		destroyer.gunnery_accuracy_profile,
		cruiser.gunnery_accuracy_profile,
		battleship.gunnery_accuracy_profile,
		secondary.gunnery_accuracy_profile,
	]
	var profiles_valid := true
	for profile: Variant in profiles:
		if profile == null or not profile.validate().is_empty():
			profiles_valid = false
	_check(
		profiles_valid,
		"representative cannon resources own valid accuracy profiles"
	)
	_check(
		destroyer.gunnery_accuracy_profile
			!= battleship.gunnery_accuracy_profile
			and destroyer.gunnery_accuracy_profile.reference_range_m
				!= battleship.gunnery_accuracy_profile.reference_range_m,
		"destroyer and battleship profiles are independent"
	)
	var destroyer_sigma := _sigma_for(destroyer.gunnery_accuracy_profile)
	var battleship_sigma := _sigma_for(battleship.gunnery_accuracy_profile)
	var default_sigma := _sigma_for(
		GunneryAccuracyProfileResolver.SHARED_DEFAULT
	)
	_check(
		not is_equal_approx(destroyer_sigma, battleship_sigma),
		"different weapon profiles produce different sigma"
	)
	_check(
		destroyer_sigma >= default_sigma * 0.95
			and destroyer_sigma <= default_sigma * 1.1
			and battleship_sigma >= default_sigma * 0.95
			and battleship_sigma <= default_sigma * 1.1,
		"representative profiles preserve the established accuracy scale"
	)
	var shared := GunneryAccuracyProfileResolver.resolve(null)
	_check(
		shared == GunneryAccuracyProfileResolver.SHARED_DEFAULT,
		"null WeaponData profile uses the shared default"
	)
	print(
		"GUNNERY_WEAPON_ACCURACY_PROFILE_SELECTION_TEST failures=%d"
		% _failures.size()
	)
	quit(0 if _failures.is_empty() else 1)


func _sigma_for(profile: GunneryWeaponAccuracyProfile) -> float:
	var context := GunneryAccuracyContext.new()
	context.launch_position = Vector3.ZERO
	context.ideal_aim_point = Vector3(0.0, 0.0, 6000.0)
	context.range_m = 6000.0
	context.weapon_accuracy_profile = profile
	context.difficulty_profile = preload(
		"res://resources/ai_difficulty/gunnery_normal.tres"
	)
	context.crew_stats = GunneryCrewStats.new()
	return GunneryAccuracyResolver.compute_sigmas(context).range_sigma_m


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("GUNNERY PROFILE SELECTION: %s" % label)

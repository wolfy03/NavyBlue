extends SceneTree

# Verifies TorpedoAttackProfile.validate() enforces the numeric relationships,
# including the attack-run speed lying inside the release speed band (added so
# the attack run never asks for a speed the release envelope would reject).

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var profile := TorpedoAttackProfile.new()
	_check(profile.validate().is_empty(), "default profile validates")

	var high_run := TorpedoAttackProfile.new()
	high_run.attack_run_speed_mps = high_run.maximum_release_speed_mps + 10.0
	_check(
		not high_run.validate().is_empty(),
		"attack run faster than the release band is rejected"
	)

	var low_run := TorpedoAttackProfile.new()
	low_run.attack_run_speed_mps = low_run.minimum_release_speed_mps - 5.0
	_check(
		not low_run.validate().is_empty(),
		"attack run slower than the release band is rejected"
	)

	var bad_altitude := TorpedoAttackProfile.new()
	bad_altitude.maximum_release_altitude_m = \
		bad_altitude.release_altitude_m - 1.0
	_check(
		not bad_altitude.validate().is_empty(),
		"release altitude above the maximum envelope is rejected"
	)

	var bad_distance := TorpedoAttackProfile.new()
	bad_distance.minimum_attack_run_distance_m = 0.0
	_check(
		not bad_distance.validate().is_empty(),
		"non-positive minimum attack run distance is rejected"
	)

	profile = null
	high_run = null
	low_run = null
	bad_altitude = null
	bad_distance = null
	print(
		"TORPEDO_ATTACK_PROFILE_RELATIONSHIP_VALIDATION_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("TORPEDO PROFILE VALIDATION: %s" % label)

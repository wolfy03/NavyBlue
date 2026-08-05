extends SceneTree
## Statistical contract of the deterministic bombing-accuracy dispersion:
## accuracy 1.0 aims exactly (zero offset), lower accuracy scatters inside a
## shrinking disc, the same seed always reproduces the same offset, and the
## mean miss distance grows monotonically as accuracy drops.

const SEED_COUNT := 200
const MIN_RADIUS_M := 0.0
const MAX_RADIUS_M := 150.0

var _failures: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_perfect_accuracy_is_exact()
	_test_offsets_stay_inside_radius()
	_test_determinism()
	_test_monotonic_mean_error()
	print(
		"DIVE_BOMB_ACCURACY_DISPERSION_TEST failures=%d" % _failures.size()
	)
	for failure in _failures:
		push_error("DIVE BOMB ACCURACY DISPERSION: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _test_perfect_accuracy_is_exact() -> void:
	for seed_index in SEED_COUNT:
		var offset := DiveBombAttackResolver \
			.resolve_accuracy_dispersion_offset(
				1.0,
				MIN_RADIUS_M,
				MAX_RADIUS_M,
				_seed_for(seed_index)
			)
		if offset != Vector3.ZERO:
			_failures.append(
				"accuracy 1.0 must aim exactly (seed %d gave %s)"
				% [seed_index, offset]
			)
			return


func _test_offsets_stay_inside_radius() -> void:
	for accuracy in [0.0, 0.25, 0.5, 0.75]:
		var allowed: float = lerpf(MAX_RADIUS_M, MIN_RADIUS_M, accuracy)
		for seed_index in SEED_COUNT:
			var offset := DiveBombAttackResolver \
				.resolve_accuracy_dispersion_offset(
					accuracy,
					MIN_RADIUS_M,
					MAX_RADIUS_M,
					_seed_for(seed_index)
				)
			if offset.y != 0.0:
				_failures.append("dispersion must stay horizontal")
				return
			if offset.length() > allowed + 0.001:
				_failures.append(
					"accuracy %.2f offset %.1f m exceeds radius %.1f m"
					% [accuracy, offset.length(), allowed]
				)
				return


func _test_determinism() -> void:
	for seed_index in 16:
		var seed_value := _seed_for(seed_index)
		var first := DiveBombAttackResolver \
			.resolve_accuracy_dispersion_offset(
				0.5, MIN_RADIUS_M, MAX_RADIUS_M, seed_value
			)
		var second := DiveBombAttackResolver \
			.resolve_accuracy_dispersion_offset(
				0.5, MIN_RADIUS_M, MAX_RADIUS_M, seed_value
			)
		if first != second:
			_failures.append(
				"same seed must reproduce the same offset (seed %d)"
				% seed_index
			)
			return


func _test_monotonic_mean_error() -> void:
	var previous_mean := -1.0
	for accuracy in [1.0, 0.5, 0.0]:
		var total := 0.0
		for seed_index in SEED_COUNT:
			total += DiveBombAttackResolver \
				.resolve_accuracy_dispersion_offset(
					accuracy,
					MIN_RADIUS_M,
					MAX_RADIUS_M,
					_seed_for(seed_index)
				).length()
		var mean := total / float(SEED_COUNT)
		print(
			"DISPERSION accuracy=%.1f mean_offset_m=%.1f" % [accuracy, mean]
		)
		if mean <= previous_mean:
			_failures.append(
				"mean miss distance must grow as accuracy drops "
				+ "(accuracy %.1f mean %.1f m)" % [accuracy, mean]
			)
			return
		previous_mean = mean


func _seed_for(seed_index: int) -> int:
	# Mirrors the gameplay seed shape: squadron id, target id, pass, revision.
	return hash([1000 + seed_index, 2000 + seed_index * 7, 1, seed_index])

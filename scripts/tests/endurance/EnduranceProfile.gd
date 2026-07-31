extends RefCounted
class_name EnduranceProfile

const SMOKE := &"smoke"
const EXTENDED_SMOKE := &"extended_smoke"
const SEEDED_ENDURANCE := &"seeded_endurance"
const NIGHTLY_ENDURANCE := &"nightly_endurance"

const SMOKE_FRAMES := 600
const EXTENDED_SMOKE_FRAMES := 1800
const SEEDED_ENDURANCE_FRAMES := 9000
const NIGHTLY_ENDURANCE_FRAMES := 36000
const DEFAULT_CHUNK_SIZE_FRAMES := 600
const DEFAULT_WARMUP_FRAMES := 120
const DEFAULT_CLEANUP_FRAMES := 180


static func get_default_frames(profile_name: StringName) -> int:
	match profile_name:
		SMOKE:
			return SMOKE_FRAMES
		EXTENDED_SMOKE:
			return EXTENDED_SMOKE_FRAMES
		SEEDED_ENDURANCE:
			return SEEDED_ENDURANCE_FRAMES
		NIGHTLY_ENDURANCE:
			return NIGHTLY_ENDURANCE_FRAMES
	return 0


static func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var values := [
		SMOKE_FRAMES,
		EXTENDED_SMOKE_FRAMES,
		SEEDED_ENDURANCE_FRAMES,
		NIGHTLY_ENDURANCE_FRAMES,
	]
	var seen: Dictionary = {}
	for frame_count in values:
		if frame_count <= 0:
			errors.append("Endurance frame counts must be positive.")
		if seen.has(frame_count):
			errors.append(
				"Endurance profiles must not share the same frame count."
			)
		seen[frame_count] = true
	if DEFAULT_CHUNK_SIZE_FRAMES <= 0:
		errors.append("Endurance chunk size must be positive.")
	return errors

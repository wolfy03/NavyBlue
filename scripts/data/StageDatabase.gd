extends RefCounted
class_name StageDatabase

const DEFAULT_STAGE_ID := "test_level"
const STAGE_PATHS := {
	"test_level": "res://resources/stages/test_level.tres",
}

var warn_on_fallback := true

func get_stage(stage_id: String) -> StageData:
	var resolved_id := stage_id if STAGE_PATHS.has(stage_id) else DEFAULT_STAGE_ID
	if resolved_id != stage_id and warn_on_fallback:
		push_warning("Unknown stage id '%s'. Falling back to %s." % [stage_id, DEFAULT_STAGE_ID])
	var path := str(STAGE_PATHS[resolved_id])
	var data := load(path) as StageData
	if data != null:
		return data
	push_warning("Failed to load stage data: %s" % path)
	if resolved_id != DEFAULT_STAGE_ID:
		return load(str(STAGE_PATHS[DEFAULT_STAGE_ID])) as StageData
	var fallback := StageData.new()
	fallback.id = DEFAULT_STAGE_ID
	return fallback

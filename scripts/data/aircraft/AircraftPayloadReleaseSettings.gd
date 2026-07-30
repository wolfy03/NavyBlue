extends Resource
class_name AircraftPayloadReleaseSettings

@export var request_timeout_sec := 2.0
@export var retry_interval_sec := 0.05
@export_range(0, 20, 1) var maximum_additional_retries := 3
@export var completion_wait_sec := 0.5


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if request_timeout_sec < 0.0:
		errors.append("request_timeout_sec must not be negative.")
	if retry_interval_sec < 0.0:
		errors.append("retry_interval_sec must not be negative.")
	if completion_wait_sec < 0.0:
		errors.append("completion_wait_sec must not be negative.")
	return errors

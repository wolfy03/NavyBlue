extends RefCounted
class_name AircraftPayloadReleaseCoordinator

signal aircraft_release_finished(
	aircraft_id: int,
	aircraft: AircraftUnit,
	success: bool,
	cancelled: bool,
	reason: int
)
signal pass_finished(result: AircraftPayloadReleasePassResult)

var owner_squadron: AircraftSquadron
var settings: AircraftPayloadReleaseSettings

var _active_requests: Dictionary = {}
var _last_aircraft_results: Dictionary = {}
var _pass_active := false
var _active_requested_count := 0
var _active_completed_count := 0
var _active_failed_count := 0
var _active_cancelled_count := 0
var _last_result := AircraftPayloadReleasePassResult.new()


func setup(
		squadron: AircraftSquadron,
		next_settings: AircraftPayloadReleaseSettings
) -> void:
	cancel_all_requests()
	owner_squadron = squadron
	settings = next_settings
	_last_aircraft_results.clear()
	_last_result = AircraftPayloadReleasePassResult.new()


func register_aircraft(aircraft: AircraftUnit) -> void:
	if aircraft == null or aircraft.weapon_controller == null:
		return
	var weapon := aircraft.weapon_controller
	if not weapon.payload_release_completed.is_connected(
		_on_payload_release_completed
	):
		weapon.payload_release_completed.connect(
			_on_payload_release_completed
		)
	if not weapon.payload_release_failed.is_connected(
		_on_payload_release_failed
	):
		weapon.payload_release_failed.connect(
			_on_payload_release_failed
		)
	if not weapon.payload_release_cancelled.is_connected(
		_on_payload_release_cancelled
	):
		weapon.payload_release_cancelled.connect(
			_on_payload_release_cancelled
		)


func unregister_aircraft(aircraft_id: int) -> void:
	cancel_aircraft_requests(aircraft_id)


func request_release(
		aircraft: AircraftUnit,
		context: AircraftPayloadReleaseContext
) -> AircraftPayloadReleaseRequestResult:
	if aircraft == null or not is_instance_valid(aircraft) \
			or not aircraft.is_alive():
		return AircraftPayloadReleaseRequestResult.create(
			AircraftPayloadReleaseRequestResult.Status.INVALID_AIRCRAFT
		)
	var aircraft_id := aircraft.get_instance_id()
	if _has_active_request_for_aircraft(aircraft_id):
		return AircraftPayloadReleaseRequestResult.create(
			AircraftPayloadReleaseRequestResult.Status.ALREADY_PENDING,
			aircraft_id
		)
	var previous: Dictionary = _last_aircraft_results.get(
		aircraft_id,
		{}
	)
	if bool(previous.get("success", false)):
		return AircraftPayloadReleaseRequestResult.create(
			AircraftPayloadReleaseRequestResult.Status.ALREADY_RELEASED,
			aircraft_id
		)
	var weapon := aircraft.weapon_controller
	if weapon == null:
		return AircraftPayloadReleaseRequestResult.create(
			AircraftPayloadReleaseRequestResult.Status.NO_WEAPON_CONTROLLER,
			aircraft_id
		)
	if not weapon.has_ammunition():
		return AircraftPayloadReleaseRequestResult.create(
			AircraftPayloadReleaseRequestResult.Status.NO_AMMUNITION,
			aircraft_id
		)
	if not weapon.is_release_enabled():
		return AircraftPayloadReleaseRequestResult.create(
			AircraftPayloadReleaseRequestResult.Status.WEAPON_DISABLED,
			aircraft_id
		)
	if not weapon.can_release():
		return AircraftPayloadReleaseRequestResult.create(
			AircraftPayloadReleaseRequestResult.Status.RETRYABLE
				if weapon.can_retry_payload_release()
				else AircraftPayloadReleaseRequestResult.Status.WEAPON_DISABLED,
			aircraft_id
		)
	var request_id := weapon.request_release(
		context.target_position,
		context.target_velocity
	)
	if request_id < 0:
		return AircraftPayloadReleaseRequestResult.create(
			AircraftPayloadReleaseRequestResult.Status.RETRYABLE,
			aircraft_id
		)
	_active_requests[request_id] = {
		"aircraft_ref": weakref(aircraft),
		"aircraft_id": aircraft_id,
		"elapsed_sec": 0.0,
	}
	_active_requested_count += 1
	return AircraftPayloadReleaseRequestResult.create(
		AircraftPayloadReleaseRequestResult.Status.QUEUED,
		aircraft_id,
		request_id
	)


func update(delta: float) -> void:
	var step := maxf(delta, 0.0)
	for aircraft in owner_squadron.get_alive_aircraft() \
			if owner_squadron != null else []:
		if aircraft.weapon_controller != null:
			aircraft.weapon_controller.update_weapon(step)
	if _active_requests.is_empty():
		return
	var timeout := settings.request_timeout_sec \
		if settings != null else 2.0
	if timeout <= 0.0:
		return
	var timed_out: Array[int] = []
	for request_value in _active_requests.keys():
		var request_id := int(request_value)
		var data: Dictionary = _active_requests.get(request_id, {})
		data["elapsed_sec"] = float(data.get("elapsed_sec", 0.0)) + step
		_active_requests[request_id] = data
		if float(data["elapsed_sec"]) >= timeout:
			timed_out.append(request_id)
	for request_id in timed_out:
		_cancel_request_by_id(
			request_id,
			AircraftWeaponController.ReleaseFailureReason.CANCELLED
		)


func begin_pass() -> void:
	_active_requested_count = 0
	_active_completed_count = 0
	_active_failed_count = 0
	_active_cancelled_count = 0
	_last_aircraft_results.clear()
	_pass_active = true


func finish_pass(
		policy_failed_count: int,
		skipped_count: int,
		cancelled: bool
) -> AircraftPayloadReleasePassResult:
	if not _pass_active:
		return _last_result
	_pass_active = false
	var result := AircraftPayloadReleasePassResult.new()
	result.requested_count = _active_requested_count
	result.released_count = _active_completed_count
	result.failed_count = maxi(
		_active_failed_count,
		policy_failed_count
	)
	result.skipped_count = maxi(skipped_count, 0)
	result.cancelled_count = _active_cancelled_count
	result.cancelled = cancelled or result.cancelled_count > 0
	_last_result = result
	_active_requested_count = 0
	_active_completed_count = 0
	_active_failed_count = 0
	_active_cancelled_count = 0
	pass_finished.emit(result)
	return result


func cancel_aircraft_requests(aircraft_id: int) -> void:
	var request_ids: Array[int] = []
	for request_value in _active_requests.keys():
		var request_id := int(request_value)
		var data: Dictionary = _active_requests.get(request_id, {})
		if int(data.get("aircraft_id", 0)) == aircraft_id:
			request_ids.append(request_id)
	for request_id in request_ids:
		_cancel_request_by_id(
			request_id,
			AircraftWeaponController.ReleaseFailureReason.CANCELLED
		)


func cancel_all_requests() -> void:
	var request_ids: Array[int] = []
	for request_value in _active_requests.keys():
		request_ids.append(int(request_value))
	for request_id in request_ids:
		_cancel_request_by_id(
			request_id,
			AircraftWeaponController.ReleaseFailureReason.CANCELLED
		)


func is_release_in_progress() -> bool:
	if not _active_requests.is_empty():
		return true
	if owner_squadron == null:
		return false
	for aircraft in owner_squadron.get_alive_aircraft():
		if aircraft.weapon_controller != null \
				and aircraft.weapon_controller.is_release_in_progress():
			return true
	return false


func is_pass_active() -> bool:
	return _pass_active


func get_last_result() -> AircraftPayloadReleasePassResult:
	return _last_result


func get_last_aircraft_result(aircraft_id: int) -> Dictionary:
	var value: Variant = _last_aircraft_results.get(aircraft_id, {})
	return (value as Dictionary).duplicate(true) \
		if value is Dictionary else {}


func get_active_requested_count() -> int:
	return _active_requested_count


func get_active_completed_count() -> int:
	return _active_completed_count


func get_debug_snapshot() -> Dictionary:
	var requests := {}
	for request_value in _active_requests.keys():
		var request_id := int(request_value)
		var data: Dictionary = _active_requests.get(request_id, {})
		requests[request_id] = {
			"aircraft_id": int(data.get("aircraft_id", 0)),
			"elapsed_sec": float(data.get("elapsed_sec", 0.0)),
		}
	return {
		"active_request_ids": _active_requests.keys(),
		"active_requests": requests,
		"last_release_result": _last_result.to_dictionary(),
	}


func _has_active_request_for_aircraft(aircraft_id: int) -> bool:
	for value in _active_requests.values():
		var data := value as Dictionary
		if int(data.get("aircraft_id", 0)) == aircraft_id:
			return true
	return false


func _on_payload_release_completed(
		aircraft: AircraftUnit,
		request_id: int,
		_projectile: Node3D
) -> void:
	_finish_request(
		aircraft,
		request_id,
		true,
		false,
		AircraftWeaponController.ReleaseFailureReason.NONE
	)


func _on_payload_release_failed(
		aircraft: AircraftUnit,
		request_id: int,
		reason: int
) -> void:
	_finish_request(aircraft, request_id, false, false, reason)


func _on_payload_release_cancelled(
		aircraft: AircraftUnit,
		request_id: int
) -> void:
	_finish_request(
		aircraft,
		request_id,
		false,
		true,
		AircraftWeaponController.ReleaseFailureReason.CANCELLED
	)


func _finish_request(
		aircraft: AircraftUnit,
		request_id: int,
		success: bool,
		cancelled: bool,
		reason: int
) -> void:
	if not _active_requests.has(request_id):
		return
	var data: Dictionary = _active_requests.get(request_id, {})
	var aircraft_id := int(data.get("aircraft_id", 0))
	if aircraft == null:
		var aircraft_ref := data.get("aircraft_ref") as WeakRef
		if aircraft_ref != null:
			aircraft = aircraft_ref.get_ref() as AircraftUnit
	_active_requests.erase(request_id)
	if success:
		_active_completed_count += 1
	else:
		_active_failed_count += 1
		if cancelled:
			_active_cancelled_count += 1
	_last_aircraft_results[aircraft_id] = {
		"success": success,
		"cancelled": cancelled,
		"request_id": request_id,
		"reason": reason,
	}
	aircraft_release_finished.emit(
		aircraft_id,
		aircraft,
		success,
		cancelled,
		reason
	)


func _cancel_request_by_id(request_id: int, reason: int) -> void:
	if not _active_requests.has(request_id):
		return
	var data: Dictionary = _active_requests.get(request_id, {})
	var aircraft_ref := data.get("aircraft_ref") as WeakRef
	var aircraft := aircraft_ref.get_ref() as AircraftUnit \
		if aircraft_ref != null else null
	var cancellation_requested := false
	if aircraft != null and is_instance_valid(aircraft) \
			and aircraft.weapon_controller != null:
		cancellation_requested = aircraft.weapon_controller \
			.cancel_release_request(request_id)
	if not cancellation_requested and _active_requests.has(request_id):
		_finish_request(
			aircraft,
			request_id,
			false,
			true,
			reason
		)

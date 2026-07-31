extends Node
class_name TorpedoAttackTargetingSession

signal targeting_started
signal preview_changed(preview: TorpedoAttackPreview)
signal drag_started(entry_point: Vector3)
signal targeting_completed(commands: Array[TorpedoAttackCommand])
signal targeting_cancelled(reason: StringName)

enum State {
	INACTIVE,
	ARMED,
	DRAGGING,
}

var state: State = State.INACTIVE
var _world_pointer: WorldPointerResolver
var _battle_environment: BattleEnvironment
var _resolver := TorpedoAttackCommandResolver.new()
var _profile: TorpedoAttackProfile
var _squadron_refs: Array[WeakRef] = []
var _squadron_callbacks: Dictionary = {}
var _entry_point := Vector3.ZERO
var _cursor_point := Vector3.ZERO
var _current_preview: TorpedoAttackPreview


func _ready() -> void:
	set_process(false)


func setup(
		world_pointer: WorldPointerResolver,
		battle_environment: BattleEnvironment
) -> void:
	shutdown()
	_world_pointer = world_pointer
	_battle_environment = battle_environment


func shutdown() -> void:
	if is_active():
		cancel(&"shutdown")
	_disconnect_squadron_callbacks()
	_world_pointer = null
	_battle_environment = null
	_profile = null
	_resolver = TorpedoAttackCommandResolver.new()
	_current_preview = null
	state = State.INACTIVE
	set_process(false)


func validate_begin(
		squadrons: Array[AircraftSquadron]
) -> TorpedoTargetingValidationResult:
	if squadrons.is_empty():
		return TorpedoTargetingValidationResult.rejected(&"no_selection")
	var shared_profile: TorpedoAttackProfile
	for squadron in squadrons:
		if squadron == null or not is_instance_valid(squadron):
			return TorpedoTargetingValidationResult.rejected(&"invalid_squadron")
		if squadron.get_aircraft_role() \
				!= AircraftData.AircraftRole.TORPEDO_BOMBER:
			return TorpedoTargetingValidationResult.rejected(&"mixed_roles")
		if not squadron.can_begin_manual_torpedo_attack():
			return TorpedoTargetingValidationResult.rejected(
				&"torpedo_attack_unavailable"
			)
		var profile := squadron.get_torpedo_attack_profile()
		if profile == null or not profile.validate().is_empty():
			return TorpedoTargetingValidationResult.rejected(&"invalid_profile")
		if shared_profile == null:
			shared_profile = profile
		elif not is_equal_approx(
			shared_profile.minimum_attack_run_distance_m,
			profile.minimum_attack_run_distance_m
		):
			return TorpedoTargetingValidationResult.rejected(
				&"incompatible_profiles"
			)
	return TorpedoTargetingValidationResult.accepted(shared_profile)


func begin(
		squadrons: Array[AircraftSquadron],
		initial_cursor_point: Vector3
) -> bool:
	if is_active():
		return false
	var validation := validate_begin(squadrons)
	if not validation.valid:
		return false
	_profile = validation.profile
	_squadron_refs.clear()
	for squadron in squadrons:
		_squadron_refs.append(weakref(squadron))
		_connect_squadron_callbacks(squadron)
	_entry_point = _on_command_plane(initial_cursor_point)
	_cursor_point = _entry_point
	state = State.ARMED
	set_process(true)
	targeting_started.emit()
	_refresh_preview()
	return true


func update_armed_cursor(world_point: Vector3) -> void:
	if state != State.ARMED:
		return
	_entry_point = _on_command_plane(world_point)
	_cursor_point = _entry_point
	_refresh_preview()


func begin_drag(world_point: Vector3) -> void:
	if state != State.ARMED:
		return
	_entry_point = _on_command_plane(world_point)
	_cursor_point = _entry_point
	state = State.DRAGGING
	drag_started.emit(_entry_point)
	_refresh_preview()


func update_drag(world_point: Vector3) -> void:
	if state != State.DRAGGING:
		return
	_cursor_point = _on_command_plane(world_point)
	_refresh_preview()


func resolve_drag_commands(
		world_point: Vector3,
		target_ship: ShipUnit = null
) -> Array[TorpedoAttackCommand]:
	# Builds the per-squadron commands without finalizing the session. On any
	# resolve failure the session falls back to ARMED (invalid preview shown)
	# so the player can re-drag; the caller receives an empty array. On success
	# the session stays DRAGGING and the caller must call confirm_completed()
	# once it has verified every squadron can apply its command atomically.
	var commands: Array[TorpedoAttackCommand] = []
	if state != State.DRAGGING:
		return commands
	_cursor_point = _on_command_plane(world_point)
	var squadrons := get_active_squadrons()
	if squadrons.is_empty():
		cancel(&"squadron_unavailable")
		return commands
	var base_result := _resolver.resolve(
		squadrons[0],
		_entry_point,
		_cursor_point,
		_profile,
		_battle_environment,
		target_ship
	)
	if not base_result.success:
		_return_to_armed(base_result.failure_reason)
		return commands
	for index in squadrons.size():
		var centered_index := float(index) \
			- float(squadrons.size() - 1) * 0.5
		var offset_result := _resolver.apply_lateral_offset(
			base_result.command,
			centered_index,
			_profile,
			_battle_environment
		)
		if not offset_result.success:
			commands.clear()
			_return_to_armed(offset_result.failure_reason)
			return commands
		offset_result.command.target_ship = target_ship \
			if target_ship != null and is_instance_valid(target_ship) else null
		commands.append(offset_result.command)
	return commands


func confirm_completed(commands: Array[TorpedoAttackCommand]) -> void:
	if state != State.DRAGGING:
		return
	state = State.INACTIVE
	set_process(false)
	_disconnect_squadron_callbacks()
	_squadron_refs.clear()
	_current_preview = null
	_profile = null
	targeting_completed.emit(commands)


func return_to_armed(reason: StringName) -> void:
	_return_to_armed(reason)


func complete_drag(
		world_point: Vector3,
		target_ship: ShipUnit = null
) -> Array[TorpedoAttackCommand]:
	var commands := resolve_drag_commands(world_point, target_ship)
	if not commands.is_empty():
		confirm_completed(commands)
	return commands


func cancel(reason: StringName) -> void:
	if not is_active():
		return
	state = State.INACTIVE
	set_process(false)
	_disconnect_squadron_callbacks()
	_squadron_refs.clear()
	_current_preview = null
	_profile = null
	targeting_cancelled.emit(reason)


func _return_to_armed(_reason: StringName) -> void:
	# A failed release keeps the session alive: end the drag, revert to ARMED,
	# and refresh the (now invalid) preview so the player can drag again. The
	# active mission is untouched and only right-click / ESC fully cancels.
	if state == State.INACTIVE:
		return
	state = State.ARMED
	set_process(true)
	_refresh_preview()


func is_active() -> bool:
	return state != State.INACTIVE


func is_dragging() -> bool:
	return state == State.DRAGGING


func get_current_preview() -> TorpedoAttackPreview:
	return _current_preview


func get_active_squadrons() -> Array[AircraftSquadron]:
	var result: Array[AircraftSquadron] = []
	for squadron_ref in _squadron_refs:
		var squadron := squadron_ref.get_ref() as AircraftSquadron
		if squadron != null and is_instance_valid(squadron) \
				and not squadron.is_queued_for_deletion():
			result.append(squadron)
	return result


func _process(_delta: float) -> void:
	if is_active() and get_active_squadrons().size() != _squadron_refs.size():
		cancel(&"squadron_unavailable")


func _refresh_preview() -> void:
	var squadrons := get_active_squadrons()
	if squadrons.is_empty() or _profile == null:
		cancel(&"squadron_unavailable")
		return
	_current_preview = _resolver.build_preview(
		squadrons[0],
		_entry_point,
		_cursor_point,
		_profile,
		_battle_environment,
		state == State.DRAGGING
	)
	preview_changed.emit(_current_preview)


func _on_command_plane(point: Vector3) -> Vector3:
	var result := point
	result.y = _battle_environment.sea_level_m \
		if _battle_environment != null else point.y
	return result


func _connect_squadron_callbacks(squadron: AircraftSquadron) -> void:
	var id := squadron.get_instance_id()
	var tree_callback := Callable(self, "_on_squadron_cancel_event").bind(
		&"squadron_removed"
	)
	var return_callback := Callable(self, "_on_squadron_cancel_event").bind(
		&"return_requested"
	)
	var lost_callback := Callable(self, "_on_squadron_cancel_event").bind(
		&"squadron_destroyed"
	)
	_squadron_callbacks[id] = {
		"squadron_ref": weakref(squadron),
		"tree": tree_callback,
		"return": return_callback,
		"lost": lost_callback,
	}
	if not squadron.tree_exiting.is_connected(tree_callback):
		squadron.tree_exiting.connect(tree_callback, CONNECT_ONE_SHOT)
	if not squadron.return_requested.is_connected(return_callback):
		squadron.return_requested.connect(return_callback)
	if not squadron.squadron_lost.is_connected(lost_callback):
		squadron.squadron_lost.connect(lost_callback)


func _disconnect_squadron_callbacks() -> void:
	for value in _squadron_callbacks.values():
		var data := value as Dictionary
		var squadron_ref := data.get("squadron_ref") as WeakRef
		var squadron := squadron_ref.get_ref() as AircraftSquadron \
			if squadron_ref != null else null
		if squadron == null or not is_instance_valid(squadron):
			continue
		_disconnect_if_connected(squadron.tree_exiting, data.get("tree") as Callable)
		_disconnect_if_connected(
			squadron.return_requested,
			data.get("return") as Callable
		)
		_disconnect_if_connected(squadron.squadron_lost, data.get("lost") as Callable)
	_squadron_callbacks.clear()


func _disconnect_if_connected(signal_value: Signal, callback: Callable) -> void:
	if callback.is_valid() and signal_value.is_connected(callback):
		signal_value.disconnect(callback)


func _on_squadron_cancel_event(_value = null, reason: StringName = &"squadron_unavailable") -> void:
	cancel(reason)

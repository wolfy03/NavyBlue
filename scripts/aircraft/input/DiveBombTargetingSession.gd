extends Node
class_name DiveBombTargetingSession

# Player dive-bomb targeting. Pressing the special-action key arms the session;
# the cursor drives a circular accuracy preview and a left click confirms the
# bomb point. Simpler than the torpedo session: there is no drag, only ARMED and
# a single confirm.

signal targeting_started
signal preview_changed(preview: DiveBombPreview)
signal targeting_completed(commands: Array[DiveBombCommand])
signal targeting_cancelled(reason: StringName)

enum State {
	INACTIVE,
	ARMED,
}

var state: State = State.INACTIVE
var _battle_environment: BattleEnvironment
var _accuracy_resolver := DiveBombAccuracyResolver.new()
var _squadron_refs: Array[WeakRef] = []
var _squadron_callbacks: Dictionary = {}
var _cursor_point := Vector3.ZERO
var _current_preview: DiveBombPreview
static var _next_command_id := 1


func _ready() -> void:
	set_process(false)


func setup(battle_environment: BattleEnvironment) -> void:
	shutdown()
	_battle_environment = battle_environment


func shutdown() -> void:
	if is_active():
		cancel(&"shutdown")
	_disconnect_squadron_callbacks()
	_battle_environment = null
	_current_preview = null
	state = State.INACTIVE
	set_process(false)


func begin(
		squadrons: Array[AircraftSquadron],
		initial_cursor_point: Vector3
) -> bool:
	if is_active() or squadrons.is_empty():
		return false
	for squadron in squadrons:
		if squadron == null or not is_instance_valid(squadron):
			return false
		if squadron.get_aircraft_role() \
				!= AircraftData.AircraftRole.DIVE_BOMBER:
			return false
		if not squadron.can_begin_manual_dive():
			return false
	_squadron_refs.clear()
	for squadron in squadrons:
		_squadron_refs.append(weakref(squadron))
		_connect_squadron_callbacks(squadron)
	_cursor_point = _on_ground_plane(initial_cursor_point)
	state = State.ARMED
	set_process(true)
	targeting_started.emit()
	_refresh_preview()
	return true


func update_cursor(world_point: Vector3) -> void:
	if state != State.ARMED:
		return
	_cursor_point = _on_ground_plane(world_point)
	_refresh_preview()


func confirm(world_point: Vector3) -> Array[DiveBombCommand]:
	var commands: Array[DiveBombCommand] = []
	if state != State.ARMED:
		return commands
	_cursor_point = _on_ground_plane(world_point)
	var squadrons := get_active_squadrons()
	if squadrons.is_empty():
		cancel(&"squadron_unavailable")
		return commands
	for squadron in squadrons:
		var command := DiveBombCommand.new()
		command.command_id = _allocate_command_id()
		command.target_point = _cursor_point
		command.target_velocity = Vector3.ZERO
		command.dispersion_radius_m = _resolve_radius_for(squadron)
		commands.append(command)
	state = State.INACTIVE
	set_process(false)
	_disconnect_squadron_callbacks()
	_squadron_refs.clear()
	_current_preview = null
	targeting_completed.emit(commands)
	return commands


func cancel(reason: StringName) -> void:
	if not is_active():
		return
	state = State.INACTIVE
	set_process(false)
	_disconnect_squadron_callbacks()
	_squadron_refs.clear()
	_current_preview = null
	targeting_cancelled.emit(reason)


func is_active() -> bool:
	return state != State.INACTIVE


func get_current_preview() -> DiveBombPreview:
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
	if is_active() \
			and get_active_squadrons().size() != _squadron_refs.size():
		cancel(&"squadron_unavailable")


func _refresh_preview() -> void:
	var squadrons := get_active_squadrons()
	if squadrons.is_empty():
		cancel(&"squadron_unavailable")
		return
	var preview := DiveBombPreview.new()
	preview.target_point = _cursor_point
	preview.dispersion_radius_m = _resolve_radius_for(squadrons[0])
	preview.valid = true
	_current_preview = preview
	preview_changed.emit(preview)


func _resolve_radius_for(squadron: AircraftSquadron) -> float:
	return _accuracy_resolver.resolve_dispersion_radius_m(
		squadron.get_dive_bomber_combat_data(),
		squadron.get_alive_aircraft_count()
	)


func _on_ground_plane(point: Vector3) -> Vector3:
	var result := point
	result.y = _battle_environment.sea_level_m \
		if _battle_environment != null else point.y
	return result


func _connect_squadron_callbacks(squadron: AircraftSquadron) -> void:
	var id := squadron.get_instance_id()
	# tree_exiting emits zero arguments, so a bound reason would land in the
	# first parameter and be discarded. Use a dedicated zero-arg handler.
	var tree_callback := Callable(self, "_on_squadron_tree_exiting")
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
		_disconnect_if_connected(
			squadron.tree_exiting,
			data.get("tree") as Callable
		)
		_disconnect_if_connected(
			squadron.return_requested,
			data.get("return") as Callable
		)
		_disconnect_if_connected(
			squadron.squadron_lost,
			data.get("lost") as Callable
		)
	_squadron_callbacks.clear()


func _disconnect_if_connected(signal_value: Signal, callback: Callable) -> void:
	if callback.is_valid() and signal_value.is_connected(callback):
		signal_value.disconnect(callback)


func _on_squadron_cancel_event(
		_value = null,
		reason: StringName = &"squadron_unavailable"
) -> void:
	cancel(reason)


func _on_squadron_tree_exiting() -> void:
	cancel(&"squadron_removed")


func _allocate_command_id() -> int:
	var command_id := _next_command_id
	_next_command_id += 1
	if _next_command_id <= 0:
		_next_command_id = 1
	return command_id

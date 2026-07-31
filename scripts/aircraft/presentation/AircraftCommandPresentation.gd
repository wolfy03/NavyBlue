extends Node
class_name AircraftCommandPresentation

const DEFAULT_SETTINGS: AircraftCommandPresentationSettings = preload(
	"res://resources/settings/default_aircraft_command_presentation.tres"
)

@export var settings: AircraftCommandPresentationSettings = DEFAULT_SETTINGS
@export var selection_box_scene: PackedScene
@export var command_path_scene: PackedScene
@export var status_overlay_scene: PackedScene

@onready var selection_box_root: Node3D = %SelectionBoxRoot
@onready var command_path_root: Node3D = %CommandPathRoot
@onready var status_overlay_root: Control = %StatusOverlayRoot

var _selection_controller: AircraftSelectionController
var _camera: Camera3D
var _battle_environment: BattleEnvironment
var _frame_builder := SquadronPresentationFrameBuilder.new()
var _selected_squadrons: Dictionary = {}
var _bindings: Dictionary = {}
var _active_boxes: Dictionary = {}
var _active_paths: Dictionary = {}
var _active_overlays: Dictionary = {}
var _last_frames: Dictionary = {}
var _available_boxes: Array[SquadronSelectionBox] = []
var _available_paths: Array[SquadronCommandPathPresenter] = []
var _available_overlays: Array[SquadronStatusOverlay] = []
var _bounds_refresh_left := 0.0
var _status_refresh_left := 0.0
var _bounds_refresh_count := 0
var _snapshot_build_count := 0


func _ready() -> void:
	add_to_group(&"aircraft_command_presentations")
	set_process(false)


func setup(
		selection_controller: AircraftSelectionController,
		camera: Camera3D,
		environment: BattleEnvironment
) -> void:
	shutdown()
	_selection_controller = selection_controller
	_camera = camera
	_battle_environment = environment
	if _selection_controller != null \
			and not _selection_controller.selection_changed.is_connected(
				set_selected_squadrons
			):
		_selection_controller.selection_changed.connect(
			set_selected_squadrons
		)
	set_process(true)
	if _selection_controller != null:
		set_selected_squadrons(
			_selection_controller.get_selected_squadrons()
		)


func shutdown() -> void:
	set_process(false)
	if _selection_controller != null \
			and _selection_controller.selection_changed.is_connected(
				set_selected_squadrons
			):
		_selection_controller.selection_changed.disconnect(
			set_selected_squadrons
		)
	for id_value in _selected_squadrons.keys():
		_release_presenters(int(id_value))
	_selected_squadrons.clear()
	_bindings.clear()
	_last_frames.clear()
	_selection_controller = null
	_camera = null
	_battle_environment = null
	_clear_local_pools()


func set_selected_squadrons(
		squadrons: Array[AircraftSquadron]
) -> void:
	var next_ids: Dictionary = {}
	for squadron in squadrons:
		if squadron == null or not is_instance_valid(squadron):
			continue
		var squadron_id := squadron.get_instance_id()
		next_ids[squadron_id] = true
		if not _selected_squadrons.has(squadron_id):
			_selected_squadrons[squadron_id] = weakref(squadron)
			_connect_squadron_binding(squadron)
			var box := _acquire_box()
			box.activate(squadron)
			_active_boxes[squadron_id] = box
			var path := _acquire_path()
			path.activate(squadron)
			_active_paths[squadron_id] = path
			var overlay := _acquire_overlay()
			overlay.activate(squadron)
			_active_overlays[squadron_id] = overlay
			_refresh_frame(squadron_id, squadron, true)
	for id_value in _selected_squadrons.keys():
		var squadron_id := int(id_value)
		if not next_ids.has(squadron_id):
			_release_presenters(squadron_id)
	_bounds_refresh_left = 0.0
	_status_refresh_left = 0.0


func _process(delta: float) -> void:
	_bounds_refresh_left = maxf(
		_bounds_refresh_left - maxf(delta, 0.0),
		0.0
	)
	_status_refresh_left = maxf(
		_status_refresh_left - maxf(delta, 0.0),
		0.0
	)
	var refresh_bounds := _bounds_refresh_left <= 0.0
	var refresh_status := _status_refresh_left <= 0.0
	if refresh_bounds:
		_bounds_refresh_left = maxf(
			settings.bounds_refresh_interval_sec,
			0.05
		)
	if refresh_status:
		_status_refresh_left = maxf(
			settings.status_refresh_interval_sec,
			0.05
		)
	for id_value in _selected_squadrons.keys():
		var squadron_id := int(id_value)
		var squadron := _get_squadron(squadron_id)
		if squadron == null or _is_terminal_state(squadron):
			_release_presenters(squadron_id)
			continue
		if refresh_bounds:
			_refresh_frame(
				squadron_id,
				squadron,
				refresh_status
			)
		elif refresh_status:
			var frame := _last_frames.get(squadron_id) \
				as SquadronPresentationFrame
			if frame != null:
				_apply_overlay_snapshot(squadron_id, frame)
		_refresh_overlay_position(squadron_id)


func _refresh_frame(
		squadron_id: int,
		squadron: AircraftSquadron,
		refresh_status: bool
) -> void:
	var frame := _frame_builder.build(squadron, settings)
	_last_frames[squadron_id] = frame
	_bounds_refresh_count += 1
	_snapshot_build_count += 1
	var box := _active_boxes.get(squadron_id) \
		as SquadronSelectionBox
	if box != null:
		box.set_bounds(
			frame.bounds,
			maxf(settings.bounds_refresh_interval_sec, 0.05)
		)
		box.set_visible_state(true)
	_apply_path(squadron_id, squadron, frame.destination)
	if refresh_status:
		_apply_overlay_snapshot(squadron_id, frame)


func _apply_path(
		squadron_id: int,
		squadron: AircraftSquadron,
		destination: SquadronDestinationSnapshot
) -> void:
	var path := _active_paths.get(squadron_id) \
		as SquadronCommandPathPresenter
	if path == null:
		return
	if path.should_show_path(squadron, destination):
		path.update_path(
			squadron.formation_center,
			destination.destination,
			destination.command_plane_height_m
		)
	else:
		path.hide_path()


func _apply_overlay_snapshot(
		squadron_id: int,
		frame: SquadronPresentationFrame
) -> void:
	var overlay := _active_overlays.get(squadron_id) \
		as SquadronStatusOverlay
	if overlay != null:
		overlay.set_snapshot(frame.snapshot)


func _refresh_overlay_position(squadron_id: int) -> void:
	var overlay := _active_overlays.get(squadron_id) \
		as SquadronStatusOverlay
	var frame := _last_frames.get(squadron_id) \
		as SquadronPresentationFrame
	if overlay == null or frame == null:
		return
	overlay.set_screen_bounds(
		_camera,
		frame.bounds,
		settings.status_offset_pixels
	)


func _connect_squadron_binding(
		squadron: AircraftSquadron
) -> void:
	var squadron_id := squadron.get_instance_id()
	_disconnect_squadron_binding(squadron_id)
	var binding := SquadronPresentationBinding.new()
	binding.squadron_ref = weakref(squadron)
	binding.destination_changed_callback = Callable(
		self,
		"_on_destination_changed"
	).bind(squadron_id)
	binding.destination_reached_callback = Callable(
		self,
		"_on_destination_reached"
	).bind(squadron_id)
	binding.selection_changed_callback = Callable(
		self,
		"_on_player_selection_changed"
	).bind(squadron_id)
	binding.return_requested_callback = Callable(
		self,
		"_on_squadron_finished"
	).bind(squadron_id)
	binding.recovery_completed_callback = Callable(
		self,
		"_on_squadron_finished"
	).bind(squadron_id)
	binding.squadron_lost_callback = Callable(
		self,
		"_on_squadron_finished"
	).bind(squadron_id)
	binding.tree_exiting_callback = Callable(
		self,
		"_on_squadron_tree_exiting"
	).bind(squadron_id)
	_connect_if_needed(
		squadron.player_destination_changed,
		binding.destination_changed_callback
	)
	_connect_if_needed(
		squadron.player_destination_reached,
		binding.destination_reached_callback
	)
	_connect_if_needed(
		squadron.player_selection_changed,
		binding.selection_changed_callback
	)
	_connect_if_needed(
		squadron.return_requested,
		binding.return_requested_callback
	)
	_connect_if_needed(
		squadron.recovery_completed,
		binding.recovery_completed_callback
	)
	_connect_if_needed(
		squadron.squadron_lost,
		binding.squadron_lost_callback
	)
	_connect_if_needed(
		squadron.tree_exiting,
		binding.tree_exiting_callback,
		CONNECT_ONE_SHOT
	)
	_bindings[squadron_id] = binding


func _disconnect_squadron_binding(squadron_id: int) -> void:
	var binding := _bindings.get(squadron_id) \
		as SquadronPresentationBinding
	if binding == null:
		return
	var squadron := binding.get_squadron()
	if squadron != null:
		_disconnect_if_needed(
			squadron.player_destination_changed,
			binding.destination_changed_callback
		)
		_disconnect_if_needed(
			squadron.player_destination_reached,
			binding.destination_reached_callback
		)
		_disconnect_if_needed(
			squadron.player_selection_changed,
			binding.selection_changed_callback
		)
		_disconnect_if_needed(
			squadron.return_requested,
			binding.return_requested_callback
		)
		_disconnect_if_needed(
			squadron.recovery_completed,
			binding.recovery_completed_callback
		)
		_disconnect_if_needed(
			squadron.squadron_lost,
			binding.squadron_lost_callback
		)
		_disconnect_if_needed(
			squadron.tree_exiting,
			binding.tree_exiting_callback
		)
	binding.clear()
	_bindings.erase(squadron_id)


func _connect_if_needed(
		signal_value: Signal,
		callback: Callable,
		flags: int = 0
) -> void:
	if callback.is_valid() and not signal_value.is_connected(callback):
		signal_value.connect(callback, flags)


func _disconnect_if_needed(
		signal_value: Signal,
		callback: Callable
) -> void:
	if callback.is_valid() and signal_value.is_connected(callback):
		signal_value.disconnect(callback)


func _on_destination_changed(
		snapshot: SquadronDestinationSnapshot,
		squadron_id: int
) -> void:
	var squadron := _get_squadron(squadron_id)
	if squadron == null:
		_release_presenters(squadron_id)
		return
	var frame := _last_frames.get(squadron_id) \
		as SquadronPresentationFrame
	if frame == null:
		_refresh_frame(squadron_id, squadron, true)
		return
	frame.destination = snapshot
	_apply_path(squadron_id, squadron, snapshot)


func _on_destination_reached(squadron_id: int) -> void:
	var path := _active_paths.get(squadron_id) \
		as SquadronCommandPathPresenter
	if path != null:
		path.hide_path()


func _on_player_selection_changed(
		selected: bool,
		squadron_id: int
) -> void:
	if not selected:
		_release_presenters(squadron_id)


func _on_squadron_finished(
		_squadron: AircraftSquadron,
		squadron_id: int
) -> void:
	_release_presenters(squadron_id)


func _on_squadron_tree_exiting(squadron_id: int) -> void:
	_release_presenters(squadron_id)


func _get_squadron(squadron_id: int) -> AircraftSquadron:
	var reference := _selected_squadrons.get(squadron_id) \
		as WeakRef
	if reference == null:
		return null
	var squadron := reference.get_ref() as AircraftSquadron
	return squadron \
		if squadron != null and is_instance_valid(squadron) else null


func _is_terminal_state(squadron: AircraftSquadron) -> bool:
	return squadron.state in [
		AircraftSquadron.State.RETURNING,
		AircraftSquadron.State.RECOVERING,
		AircraftSquadron.State.DESTROYED,
	]


func _acquire_box() -> SquadronSelectionBox:
	var box: SquadronSelectionBox
	if not _available_boxes.is_empty():
		box = _available_boxes.pop_back()
	else:
		box = selection_box_scene.instantiate() \
			as SquadronSelectionBox
		selection_box_root.add_child(box)
	box.setup(settings)
	return box


func _acquire_path() -> SquadronCommandPathPresenter:
	var path: SquadronCommandPathPresenter
	if not _available_paths.is_empty():
		path = _available_paths.pop_back()
	else:
		path = command_path_scene.instantiate() \
			as SquadronCommandPathPresenter
		command_path_root.add_child(path)
	path.setup(settings)
	path.hide_path()
	return path


func _acquire_overlay() -> SquadronStatusOverlay:
	var overlay: SquadronStatusOverlay
	if not _available_overlays.is_empty():
		overlay = _available_overlays.pop_back()
	else:
		overlay = status_overlay_scene.instantiate() \
			as SquadronStatusOverlay
		status_overlay_root.add_child(overlay)
	overlay.visible = false
	return overlay


func _release_presenters(squadron_id: int) -> void:
	_disconnect_squadron_binding(squadron_id)
	var box := _active_boxes.get(squadron_id) \
		as SquadronSelectionBox
	if box != null:
		box.deactivate()
		if not _available_boxes.has(box):
			_available_boxes.append(box)
	var path := _active_paths.get(squadron_id) \
		as SquadronCommandPathPresenter
	if path != null:
		path.deactivate()
		if not _available_paths.has(path):
			_available_paths.append(path)
	var overlay := _active_overlays.get(squadron_id) \
		as SquadronStatusOverlay
	if overlay != null:
		overlay.deactivate()
		if not _available_overlays.has(overlay):
			_available_overlays.append(overlay)
	_active_boxes.erase(squadron_id)
	_active_paths.erase(squadron_id)
	_active_overlays.erase(squadron_id)
	_selected_squadrons.erase(squadron_id)
	_last_frames.erase(squadron_id)


func get_debug_snapshot() -> Dictionary:
	var box_count := _active_boxes.size() + _available_boxes.size()
	var path_count := _active_paths.size() + _available_paths.size()
	var overlay_count := _active_overlays.size() \
		+ _available_overlays.size()
	return {
		"active_selection_box_count": _active_boxes.size(),
		"available_selection_box_count": _available_boxes.size(),
		"active_path_count": _active_paths.size(),
		"available_path_count": _available_paths.size(),
		"active_overlay_count": _active_overlays.size(),
		"available_overlay_count": _available_overlays.size(),
		"active_binding_count": _bindings.size(),
		"presentation_node_count": box_count + path_count + overlay_count,
		"presentation_mesh_count": box_count * 12 + path_count * 2,
		"processing_presenter_count": _count_processing_presenters(),
		"bounds_refresh_count": _bounds_refresh_count,
		"snapshot_build_count": _snapshot_build_count,
	}


func _count_processing_presenters() -> int:
	var count := 0
	for presenter in selection_box_root.get_children():
		if presenter.is_processing() or presenter.is_physics_processing():
			count += 1
	for presenter in command_path_root.get_children():
		if presenter.is_processing() or presenter.is_physics_processing():
			count += 1
	for presenter in status_overlay_root.get_children():
		if presenter.is_processing() or presenter.is_physics_processing():
			count += 1
	return count


func _clear_local_pools() -> void:
	for box in _available_boxes:
		if box != null and is_instance_valid(box):
			box.deactivate()
			box.queue_free()
	for path in _available_paths:
		if path != null and is_instance_valid(path):
			path.deactivate()
			path.queue_free()
	for overlay in _available_overlays:
		if overlay != null and is_instance_valid(overlay):
			overlay.deactivate()
			overlay.queue_free()
	_available_boxes.clear()
	_available_paths.clear()
	_available_overlays.clear()

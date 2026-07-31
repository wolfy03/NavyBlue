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
var _snapshot_builder := SquadronPresentationSnapshotBuilder.new()
var _selected_squadrons: Dictionary = {}
var _active_boxes: Dictionary = {}
var _active_paths: Dictionary = {}
var _active_overlays: Dictionary = {}
var _last_bounds: Dictionary = {}
var _available_boxes: Array[SquadronSelectionBox] = []
var _available_paths: Array[SquadronCommandPathPresenter] = []
var _available_overlays: Array[SquadronStatusOverlay] = []
var _bounds_refresh_left := 0.0
var _status_refresh_left := 0.0


func _ready() -> void:
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
	_last_bounds.clear()
	_selection_controller = null
	_camera = null
	_battle_environment = null
	_clear_local_pools()
	set_process(false)


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
			_active_boxes[squadron_id] = _acquire_box()
			_active_paths[squadron_id] = _acquire_path()
			_active_overlays[squadron_id] = _acquire_overlay()
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
		if squadron == null:
			_release_presenters(squadron_id)
			continue
		if refresh_bounds:
			_refresh_world_presentation(
				squadron_id,
				squadron
			)
		_refresh_overlay(
			squadron_id,
			squadron,
			refresh_status
		)


func _refresh_world_presentation(
		squadron_id: int,
		squadron: AircraftSquadron
) -> void:
	var box := _active_boxes.get(squadron_id) \
		as SquadronSelectionBox
	if box == null:
		return
	var bounds := box.calculate_squadron_bounds(squadron)
	_last_bounds[squadron_id] = bounds
	box.set_bounds(bounds)
	box.set_visible_state(true)
	var path := _active_paths.get(squadron_id) \
		as SquadronCommandPathPresenter
	if path == null:
		return
	var destination := squadron.get_destination_snapshot()
	if path.should_show_path(squadron, destination):
		path.update_path(
			squadron.formation_center,
			destination.destination
		)
	else:
		path.hide_path()


func _refresh_overlay(
		squadron_id: int,
		squadron: AircraftSquadron,
		refresh_status: bool
) -> void:
	var overlay := _active_overlays.get(squadron_id) \
		as SquadronStatusOverlay
	if overlay == null:
		return
	if refresh_status:
		overlay.set_snapshot(_snapshot_builder.build(squadron))
	var bounds: AABB = _last_bounds.get(
		squadron_id,
		AABB(
			squadron.formation_center,
			Vector3.ZERO
		)
	)
	var bottom_right_world := Vector3(
		bounds.position.x + bounds.size.x,
		bounds.position.y,
		bounds.position.z + bounds.size.z
	)
	overlay.set_screen_anchor(
		_camera,
		bottom_right_world,
		settings.status_offset_pixels
	)


func _get_squadron(squadron_id: int) -> AircraftSquadron:
	var reference := _selected_squadrons.get(squadron_id) \
		as WeakRef
	if reference == null:
		return null
	var squadron := reference.get_ref() as AircraftSquadron
	return squadron \
		if squadron != null and is_instance_valid(squadron) else null


func _acquire_box() -> SquadronSelectionBox:
	var box: SquadronSelectionBox
	if not _available_boxes.is_empty():
		box = _available_boxes.pop_back() \
			as SquadronSelectionBox
	else:
		box = selection_box_scene.instantiate() \
			as SquadronSelectionBox
		selection_box_root.add_child(box)
	box.setup(settings)
	box.set_visible_state(true)
	return box


func _acquire_path() -> SquadronCommandPathPresenter:
	var path: SquadronCommandPathPresenter
	if not _available_paths.is_empty():
		path = _available_paths.pop_back() \
			as SquadronCommandPathPresenter
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
		overlay = _available_overlays.pop_back() \
			as SquadronStatusOverlay
	else:
		overlay = status_overlay_scene.instantiate() \
			as SquadronStatusOverlay
		status_overlay_root.add_child(overlay)
	overlay.visible = true
	return overlay


func _release_presenters(squadron_id: int) -> void:
	var box := _active_boxes.get(squadron_id) \
		as SquadronSelectionBox
	if box != null:
		box.set_visible_state(false)
		_available_boxes.append(box)
	var path := _active_paths.get(squadron_id) \
		as SquadronCommandPathPresenter
	if path != null:
		path.hide_path()
		_available_paths.append(path)
	var overlay := _active_overlays.get(squadron_id) \
		as SquadronStatusOverlay
	if overlay != null:
		overlay.visible = false
		_available_overlays.append(overlay)
	_active_boxes.erase(squadron_id)
	_active_paths.erase(squadron_id)
	_active_overlays.erase(squadron_id)
	_selected_squadrons.erase(squadron_id)
	_last_bounds.erase(squadron_id)


func _clear_local_pools() -> void:
	for box in _available_boxes:
		if box != null and is_instance_valid(box):
			box.queue_free()
	for path in _available_paths:
		if path != null and is_instance_valid(path):
			path.queue_free()
	for overlay in _available_overlays:
		if overlay != null and is_instance_valid(overlay):
			overlay.queue_free()
	_available_boxes.clear()
	_available_paths.clear()
	_available_overlays.clear()

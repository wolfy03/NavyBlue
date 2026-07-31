extends Node3D
class_name ShipWeaponPreviewPresentation

const DEFAULT_SETTINGS: TurretPreviewSettings = preload(
	"res://resources/settings/default_turret_preview_settings.tres"
)

@export var settings: TurretPreviewSettings = DEFAULT_SETTINGS
@export var preview_scene: PackedScene
@export var ready_material: StandardMaterial3D
@export var blocked_material: StandardMaterial3D

@onready var preview_root: Node3D = %PreviewRoot

var _input_manager: PlayerInputManager
var _snapshot_builder := TurretPreviewSnapshotBuilder.new()
var _controlled_ship_ref: WeakRef
var _active_previews: Dictionary = {}
var _available_previews: Array[TurretRangePreview] = []
var _mount_refs: Dictionary = {}
var _mount_exit_callbacks: Dictionary = {}
var _ship_died_callback := Callable()
var _ship_exit_callback := Callable()
var _runtime_ready_material: StandardMaterial3D
var _runtime_blocked_material: StandardMaterial3D
var _refresh_left := 0.0
var _refresh_count := 0
var _material_switch_count := 0
var _warned_ship_ids: Dictionary = {}


func _ready() -> void:
	add_to_group(&"ship_weapon_preview_presentations")
	set_process(false)


func setup(input_manager: PlayerInputManager) -> void:
	shutdown()
	_input_manager = input_manager
	_configure_runtime_materials()
	if _input_manager == null:
		return
	_connect_input_signals()
	_bind_controlled_ship(_input_manager.get_controlled_ship())
	set_process(true)
	refresh_now()


func shutdown() -> void:
	set_process(false)
	_disconnect_input_signals()
	_disconnect_ship_signals()
	_release_all_previews()
	_input_manager = null
	_controlled_ship_ref = null
	_refresh_left = 0.0
	_clear_local_pool()


func _process(delta: float) -> void:
	if _input_manager == null:
		return
	var controlled_ship_value: Variant = \
		_input_manager.get_controlled_ship()
	if controlled_ship_value == null \
			or not is_instance_valid(controlled_ship_value):
		_disconnect_ship_signals()
		_controlled_ship_ref = null
		_release_all_previews()
		return
	var controlled_ship := controlled_ship_value as ShipUnit
	if controlled_ship != _get_controlled_ship():
		_bind_controlled_ship(controlled_ship)
		refresh_now()
		return
	if not _should_show(controlled_ship):
		_release_all_previews()
		return
	_refresh_left = maxf(_refresh_left - maxf(delta, 0.0), 0.0)
	if _refresh_left <= 0.0:
		refresh_now()


func refresh_now() -> void:
	_refresh_left = maxf(settings.refresh_interval_sec, 0.01) \
		if settings != null else 0.05
	var ship := _get_controlled_ship()
	if not _should_show(ship):
		_release_all_previews()
		return
	var mounts := ship.get_player_cannon_preview_mounts()
	_warn_for_unexpected_mount_count(ship, mounts.size())
	var current_ids: Dictionary = {}
	for mount in mounts:
		var mount_id := mount.get_instance_id()
		current_ids[mount_id] = true
		var preview := _active_previews.get(mount_id) \
			as TurretRangePreview
		if preview == null:
			preview = _acquire_preview(mount)
			_active_previews[mount_id] = preview
			_connect_mount_exit(mount)
		var had_ready_state := preview.has_ready_state()
		var previous_ready := preview.get_last_ready_state()
		var snapshot := _snapshot_builder.build(mount)
		preview.apply_snapshot(snapshot)
		if snapshot.visible \
				and (
					not had_ready_state \
					or previous_ready != snapshot.can_fire_now
				):
			_material_switch_count += 1
	for id_value in _active_previews.keys():
		var mount_id := int(id_value)
		if not current_ids.has(mount_id):
			_release_preview(mount_id)
	_refresh_count += 1


func get_debug_snapshot() -> Dictionary:
	return {
		"active_preview_count": _active_previews.size(),
		"available_preview_count": _available_previews.size(),
		"mount_binding_count": _mount_exit_callbacks.size(),
		"refresh_count": _refresh_count,
		"material_switch_count": _material_switch_count,
		"processing_preview_count": _count_processing_previews(),
	}


func get_active_previews() -> Array[TurretRangePreview]:
	var result: Array[TurretRangePreview] = []
	for preview_value in _active_previews.values():
		var preview := preview_value as TurretRangePreview
		if preview != null:
			result.append(preview)
	return result


func get_runtime_ready_material() -> StandardMaterial3D:
	return _runtime_ready_material


func get_runtime_blocked_material() -> StandardMaterial3D:
	return _runtime_blocked_material


func _should_show(ship: ShipUnit) -> bool:
	if ship == null \
			or not is_instance_valid(ship) \
			or not ship.is_alive() \
			or not ship.player_controlled \
			or _input_manager == null \
			or not _input_manager.is_input_enabled() \
			or _input_manager.get_command_mode() \
				!= PlayerInputManager.CommandMode.SHIP:
		return false
	return _input_manager.get_selected_ships().has(ship)


func _bind_controlled_ship(ship: ShipUnit) -> void:
	_disconnect_ship_signals()
	_release_all_previews()
	if ship == null or not is_instance_valid(ship):
		_controlled_ship_ref = null
		return
	_controlled_ship_ref = weakref(ship)
	_ship_exit_callback = Callable(self, "_on_controlled_ship_exiting")
	if not ship.tree_exiting.is_connected(_ship_exit_callback):
		ship.tree_exiting.connect(
			_ship_exit_callback,
			CONNECT_ONE_SHOT
		)
	if ship.health != null:
		_ship_died_callback = Callable(self, "_on_controlled_ship_died")
		if not ship.health.died.is_connected(_ship_died_callback):
			ship.health.died.connect(
				_ship_died_callback,
				CONNECT_ONE_SHOT
			)


func _disconnect_ship_signals() -> void:
	var ship := _get_controlled_ship()
	if ship != null:
		if _ship_exit_callback.is_valid() \
				and ship.tree_exiting.is_connected(_ship_exit_callback):
			ship.tree_exiting.disconnect(_ship_exit_callback)
		if ship.health != null \
				and _ship_died_callback.is_valid() \
				and ship.health.died.is_connected(_ship_died_callback):
			ship.health.died.disconnect(_ship_died_callback)
	_ship_exit_callback = Callable()
	_ship_died_callback = Callable()


func _get_controlled_ship() -> ShipUnit:
	if _controlled_ship_ref == null:
		return null
	var ship := _controlled_ship_ref.get_ref() as ShipUnit
	return ship if ship != null and is_instance_valid(ship) else null


func _acquire_preview(mount: WeaponMount) -> TurretRangePreview:
	var preview: TurretRangePreview
	if not _available_previews.is_empty():
		preview = _available_previews.pop_back()
	else:
		preview = preview_scene.instantiate() as TurretRangePreview
		preview_root.add_child(preview)
	preview.setup(
		settings,
		_runtime_ready_material,
		_runtime_blocked_material
	)
	preview.activate(mount)
	return preview


func _release_preview(mount_id: int) -> void:
	_disconnect_mount_exit(mount_id)
	var preview := _active_previews.get(mount_id) \
		as TurretRangePreview
	if preview != null:
		preview.deactivate()
		if not _available_previews.has(preview):
			_available_previews.append(preview)
	_active_previews.erase(mount_id)


func _release_all_previews() -> void:
	for id_value in _active_previews.keys():
		_release_preview(int(id_value))


func _connect_mount_exit(mount: WeaponMount) -> void:
	var mount_id := mount.get_instance_id()
	_disconnect_mount_exit(mount_id)
	var callback := Callable(
		self,
		"_on_mount_tree_exiting"
	).bind(mount_id)
	_mount_refs[mount_id] = weakref(mount)
	_mount_exit_callbacks[mount_id] = callback
	if not mount.tree_exiting.is_connected(callback):
		mount.tree_exiting.connect(callback, CONNECT_ONE_SHOT)


func _disconnect_mount_exit(mount_id: int) -> void:
	var mount_ref := _mount_refs.get(mount_id) as WeakRef
	var mount := mount_ref.get_ref() as WeaponMount \
		if mount_ref != null else null
	var callback := _mount_exit_callbacks.get(
		mount_id,
		Callable()
	) as Callable
	if mount != null \
			and is_instance_valid(mount) \
			and callback.is_valid() \
			and mount.tree_exiting.is_connected(callback):
		mount.tree_exiting.disconnect(callback)
	_mount_refs.erase(mount_id)
	_mount_exit_callbacks.erase(mount_id)


func _connect_input_signals() -> void:
	if not _input_manager.command_mode_changed.is_connected(
		_on_command_mode_changed
	):
		_input_manager.command_mode_changed.connect(
			_on_command_mode_changed
		)
	if not _input_manager.input_enabled_changed.is_connected(
		_on_input_enabled_changed
	):
		_input_manager.input_enabled_changed.connect(
			_on_input_enabled_changed
		)
	if not _input_manager.selection_changed.is_connected(
		_on_selection_changed
	):
		_input_manager.selection_changed.connect(_on_selection_changed)
	if not _input_manager.controlled_ship_changed.is_connected(
		_on_controlled_ship_changed
	):
		_input_manager.controlled_ship_changed.connect(
			_on_controlled_ship_changed
		)


func _disconnect_input_signals() -> void:
	if _input_manager == null:
		return
	if _input_manager.command_mode_changed.is_connected(
		_on_command_mode_changed
	):
		_input_manager.command_mode_changed.disconnect(
			_on_command_mode_changed
		)
	if _input_manager.input_enabled_changed.is_connected(
		_on_input_enabled_changed
	):
		_input_manager.input_enabled_changed.disconnect(
			_on_input_enabled_changed
		)
	if _input_manager.selection_changed.is_connected(
		_on_selection_changed
	):
		_input_manager.selection_changed.disconnect(_on_selection_changed)
	if _input_manager.controlled_ship_changed.is_connected(
		_on_controlled_ship_changed
	):
		_input_manager.controlled_ship_changed.disconnect(
			_on_controlled_ship_changed
		)


func _configure_runtime_materials() -> void:
	if ready_material != null and _runtime_ready_material == null:
		_runtime_ready_material = ready_material.duplicate() \
			as StandardMaterial3D
	if blocked_material != null and _runtime_blocked_material == null:
		_runtime_blocked_material = blocked_material.duplicate() \
			as StandardMaterial3D
	if settings != null:
		if _runtime_ready_material != null:
			_runtime_ready_material.albedo_color = settings.ready_color
		if _runtime_blocked_material != null:
			_runtime_blocked_material.albedo_color = settings.blocked_color


func _warn_for_unexpected_mount_count(
		ship: ShipUnit,
		mount_count: int
) -> void:
	if settings == null \
			or settings.preview_mount_warning_threshold <= 0 \
			or mount_count <= settings.preview_mount_warning_threshold:
		return
	var ship_id := ship.get_instance_id()
	if _warned_ship_ids.has(ship_id):
		return
	_warned_ship_ids[ship_id] = true
	push_warning(
		"Controlled ship has %d cannon preview mounts." % mount_count
	)


func _count_processing_previews() -> int:
	var count := 0
	for child in preview_root.get_children():
		if child.is_processing() or child.is_physics_processing():
			count += 1
	return count


func _clear_local_pool() -> void:
	for preview in _available_previews:
		if preview != null and is_instance_valid(preview):
			preview.deactivate()
			preview.queue_free()
	_available_previews.clear()


func _on_command_mode_changed(
		_mode: PlayerInputManager.CommandMode
) -> void:
	refresh_now()


func _on_input_enabled_changed(_enabled: bool) -> void:
	refresh_now()


func _on_selection_changed(
		_selected_ships: Array[ShipUnit]
) -> void:
	refresh_now()


func _on_controlled_ship_changed(ship: ShipUnit) -> void:
	_bind_controlled_ship(ship)
	refresh_now()


func _on_controlled_ship_died() -> void:
	_release_all_previews()


func _on_controlled_ship_exiting() -> void:
	_release_all_previews()
	_controlled_ship_ref = null


func _on_mount_tree_exiting(mount_id: int) -> void:
	_release_preview(mount_id)

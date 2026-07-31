extends Node3D
class_name ShipAimRangePreview

const DEFAULT_SETTINGS: ShipAimPreviewSettings = preload(
	"res://resources/settings/default_ship_aim_preview.tres"
)

@export var settings: ShipAimPreviewSettings = DEFAULT_SETTINGS
@onready var line_mesh: MeshInstance3D = %LineMesh

var _input_manager: PlayerInputManager
var _ship_commands: ShipCommandController
var _ship_ref: WeakRef
var _command: ShipManualAimCommand
var _runtime_material: StandardMaterial3D


func _ready() -> void:
	visible = false
	set_process(false)
	_apply_material()


func setup(
		input_manager: PlayerInputManager,
		ship_commands: ShipCommandController
) -> void:
	shutdown()
	_input_manager = input_manager
	_ship_commands = ship_commands
	if _ship_commands != null:
		if not _ship_commands.manual_aim_changed.is_connected(
			_on_manual_aim_changed
		):
			_ship_commands.manual_aim_changed.connect(
				_on_manual_aim_changed
			)
		if not _ship_commands.manual_aim_cleared.is_connected(
			_on_manual_aim_cleared
		):
			_ship_commands.manual_aim_cleared.connect(
				_on_manual_aim_cleared
			)
	if _input_manager != null:
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
	if _ship_commands != null:
		_ship_commands.refresh_manual_aim_preview()


func shutdown() -> void:
	if _ship_commands != null:
		if _ship_commands.manual_aim_changed.is_connected(
			_on_manual_aim_changed
		):
			_ship_commands.manual_aim_changed.disconnect(
				_on_manual_aim_changed
			)
		if _ship_commands.manual_aim_cleared.is_connected(
			_on_manual_aim_cleared
		):
			_ship_commands.manual_aim_cleared.disconnect(
				_on_manual_aim_cleared
			)
	if _input_manager != null:
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
	_input_manager = null
	_ship_commands = null
	_ship_ref = null
	_command = null
	hide_preview()


func _process(_delta: float) -> void:
	var ship := _get_ship()
	if not _should_show(ship):
		hide_preview()
		return
	var direction := ship.combat.get_manual_aim_world_direction()
	var maximum_range_m := ship \
		.get_player_cannon_preview_range_m()
	show_preview(
		ship.get_player_cannon_preview_origin(),
		direction,
		maximum_range_m
	)


func show_preview(
		origin: Vector3,
		world_direction: Vector3,
		maximum_range_m: float
) -> void:
	if maximum_range_m <= 0.0 \
			or world_direction.length_squared() <= 0.0001:
		hide_preview()
		return
	var direction := world_direction.normalized()
	var start := origin + Vector3.UP * settings.height_offset_m
	var end := start + direction * maximum_range_m
	if not BoxLinePlacement.place_between(
		self,
		line_mesh,
		start,
		end,
		settings.line_thickness_m
	):
		hide_preview()
		return
	visible = true
	set_process(true)


func hide_preview() -> void:
	visible = false
	if line_mesh != null:
		line_mesh.visible = false
	set_process(false)


func _should_show(ship: ShipUnit) -> bool:
	return ship != null \
		and is_instance_valid(ship) \
		and ship.is_alive() \
		and ship.combat != null \
		and ship.combat.is_manual_relative_aim_active() \
		and _input_manager != null \
		and _input_manager.is_input_enabled() \
		and _input_manager.get_command_mode() \
			== PlayerInputManager.CommandMode.SHIP


func _get_ship() -> ShipUnit:
	if _ship_ref == null:
		return null
	var ship := _ship_ref.get_ref() as ShipUnit
	return ship if ship != null and is_instance_valid(ship) else null


func _on_manual_aim_changed(
		ship: ShipUnit,
		command: ShipManualAimCommand
) -> void:
	_ship_ref = weakref(ship) \
		if ship != null and is_instance_valid(ship) else null
	_command = command.duplicate_command() if command != null else null
	set_process(_command != null)
	if _command == null:
		hide_preview()


func _on_manual_aim_cleared(_ship: ShipUnit) -> void:
	_ship_ref = null
	_command = null
	hide_preview()


func _on_command_mode_changed(
	_mode: PlayerInputManager.CommandMode
) -> void:
	if _input_manager == null \
			or _input_manager.get_command_mode() \
				!= PlayerInputManager.CommandMode.SHIP:
		hide_preview()
	elif _ship_commands != null:
		_ship_commands.refresh_manual_aim_preview()


func _on_input_enabled_changed(enabled: bool) -> void:
	if not enabled:
		hide_preview()
	elif _ship_commands != null:
		_ship_commands.refresh_manual_aim_preview()


func _apply_material() -> void:
	if line_mesh == null:
		return
	if _runtime_material == null:
		var source_material := line_mesh.material_override \
			as StandardMaterial3D
		if source_material != null:
			_runtime_material = source_material.duplicate() \
				as StandardMaterial3D
	if _runtime_material == null:
		return
	_runtime_material.albedo_color = settings.line_color
	line_mesh.material_override = _runtime_material


func get_runtime_material() -> StandardMaterial3D:
	return _runtime_material

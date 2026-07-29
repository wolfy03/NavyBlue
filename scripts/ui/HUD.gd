extends CanvasLayer
class_name HUD

const SHIP_DATABASE_SCRIPT := preload("res://scripts/data/ShipDatabase.gd")
const SHIP_STATUS_INDICATOR_SCENE: PackedScene = preload("res://scenes/ui/ship_status_indicator.tscn")

@onready var status_label: Label = $StatusLabel
@onready var ship_status_overlay_root: Control = $ShipStatusOverlayRoot
@onready var mode_label: Label = %ModeLabel
@onready var mode_hint_label: Label = %ModeHintLabel
@onready var aircraft_feedback_label: Label = %AircraftFeedbackLabel

var target_ship: Node3D
var battle_camera: Camera3D
var ship_database: RefCounted = SHIP_DATABASE_SCRIPT.new()
var _ship_indicators: Dictionary[int, ShipStatusIndicator] = {}
var _feedback_time_left := 0.0


func _ready() -> void:
	if has_node("/root/EventBus"):
		var event_bus: Node = get_node("/root/EventBus")
		if not event_bus.ship_spawned.is_connected(_on_ship_spawned):
			event_bus.ship_spawned.connect(_on_ship_spawned)
		if not event_bus.ship_destroyed.is_connected(_on_ship_destroyed):
			event_bus.ship_destroyed.connect(_on_ship_destroyed)


func setup(ship: Node3D, camera: Camera3D = null) -> void:
	target_ship = ship
	battle_camera = camera
	_sync_ship_indicators()

func _process(delta: float) -> void:
	if _feedback_time_left > 0.0:
		_feedback_time_left = maxf(
			0.0,
			_feedback_time_left - maxf(delta, 0.0)
		)
		if _feedback_time_left <= 0.0 \
				and aircraft_feedback_label != null:
			aircraft_feedback_label.visible = false
	if status_label == null or not is_instance_valid(target_ship):
		return
	var data = target_ship.ship_data
	var turret_pitch := 0.0
	var cannons: Array[WeaponMount] = target_ship.combat.get_weapons_by_type(
		WeaponTypes.Type.CANNON
	)
	if not cannons.is_empty() and cannons[0] is CannonMount:
		turret_pitch = (cannons[0] as CannonMount).pitch_degrees
	var damage_status := target_ship.get_node_or_null("ShipDamageStatus") \
		as ShipDamageStatus
	var status_suffix := " | FLOODING %.1fs" % damage_status.flooding_time_left \
		if damage_status != null and damage_status.is_flooding() else ""
	status_label.text = "%s | %s%s\nEngine %d%% | Speed %.1f | Gun %.1f deg" % [
		data.display_name,
		ship_database.class_label(data.ship_class),
		status_suffix,
		roundi(target_ship.get_engine_output() * 100.0),
		target_ship.get_speed_knots_style(),
		turret_pitch,
	]


func set_command_mode(mode: int) -> void:
	if mode_label == null or mode_hint_label == null:
		return
	if mode == PlayerInputManager.CommandMode.AIRCRAFT:
		mode_label.text = "AIRCRAFT COMMAND"
		mode_hint_label.text = \
			"Drag select | Right-click move | . dive/release | TAB ship"
	else:
		mode_label.text = "SHIP COMMAND"
		mode_hint_label.text = \
			"Left-click select | Right-click move | TAB aircraft"


func show_aircraft_command_feedback(
		message: String,
		duration_seconds: float = 1.6
) -> void:
	if aircraft_feedback_label == null:
		return
	aircraft_feedback_label.text = message
	aircraft_feedback_label.visible = not message.is_empty()
	_feedback_time_left = maxf(duration_seconds, 0.0)


func _sync_ship_indicators() -> void:
	if get_tree() == null:
		return
	for ship_node: Node in get_tree().get_nodes_in_group("ships"):
		_on_ship_spawned(ship_node)


func _on_ship_spawned(ship: Node) -> void:
	if not ship is Node3D or ship_status_overlay_root == null:
		return
	var ship_3d := ship as Node3D
	var instance_id: int = ship_3d.get_instance_id()
	if _ship_indicators.has(instance_id):
		return
	var indicator := SHIP_STATUS_INDICATOR_SCENE.instantiate() as ShipStatusIndicator
	if indicator == null:
		return
	ship_status_overlay_root.add_child(indicator)
	indicator.setup(ship_3d, battle_camera)
	_ship_indicators[instance_id] = indicator
	ship_3d.tree_exiting.connect(_remove_ship_indicator.bind(instance_id), CONNECT_ONE_SHOT)


func _on_ship_destroyed(ship: Node) -> void:
	if ship == null:
		return
	_remove_ship_indicator(ship.get_instance_id())


func _remove_ship_indicator(instance_id: int) -> void:
	var indicator_value: Variant = _ship_indicators.get(instance_id)
	if indicator_value != null and is_instance_valid(indicator_value):
		var indicator := indicator_value as ShipStatusIndicator
		if indicator != null:
			indicator.queue_free()
	_ship_indicators.erase(instance_id)

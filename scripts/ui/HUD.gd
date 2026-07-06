extends CanvasLayer
class_name HUD

const SHIP_DATABASE_SCRIPT := preload("res://scripts/data/ShipDatabase.gd")

@onready var status_label: Label = $StatusLabel

var target_ship
var ship_database := SHIP_DATABASE_SCRIPT.new()

func setup(ship) -> void:
	target_ship = ship

func _process(_delta: float) -> void:
	if status_label == null or target_ship == null:
		return
	var data = target_ship.ship_data
	var turret_pitch := 0.0
	if not target_ship.turrets.is_empty():
		turret_pitch = target_ship.turrets[0].pitch_degrees
	status_label.text = "%s | %s\nEngine %d%% | Speed %.1f | Gun %.1f deg" % [
		data.display_name,
		ship_database.class_label(data.ship_class),
		roundi(target_ship.engine_output * 100.0),
		target_ship.get_speed_knots_style(),
		turret_pitch,
	]


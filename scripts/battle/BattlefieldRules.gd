extends Resource
class_name BattlefieldRules

@export_category("Command Bounds")
@export var ship_command_margin_m := 250.0
@export var aircraft_command_margin_m := 100.0
@export var projectile_cleanup_margin_m := 500.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if ship_command_margin_m < 0.0:
		errors.append("ship_command_margin_m must not be negative.")
	if aircraft_command_margin_m < 0.0:
		errors.append("aircraft_command_margin_m must not be negative.")
	if projectile_cleanup_margin_m < 0.0:
		errors.append("projectile_cleanup_margin_m must not be negative.")
	return errors

extends RefCounted
class_name AircraftVisualController
## Owns the aircraft's visual-only attitude: banking today, with room for
## pitch, pull-out posture, hit shake, turbulence and propeller spin later.
##
## Writes exclusively to the visual root node handed in at setup. The physics
## root, collision shape and weapon transforms never roll, so flight behaviour
## and hit detection are unaffected by anything in this controller.

## Shared fallback used whenever an aircraft supplies no per-type settings.
## Always the .tres resource: code never builds a second set of defaults with
## AircraftBankVisualSettings.new(), so the values live in exactly one place.
const DEFAULT_BANK_SETTINGS: AircraftBankVisualSettings = preload(
	"res://resources/aircraft/settings/default_bank_visual_settings.tres"
)

var visual_root: Node3D
var bank_settings: AircraftBankVisualSettings
## The visual root's rotation as authored in the scene (import correction,
## model pivot fixes). Banking is always added on top of this base and never
## overwrites it, so models with a non-zero authored rotation stay correct.
var visual_base_rotation := Vector3.ZERO

var _previous_horizontal_velocity := Vector3.ZERO
var _current_bank_angle_rad := 0.0


func setup(
		next_visual_root: Node3D,
		next_bank_settings: AircraftBankVisualSettings = null
) -> void:
	visual_root = next_visual_root
	bank_settings = next_bank_settings
	visual_base_rotation = visual_root.rotation \
		if visual_root != null and is_instance_valid(visual_root) \
		else Vector3.ZERO
	reset_visual_attitude()


func set_bank_settings(
		next_bank_settings: AircraftBankVisualSettings
) -> void:
	bank_settings = next_bank_settings


func get_bank_settings() -> AircraftBankVisualSettings:
	return bank_settings if bank_settings != null else DEFAULT_BANK_SETTINGS


func has_visual_root() -> bool:
	return visual_root != null and is_instance_valid(visual_root)


## Per-frame attitude update. Reads only the aircraft's own velocity; an
## inactive aircraft keeps its current attitude (lifecycle transitions call
## reset_visual_attitude explicitly).
func update_visual_attitude(
		delta: float,
		velocity: Vector3,
		_global_transform: Transform3D,
		active: bool
) -> void:
	if not active or not has_visual_root() or delta <= 0.0:
		return
	var settings := get_bank_settings()
	var horizontal_velocity := velocity
	horizontal_velocity.y = 0.0
	var target_bank_rad := 0.0
	var minimum_speed := maxf(settings.minimum_horizontal_speed_mps, 0.0)
	if horizontal_velocity.length() >= minimum_speed \
			and _previous_horizontal_velocity.length() >= minimum_speed:
		# Turn direction and rate from the signed change of the aircraft's own
		# horizontal track. Flying straight (or diving without turning) gives
		# zero rate, so the model levels out on its own.
		var turn_rate_rad := _previous_horizontal_velocity.signed_angle_to(
			horizontal_velocity,
			Vector3.UP
		) / delta
		var full_bank_rate_rad := deg_to_rad(maxf(
			settings.turn_rate_for_full_bank_deg_sec,
			0.001
		))
		var maximum_bank_rad := deg_to_rad(clampf(
			settings.maximum_bank_angle_degrees,
			0.0,
			85.0
		))
		# Left turn (positive yaw about UP) banks left, which is a positive
		# roll about +Z for a -Z-forward model.
		target_bank_rad = clampf(
			turn_rate_rad / full_bank_rate_rad,
			-1.0,
			1.0
		) * maximum_bank_rad
	_previous_horizontal_velocity = horizontal_velocity
	var bank_speed_deg := settings.bank_response_speed_deg_sec \
		if absf(target_bank_rad) > absf(_current_bank_angle_rad) \
		else settings.bank_return_speed_deg_sec
	_current_bank_angle_rad = move_toward(
		_current_bank_angle_rad,
		target_bank_rad,
		deg_to_rad(maxf(bank_speed_deg, 0.0)) * delta
	)
	_apply_attitude()


## Clears all attitude state and restores the authored base rotation. Called
## on setup, activate, deactivate and pool reuse so a fresh sortie can never
## inherit the previous flight's velocity history and snap to full bank.
func reset_visual_attitude() -> void:
	_previous_horizontal_velocity = Vector3.ZERO
	_current_bank_angle_rad = 0.0
	if has_visual_root():
		visual_root.rotation = visual_base_rotation


func get_current_bank_angle_rad() -> float:
	return _current_bank_angle_rad


func get_debug_snapshot() -> Dictionary:
	return {
		"has_visual_root": has_visual_root(),
		"visual_base_rotation": visual_base_rotation,
		"current_bank_angle_rad": _current_bank_angle_rad,
		"previous_horizontal_velocity": _previous_horizontal_velocity,
		"using_default_bank_settings": bank_settings == null,
	}


func _apply_attitude() -> void:
	# Absolute assignment on top of the preserved base: never accumulated with
	# rotate_z, so the model can never wind up or drift, and the authored
	# import rotation is never lost.
	var next_rotation := visual_base_rotation
	next_rotation.z += _current_bank_angle_rad
	visual_root.rotation = next_rotation

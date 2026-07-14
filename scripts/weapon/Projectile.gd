extends RigidBody3D
class_name Projectile

const LIFETIME_SECONDS := 12.0

@export var water_height := 0.0
@export var base_water_splash_strength := 1.0
@export var min_water_splash_strength := 0.35
@export var max_water_splash_strength := 4.0
@export var velocity_strength_reference := 45.0

var team: StringName = &"neutral"
var age := 0.0
var previous_position := Vector3.ZERO
var previous_position_initialized := false
var water_impact_processed := false

func _ready() -> void:
	gravity_scale = 1.0
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	previous_position = global_position
	previous_position_initialized = true

func launch(start_velocity: Vector3, owner_team: StringName) -> void:
	team = owner_team
	linear_velocity = start_velocity
	age = 0.0
	water_impact_processed = false
	previous_position = global_position
	previous_position_initialized = true

func _physics_process(delta: float) -> void:
	age += delta
	var current_position := global_position
	if not previous_position_initialized:
		previous_position = current_position
		previous_position_initialized = true

	if not water_impact_processed and _try_process_water_impact(previous_position, current_position):
		queue_free()
		return

	var ocean_manager := _get_ocean_manager()
	if ocean_manager != null and ocean_manager.has_method(&"is_underwater"):
		if bool(ocean_manager.call(&"is_underwater", current_position)):
			queue_free()
			return
	elif current_position.y <= water_height:
		queue_free()
		return

	if age >= LIFETIME_SECONDS:
		queue_free()
		return

	previous_position = current_position


func _try_process_water_impact(from_position: Vector3, to_position: Vector3) -> bool:
	var ocean_manager := _get_ocean_manager()
	if ocean_manager == null:
		return false
	if not ocean_manager.has_method(&"did_cross_water_surface"):
		return false
	if not bool(ocean_manager.call(&"did_cross_water_surface", from_position, to_position)):
		return false

	var hit: RefCounted = ocean_manager.call(&"get_surface_intersection_hit", from_position, to_position)
	if hit == null or not bool(hit.get(&"hit")):
		return false

	water_impact_processed = true
	var interaction := _get_ocean_interaction()
	if interaction != null and interaction.has_method(&"register_impact_at"):
		interaction.call(
			&"register_impact_at",
			hit.get(&"position") as Vector3,
			_calculate_water_impact_strength(),
			linear_velocity,
			hit.get(&"normal") as Vector3,
			self
		)
	return true


func _calculate_water_impact_strength() -> float:
	var speed_factor := clampf(linear_velocity.length() / maxf(velocity_strength_reference, 0.001), 0.25, 3.0)
	var mass_factor := sqrt(maxf(mass, 0.1))
	var strength := base_water_splash_strength * mass_factor * speed_factor
	return clampf(strength, min_water_splash_strength, max_water_splash_strength)


func _get_ocean_manager() -> Node:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group("ocean_manager")


func _get_ocean_interaction() -> Node:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group("ocean_interaction")

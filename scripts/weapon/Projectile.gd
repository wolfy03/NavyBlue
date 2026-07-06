extends RigidBody3D
class_name Projectile

const LIFETIME_SECONDS := 12.0

@export var water_height := 0.0

var team: StringName = &"neutral"
var age := 0.0

func _ready() -> void:
	gravity_scale = 1.0
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true

func launch(start_velocity: Vector3, owner_team: StringName) -> void:
	team = owner_team
	linear_velocity = start_velocity

func _physics_process(delta: float) -> void:
	age += delta
	if global_position.y <= water_height or age >= LIFETIME_SECONDS:
		queue_free()


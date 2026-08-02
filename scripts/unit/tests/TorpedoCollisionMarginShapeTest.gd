extends SceneTree

const SHIP_SCENE := preload("res://scenes/unit/ship.tscn")

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var ship := SHIP_SCENE.instantiate() as ShipUnit
	ship.scale = Vector3(1.0, 1.0, 2.0)
	root.add_child(ship)
	ship.set_physics_process(false)
	ship.ship_data = null
	var collision := ship.get_node("HullCollision") as CollisionShape3D
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 10.0, 100.0)
	collision.shape = box
	collision.position = Vector3(0.0, 0.0, 10.0)
	var disabled_collision := CollisionShape3D.new()
	var huge_box := BoxShape3D.new()
	huge_box.size = Vector3.ONE * 1000.0
	disabled_collision.shape = huge_box
	disabled_collision.disabled = true
	ship.add_child(disabled_collision)
	var margin := ship.get_torpedo_collision_margin_m(
		Vector3(0.0, 0.0, 1.0)
	)
	_check(
		absf(margin - 80.75) < 0.1,
		"world-space shape projection includes scale and local offset"
	)
	ship.rotation.y = PI * 0.5
	var rotated_margin := ship.get_torpedo_collision_margin_m(
		Vector3(1.0, 0.0, 0.0)
	)
	_check(
		absf(rotated_margin - 80.75) < 0.1,
		"world-space shape projection follows hull rotation"
	)
	_check(
		rotated_margin < 500.0,
		"disabled collision shapes are excluded"
	)
	ship.queue_free()
	await process_frame
	print(
		"TORPEDO_COLLISION_MARGIN_SHAPE_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("TORPEDO COLLISION MARGIN: %s" % label)

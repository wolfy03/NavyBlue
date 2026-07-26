extends Node
class_name ShipVisualBuilder

const WEAPON_DATABASE_SCRIPT := preload("res://scripts/data/WeaponDatabase.gd")

var hull_collision: CollisionShape3D
var hull_mesh: MeshInstance3D
var bow_mesh: MeshInstance3D
var deck_mesh: MeshInstance3D
var weapon_mount_root: Node3D
var weapon_database := WEAPON_DATABASE_SCRIPT.new()
var diagnostics_enabled := true


func setup(
		next_hull_collision: CollisionShape3D,
		next_hull_mesh: MeshInstance3D,
		next_bow_mesh: MeshInstance3D,
		next_deck_mesh: MeshInstance3D,
		next_weapon_mount_root: Node3D
) -> void:
	hull_collision = next_hull_collision
	hull_mesh = next_hull_mesh
	bow_mesh = next_bow_mesh
	deck_mesh = next_deck_mesh
	weapon_mount_root = next_weapon_mount_root


func build(
		ship_data: ShipData,
		loadout: ShipWeaponLoadout,
		team: StringName,
		team_color: Color,
		owner_ship: ShipUnit,
		legacy_turret_scene: PackedScene = null
) -> Array[WeaponMount]:
	if ship_data == null:
		push_warning("ShipVisualBuilder cannot build a ship without ShipData.")
		return []
	if weapon_mount_root == null:
		push_warning("ShipVisualBuilder cannot build ship '%s': WeaponMountRoot is missing." % ship_data.id)
		return []
	_apply_hull_shape(ship_data)
	_apply_materials(team_color)
	if ship_data.weapon_slots.is_empty():
		return _build_legacy_turrets(
			ship_data,
			team,
			owner_ship,
			legacy_turret_scene
		)
	return _rebuild_weapon_mounts(ship_data, loadout, team, owner_ship)


func _rebuild_weapon_mounts(
		ship_data: ShipData,
		loadout: ShipWeaponLoadout,
		team: StringName,
		owner_ship: ShipUnit
) -> Array[WeaponMount]:
	_clear_mounts()
	var mounts: Array[WeaponMount] = []
	for slot in ship_data.weapon_slots:
		if slot == null:
			continue
		var weapon_id := loadout.get_weapon_id(slot.slot_id) \
			if loadout != null else ""
		if weapon_id.is_empty():
			weapon_id = slot.default_weapon_id
		if weapon_id.is_empty():
			continue
		var weapon_data := weapon_database.get_weapon(weapon_id)
		var validation := WeaponMountValidator.validate(slot, weapon_data)
		if not validation.valid:
			push_warning(
				"Weapon '%s' cannot be mounted in slot '%s': %s"
				% [weapon_id, String(slot.slot_id), validation.reason]
			)
			continue
		var mount := _create_mount(slot, weapon_data, owner_ship, team)
		if mount != null:
			mounts.append(mount)
	return mounts


func _create_mount(
		slot: ShipWeaponSlotData,
		weapon_data: WeaponData,
		owner_ship: ShipUnit,
		team: StringName,
		mount_scene_override: PackedScene = null
) -> WeaponMount:
	var mount_scene := mount_scene_override \
		if mount_scene_override != null else weapon_data.mount_scene
	if mount_scene == null:
		push_warning("Weapon has no mount scene: %s" % weapon_data.id)
		return null
	var mount := mount_scene.instantiate() as WeaponMount
	if mount == null:
		push_warning("Mount scene must inherit WeaponMount: %s" % weapon_data.id)
		return null
	weapon_mount_root.add_child(mount)
	mount.position = slot.local_position
	mount.rotation_degrees = slot.local_rotation_degrees
	mount.scale = slot.local_scale
	mount.name = String(slot.slot_id)
	mount.setup(weapon_data, slot, owner_ship, team)
	return mount


func _build_legacy_turrets(
		ship_data: ShipData,
		team: StringName,
		owner_ship: ShipUnit,
		legacy_turret_scene: PackedScene
) -> Array[WeaponMount]:
	# Deprecated: compatibility only. Do not use in new ship definitions.
	var mounts: Array[WeaponMount] = []
	if ship_data == null:
		return mounts
	if weapon_mount_root == null:
		if diagnostics_enabled:
			push_warning(
				"Cannot build legacy weapons for ship '%s': WeaponMountRoot is missing."
				% ship_data.id
			)
		return mounts
	_clear_mounts()
	var weapon_data := weapon_database.get_weapon(ship_data.default_weapon_id)
	if weapon_data == null:
		if diagnostics_enabled:
			push_warning(
				"Legacy weapon data could not be loaded for ship '%s': %s"
				% [ship_data.id, ship_data.default_weapon_id]
			)
		return mounts
	if weapon_data.id.is_empty():
		push_warning(
			"Legacy weapon fallback is invalid for ship '%s': %s"
			% [ship_data.id, ship_data.default_weapon_id]
		)
		return mounts
	var scene := weapon_data.mount_scene
	if scene == null:
		scene = legacy_turret_scene
	if scene == null:
		push_warning(
			"Legacy ship '%s' has no mount scene for weapon '%s' and no legacy turret fallback."
			% [ship_data.id, weapon_data.id]
		)
		return mounts
	var start_z := -ship_data.turret_spacing * float(ship_data.turret_count - 1) * 0.5
	for index in range(ship_data.turret_count):
		var slot := ShipWeaponSlotData.new()
		slot.slot_id = StringName("legacy_cannon_%02d" % index)
		slot.display_name = "Legacy Cannon %d" % (index + 1)
		slot.slot_size = weapon_data.required_slot_size
		slot.allowed_weapon_types = [WeaponTypes.Type.CANNON]
		slot.default_weapon_id = weapon_data.id
		slot.local_position = Vector3(
			0.0,
			ship_data.hull_size.y + 0.28,
			start_z + ship_data.turret_spacing * index
		)
		var turret_scale := clampf(ship_data.hull_size.x / 3.0, 5.0, 13.0)
		slot.local_scale = Vector3.ONE * turret_scale
		var mount := _create_mount(
			slot,
			weapon_data,
			owner_ship,
			team,
			scene
		)
		if mount != null:
			mounts.append(mount)
	return mounts


func _clear_mounts() -> void:
	if weapon_mount_root == null:
		return
	for child in weapon_mount_root.get_children():
		weapon_mount_root.remove_child(child)
		child.queue_free()


func _apply_hull_shape(ship_data: ShipData) -> void:
	var hull_size := ship_data.hull_size
	if hull_collision.shape:
		hull_collision.shape = hull_collision.shape.duplicate()
	if hull_mesh.mesh:
		hull_mesh.mesh = hull_mesh.mesh.duplicate()
	if bow_mesh.mesh:
		bow_mesh.mesh = bow_mesh.mesh.duplicate()
	if deck_mesh.mesh:
		deck_mesh.mesh = deck_mesh.mesh.duplicate()
	var collision_box := hull_collision.shape as BoxShape3D
	if collision_box:
		collision_box.size = hull_size
	hull_collision.position.y = hull_size.y * 0.5
	var hull_box := hull_mesh.mesh as BoxMesh
	if hull_box:
		hull_box.size = hull_size
	hull_mesh.position.y = hull_size.y * 0.5
	var bow_prism := bow_mesh.mesh as PrismMesh
	if bow_prism:
		bow_prism.size = Vector3(
			hull_size.x,
			hull_size.y * 0.9,
			hull_size.x * 1.1
		)
	bow_mesh.position = Vector3(
		0.0,
		hull_size.y * 0.5,
		-hull_size.z * 0.55
	)
	var deck_box := deck_mesh.mesh as BoxMesh
	if deck_box:
		deck_box.size = Vector3(
			hull_size.x * 0.72,
			0.22,
			hull_size.z * 0.52
		)
	deck_mesh.position = Vector3(0.0, hull_size.y + 0.12, 0.12)


func _apply_materials(team_color: Color) -> void:
	hull_mesh.material_override = _make_material(team_color)
	bow_mesh.material_override = hull_mesh.material_override
	deck_mesh.material_override = _make_material(team_color.darkened(0.25))


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	material.metallic = 0.08
	return material

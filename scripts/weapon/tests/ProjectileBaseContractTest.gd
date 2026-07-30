extends SceneTree

const SHELL_SCENE := preload(
	"res://scenes/weapon/projectiles/shell_projectile.tscn"
)
const BOMB_SCENE := preload("res://scenes/weapon/projectile.tscn")
const TORPEDO_SCENE := preload(
	"res://scenes/weapon/projectiles/torpedo_projectile.tscn"
)

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var services := BattleTestServices.create(self)
	var parent := Node3D.new()
	root.add_child(parent)
	for entry in [
		{"name": "shell", "scene": SHELL_SCENE},
		{"name": "bomb", "scene": BOMB_SCENE},
		{"name": "torpedo", "scene": TORPEDO_SCENE},
	]:
		var node := (entry["scene"] as PackedScene).instantiate() as Node3D
		var projectile := node as ProjectileBase
		var rigid_projectile := node as WeaponProjectileBase
		_check(
			projectile != null or rigid_projectile != null,
			"%s root implements the typed projectile contract" % entry["name"]
		)
		if node == null or (projectile == null and rigid_projectile == null):
			continue
		parent.add_child(node)
		var data := ProjectileData.new()
		data.id = "%s_contract" % entry["name"]
		if projectile != null:
			projectile.configure(data, services)
		else:
			rigid_projectile.configure(data, services)
		_check(
			(
				projectile != null
				and projectile.projectile_data == data
				and projectile.battle_services == services
			) or (
				rigid_projectile != null
				and rigid_projectile.projectile_data == data
				and rigid_projectile.battle_services == services
			),
			"%s accepts typed configuration" % entry["name"]
		)
		if projectile != null:
			projectile.source_team = FactionRelations.ENEMY
			projectile.source_weapon_id = &"contract_weapon"
			projectile.reset_for_pool()
		else:
			rigid_projectile.source_team = FactionRelations.ENEMY
			rigid_projectile.source_weapon_id = &"contract_weapon"
			rigid_projectile.linear_velocity = Vector3(1.0, 2.0, 3.0)
			rigid_projectile.reset_for_pool()
		_check(
			(
				projectile != null
				and projectile.projectile_data == null
				and projectile.battle_services == null
				and projectile.source_team == FactionRelations.NEUTRAL
				and projectile.source_weapon_id.is_empty()
			) or (
				rigid_projectile != null
				and rigid_projectile.projectile_data == null
				and rigid_projectile.battle_services == null
				and rigid_projectile.source_team == FactionRelations.NEUTRAL
				and rigid_projectile.source_weapon_id.is_empty()
			),
			"%s clears source and service state for pooling" % entry["name"]
		)
		node.queue_free()
	await process_frame
	parent.queue_free()
	print("PROJECTILE_BASE_CONTRACT_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("PROJECTILE CONTRACT: %s" % label)

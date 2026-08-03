extends SceneTree
## Covers the carrier_secondary -> naval_gun_100mm rename: registry resolve,
## layout defaults, ship resources, and the load-only legacy save alias.

const SHIP_IDS := [
	"dd_bluewind",
	"cl_tidebreaker",
	"bb_ironwake",
	"cv_seabastion",
]
const NEW_WEAPON_ID := "naval_gun_100mm"
const LEGACY_WEAPON_ID := "carrier_secondary"

var _failures := PackedStringArray()
var _weapon_database := WeaponDatabase.new()
var _ship_database := ShipDatabase.new()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_registry_resolves_new_id()
	_test_projectile_renamed()
	_test_layout_default_and_ship_resources()
	_test_legacy_alias_migration()
	_test_new_saves_never_write_the_alias()
	_test_no_stale_references_in_project()
	print("SECONDARY_WEAPON_RENAME_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _test_registry_resolves_new_id() -> void:
	var weapon := _weapon_database.find_weapon(NEW_WEAPON_ID)
	_check(weapon != null, "registry resolves naval_gun_100mm")
	if weapon == null:
		return
	_check(weapon.id == NEW_WEAPON_ID, "WeaponData.id is naval_gun_100mm")
	_check(
		weapon.display_name == "100 mm Naval Gun",
		"display_name is the generic gun name (got '%s')" % weapon.display_name
	)
	_check(
		weapon.mount_scene != null and weapon.projectile_scene != null,
		"renamed weapon still resolves its mount and projectile scenes"
	)
	_check(
		weapon.projectile_data != null,
		"renamed weapon still resolves its ProjectileData"
	)
	_check(
		weapon.gunnery_accuracy_profile != null,
		"renamed weapon keeps its gunnery accuracy profile"
	)
	_check(
		is_equal_approx(weapon.muzzle_velocity, 560.0),
		"100 mm naval gun uses the doubled 560 m/s muzzle velocity"
	)
	_check(
		is_equal_approx(weapon.range_meters, 4500.0),
		"100 mm naval gun range is reduced to 4.5 km"
	)
	_check(
		_weapon_database.find_weapon(LEGACY_WEAPON_ID) == null,
		"the legacy id is no longer a registry key"
	)


func _test_projectile_renamed() -> void:
	var weapon := _weapon_database.find_weapon(NEW_WEAPON_ID)
	if weapon == null or weapon.projectile_data == null:
		_check(false, "projectile data is reachable for the rename check")
		return
	_check(
		weapon.projectile_data.id == "secondary_100mm_shell",
		"projectile id is generalized (got '%s')" % weapon.projectile_data.id
	)
	var shell_data := weapon.projectile_data as ShellProjectileData
	_check(shell_data != null, "secondary projectile uses ShellProjectileData")
	if shell_data == null:
		return
	_check(
		is_equal_approx(shell_data.muzzle_velocity, 560.0),
		"secondary projectile data matches the doubled muzzle velocity"
	)
	_check(
		is_equal_approx(shell_data.trail_lifetime_sec, 0.575)
			and is_equal_approx(shell_data.trail_width_m, 2.5)
			and shell_data.trail_particle_count == 80,
		"secondary trail lifetime, width and particle count are halved"
	)
	_check(
		shell_data.trail_color.r >= 0.9
			and shell_data.trail_color.g >= 0.9
			and shell_data.trail_color.b >= 0.9,
		"secondary trail color is near white"
	)
	var projectile := weapon.projectile_scene.instantiate() as Projectile
	_check(projectile != null, "secondary shell scene instantiates as Projectile")
	if projectile != null:
		root.add_child(projectile)
		var services := BattleTestServices.create(self)
		var configured := projectile.configure(
			shell_data,
			services
		)
		var secondary_trail_mesh := projectile.trail_particles.draw_pass_1 \
			as QuadMesh
		_check(
			configured
				and projectile.trail_particles.amount == 80
				and is_equal_approx(
					projectile.trail_particles.lifetime,
					0.575
				)
				and projectile.trail_color.is_equal_approx(
					shell_data.trail_color
				)
				and secondary_trail_mesh != null
				and secondary_trail_mesh.size.is_equal_approx(
					Vector2(2.5, 2.5)
				),
			"secondary Projectile applies its data-owned trail profile"
		)
		var main_weapon := _weapon_database.find_weapon("destroyer_cannon")
		var main_shell_data := main_weapon.projectile_data as ShellProjectileData \
			if main_weapon != null else null
		projectile.reset_for_pool()
		var main_configured := projectile.configure(main_shell_data, services) \
			if main_shell_data != null else false
		var main_trail_mesh := projectile.trail_particles.draw_pass_1 as QuadMesh
		_check(
			main_configured
				and projectile.trail_particles.amount == 160
				and is_equal_approx(projectile.trail_particles.lifetime, 1.15)
				and main_trail_mesh != null
				and main_trail_mesh.size.is_equal_approx(Vector2(5.0, 5.0))
				and projectile.trail_color.is_equal_approx(
					Color(1.0, 0.66, 0.24, 0.9)
				),
			"pooled Projectile reuse restores the main-gun trail defaults"
		)
		root.remove_child(projectile)
		projectile.free()


func _test_layout_default_and_ship_resources() -> void:
	var layout := SecondaryBatteryLayout.new()
	_check(
		layout.weapon_id == NEW_WEAPON_ID,
		"SecondaryBatteryLayout defaults to the new id"
	)
	for ship_id in SHIP_IDS:
		var ship_data := _ship_database.get_ship(ship_id)
		if ship_data == null or ship_data.secondary_battery_layout == null:
			continue
		_check(
			ship_data.secondary_battery_layout.weapon_id == NEW_WEAPON_ID,
			"%s secondary layout uses the new id" % ship_id
		)
		var slots: Array[ShipWeaponSlotData] = \
			ship_data.secondary_battery_layout.build_slots()
		_check(not slots.is_empty(), "%s builds secondary slots" % ship_id)
		if not slots.is_empty():
			_check(
				slots[0].default_weapon_id == NEW_WEAPON_ID,
				"%s slot default_weapon_id is the new id" % ship_id
			)
			_check(
				slots[0].battery_role == BatteryRole.Type.SECONDARY,
				"%s secondary role still comes from battery_role" % ship_id
			)


func _test_legacy_alias_migration() -> void:
	_check(
		ShipWeaponLoadout.resolve_weapon_id(LEGACY_WEAPON_ID)
			== NEW_WEAPON_ID,
		"the legacy id maps to the new id"
	)
	_check(
		ShipWeaponLoadout.resolve_weapon_id("destroyer_cannon")
			== "destroyer_cannon",
		"unrelated ids pass through untouched"
	)
	var legacy_save := {
		"entries": [
			{"slot_id": "secondary_port_01", "weapon_id": LEGACY_WEAPON_ID},
			{"slot_id": "main_front", "weapon_id": "battleship_cannon"},
		],
	}
	var loadout := ShipWeaponLoadout.from_dictionary(legacy_save)
	_check(
		loadout.get_weapon_id(&"secondary_port_01") == NEW_WEAPON_ID,
		"a Save version 2 entry loads as the new id"
	)
	_check(
		loadout.get_weapon_id(&"main_front") == "battleship_cannon",
		"migration leaves other slots alone"
	)


func _test_new_saves_never_write_the_alias() -> void:
	var legacy_save := {
		"entries": [
			{"slot_id": "secondary_port_01", "weapon_id": LEGACY_WEAPON_ID},
		],
	}
	var round_tripped := ShipWeaponLoadout.from_dictionary(
		legacy_save
	).to_dictionary()
	var serialized := JSON.stringify(round_tripped)
	_check(
		not serialized.contains(LEGACY_WEAPON_ID),
		"re-saving a migrated loadout never writes the alias back"
	)
	_check(
		serialized.contains(NEW_WEAPON_ID),
		"the migrated loadout serializes the new id"
	)


func _test_no_stale_references_in_project() -> void:
	# Guards against a future resource or script reintroducing the old id. The
	# alias table itself is the one intentional exception.
	var offenders := PackedStringArray()
	_scan_directory("res://resources", offenders)
	_scan_directory("res://scenes", offenders)
	_check(
		offenders.is_empty(),
		"no resource or scene still references the legacy id: %s"
			% str(offenders)
	)


func _scan_directory(path: String, offenders: PackedStringArray) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = directory.get_next()
			continue
		var full_path := "%s/%s" % [path, entry]
		if directory.current_is_dir():
			_scan_directory(full_path, offenders)
		elif entry.ends_with(".tres") or entry.ends_with(".tscn"):
			var file := FileAccess.open(full_path, FileAccess.READ)
			if file != null and file.get_as_text().contains(LEGACY_WEAPON_ID):
				offenders.append(full_path)
		entry = directory.get_next()
	directory.list_dir_end()


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("SECONDARY WEAPON RENAME: %s" % label)

extends RefCounted
class_name SquadronLifecycleController

var owner_squadron: AircraftSquadron


func setup(squadron: AircraftSquadron) -> void:
	owner_squadron = squadron


func spawn_aircraft() -> void:
	var data := owner_squadron.squadron_data.aircraft_data
	if data.aircraft_scene == null:
		return
	var count := owner_squadron._requested_aircraft_count \
		if owner_squadron._requested_aircraft_count >= 0 \
		else owner_squadron.squadron_data.aircraft_count
	count = clampi(
		count,
		0,
		maxi(owner_squadron.squadron_data.aircraft_count, 0)
	)
	for index in range(count):
		var aircraft := data.aircraft_scene.instantiate() as AircraftUnit
		if aircraft == null:
			continue
		owner_squadron.add_child(aircraft)
		var offset := calculate_formation_offset(index, count)
		aircraft.global_position = owner_squadron.formation_center \
			+ offset * 0.15
		aircraft.setup(
			data,
			owner_squadron.get_owner_carrier().team,
			offset,
			owner_squadron.battle_services
		)
		aircraft.set_weapon_updates_managed_by_squadron(true)
		owner_squadron.payload_release_coordinator.register_aircraft(
			aircraft
		)
		aircraft.deactivate()
		if not aircraft.destroyed.is_connected(
			owner_squadron._on_aircraft_destroyed
		):
			aircraft.destroyed.connect(
				owner_squadron._on_aircraft_destroyed
			)
		owner_squadron.aircraft_units.append(aircraft)


func calculate_formation_offset(index: int, count: int) -> Vector3:
	var spacing := maxf(
		owner_squadron.squadron_data.formation_spacing_m,
		1.0
	)
	var center_index := float(count - 1) * 0.5
	var lateral := (float(index) - center_index) * spacing
	var depth := absf(float(index) - center_index) * spacing * 0.35
	return Vector3(lateral, 0.0, depth)


func update_launch_sequence(delta: float) -> void:
	if owner_squadron._next_aircraft_to_activate \
			>= owner_squadron.aircraft_units.size():
		return
	owner_squadron._launch_elapsed_sec += delta
	var interval := maxf(
		owner_squadron.squadron_data.launch_interval_sec,
		0.0
	)
	if interval <= 0.0 \
			or owner_squadron._launch_elapsed_sec >= interval:
		owner_squadron._launch_elapsed_sec = 0.0
		activate_next_aircraft()


func activate_next_aircraft() -> void:
	while owner_squadron._next_aircraft_to_activate \
			< owner_squadron.aircraft_units.size():
		var aircraft := owner_squadron.aircraft_units[
			owner_squadron._next_aircraft_to_activate
		]
		owner_squadron._next_aircraft_to_activate += 1
		if is_instance_valid(aircraft):
			aircraft.activate()
			if owner_squadron._next_aircraft_to_activate \
					>= owner_squadron.aircraft_units.size() \
					and not owner_squadron \
						._formation_activated_emitted:
				owner_squadron._formation_activated_emitted = true
				owner_squadron.formation_activated.emit(
					owner_squadron
				)
			return


func release_aircraft() -> void:
	owner_squadron.clear_fighter_targets()
	owner_squadron.cancel_pending_weapon_release()
	for aircraft in owner_squadron.aircraft_units:
		if is_instance_valid(aircraft):
			if aircraft.destroyed.is_connected(
				owner_squadron._on_aircraft_destroyed
			):
				aircraft.destroyed.disconnect(
					owner_squadron._on_aircraft_destroyed
				)
			aircraft.queue_free()
	owner_squadron.aircraft_units.clear()

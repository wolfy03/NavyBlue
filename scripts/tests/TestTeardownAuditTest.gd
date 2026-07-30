extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var fleet := FleetAIController.new()
	fixture.add_child(fleet)
	var active_snapshot := TestTeardownAudit.inspect_subtree(fixture)
	_check(
		int(active_snapshot.get("fleet_ai_count", 0)) == 1,
		"audit detects live fleet AI"
	)
	fleet.shutdown()
	fixture.remove_child(fleet)
	fleet.free()
	var clean_snapshot := TestTeardownAudit.inspect_subtree(fixture)
	_check(
		TestTeardownAudit.is_runtime_clean(clean_snapshot),
		"audit reports clean runtime subtree after shutdown"
	)
	fixture.queue_free()
	await process_frame
	await process_frame
	print("TEST_TEARDOWN_AUDIT_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("TEST TEARDOWN AUDIT: %s" % label)

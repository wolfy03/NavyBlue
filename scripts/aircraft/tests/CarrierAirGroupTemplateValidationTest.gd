extends SceneTree

const AIR_GROUP: CarrierAirGroupData = preload(
	"res://resources/aircraft/air_groups/seabastion_air_group.tres"
)

var _failures: Array[String] = []


func _initialize() -> void:
	_check(
		AIR_GROUP.squadron_templates.size() == 3,
		"Seabastion has three squadron templates"
	)
	var ids: Array[String] = []
	for template in AIR_GROUP.squadron_templates:
		_check(template != null, "squadron template is not null")
		if template == null:
			continue
		_check(
			template.validate().is_empty(),
			"template validates: %s" % template.id
		)
		_check(
			not ids.has(template.id),
			"template id is unique: %s" % template.id
		)
		ids.append(template.id)
	_check(ids.has("basic_bomber_squadron"), "bomber template exists")
	_check(ids.has("basic_fighter_squadron"), "fighter template exists")
	_check(ids.has("basic_torpedo_squadron"), "torpedo bomber template exists")
	_finish()


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	for failure in _failures:
		push_error(
			"CARRIER AIR GROUP TEMPLATE VALIDATION TEST: %s"
			% failure
		)
	print(
		"CARRIER_AIR_GROUP_TEMPLATE_VALIDATION_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)

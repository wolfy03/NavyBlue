extends RefCounted
class_name BattleInitializationResult

var success := false
var error: StringName


static func completed() -> BattleInitializationResult:
	var result := BattleInitializationResult.new()
	result.success = true
	return result


static func failed(error_code: StringName) -> BattleInitializationResult:
	var result := BattleInitializationResult.new()
	result.error = error_code
	return result

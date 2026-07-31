extends RefCounted
class_name AirDroppedTorpedoCreateResult

var success := false
var projectile: TorpedoProjectile
var failure_reason: StringName


static func completed(
		next_projectile: TorpedoProjectile
) -> AirDroppedTorpedoCreateResult:
	var result := AirDroppedTorpedoCreateResult.new()
	result.success = next_projectile != null
	result.projectile = next_projectile
	return result


static func failed(reason: StringName) -> AirDroppedTorpedoCreateResult:
	var result := AirDroppedTorpedoCreateResult.new()
	result.failure_reason = reason
	return result

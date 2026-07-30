extends RefCounted
class_name ShipDamageResolver


static func resolve(request: DamageRequest) -> DamageResult:
	if request == null or request.hit_info == null:
		push_warning("ShipDamageResolver requires a typed DamageRequest.")
		return DamageResult.new()
	var result := DamageResolver.resolve_hit(request.hit_info)
	result.request = request
	return result

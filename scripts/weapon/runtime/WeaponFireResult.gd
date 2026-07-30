extends RefCounted
class_name WeaponFireResult

var fired := false
var projectiles: Array[Node3D] = []
var reason: WeaponFireReadiness.State = WeaponFireReadiness.State.READY

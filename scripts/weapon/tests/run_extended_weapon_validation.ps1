param(
	[string]$GodotBin = "C:\Users\maker\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe"
)

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$tests = @(
	"res://scripts/weapon/tests/CombatVisibilityTest.gd",
	"res://scripts/weapon/tests/ShellBallisticsTest.gd",
	"res://scripts/weapon/tests/ExtendedWeaponSystemTest.gd",
	"res://scripts/weapon/tests/WeaponReadinessTest.gd",
	"res://scripts/weapon/tests/TorpedoXZCollisionTest.gd",
	"res://scripts/weapon/tests/WeaponRuntimeLoadoutTest.gd",
	"res://scripts/world/tests/ResourceDataFlowTest.gd",
	"res://scripts/combat/tests/CombatDamageTest.gd",
	"res://scripts/combat/tests/ProjectileCollisionTest.gd",
	"res://scripts/world/tests/BattleSceneSmokeTest.gd",
	"res://scripts/world/tests/BattleLoopStateTest.gd",
	"res://scripts/world/tests/ReferenceLifetimeSafetyTest.gd"
)

foreach ($test in $tests) {
	Write-Host "Running $test"
	& $GodotBin --headless --path $projectRoot --script $test
	if ($LASTEXITCODE -ne 0) {
		exit $LASTEXITCODE
	}
}

$sceneTests = @(
	"res://scenes/debug/shell_projectile_integration_test.tscn",
	"res://scenes/debug/shell_projectile_physics_frame_test.tscn"
)

foreach ($scene in $sceneTests) {
	Write-Host "Running $scene"
	& $GodotBin --headless --path $projectRoot $scene
	if ($LASTEXITCODE -ne 0) {
		exit $LASTEXITCODE
	}
}

Write-Host "Extended weapon validation passed."

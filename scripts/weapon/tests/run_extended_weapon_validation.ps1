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
	"res://scripts/weapon/tests/WeaponTeamInitializationTest.gd",
	"res://scripts/world/tests/ResourceDataFlowTest.gd",
	"res://scripts/world/tests/StageDataDefaultsTest.gd",
	"res://scripts/world/tests/StageTestIsolationTest.gd",
	"res://scripts/combat/tests/CombatDamageTest.gd",
	"res://scripts/combat/tests/ProjectileCollisionTest.gd",
	"res://scripts/world/tests/BattleSceneSmokeTest.gd",
	"res://scripts/world/tests/BattleLoopStateTest.gd",
	"res://scripts/world/tests/ReferenceLifetimeSafetyTest.gd",
	"res://scripts/aircraft/tests/CarrierAircraftSystemTest.gd",
	"res://scripts/aircraft/tests/CarrierAircraftStrikeTest.gd",
	"res://scripts/aircraft/tests/SquadronRuntimeStateTest.gd",
	"res://scripts/aircraft/tests/CarrierAirGroupRuntimeTest.gd",
	"res://scripts/aircraft/tests/CarrierAirGroupSaveRestoreTest.gd",
	"res://scripts/aircraft/tests/CarrierAirGroupAITest.gd",
	"res://scripts/aircraft/tests/CarrierAirGroupAIActivationTest.gd",
	"res://scripts/aircraft/tests/CarrierAirGroupAILaunchTest.gd",
	"res://scripts/aircraft/tests/CarrierAirGroupSetupLifecycleTest.gd",
	"res://scripts/aircraft/tests/CarrierLossResolutionTest.gd",
	"res://scripts/aircraft/tests/CarrierBattleEndIdempotencyTest.gd",
	"res://scripts/aircraft/tests/CarrierSaveMigrationTest.gd",
	"res://scripts/aircraft/tests/CarrierCommandAuthorityTest.gd",
	"res://scripts/aircraft/tests/CarrierCommandControllerTest.gd",
	"res://scripts/aircraft/tests/CarrierBattleEndResolutionTest.gd"
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
	"res://scenes/debug/shell_projectile_physics_frame_test.tscn",
	"res://scenes/debug/shell_ship_impact_effect_test.tscn",
	"res://scenes/debug/torpedo_impact_effect_test.tscn"
)

foreach ($scene in $sceneTests) {
	Write-Host "Running $scene"
	& $GodotBin --headless --path $projectRoot $scene
	if ($LASTEXITCODE -ne 0) {
		exit $LASTEXITCODE
	}
}

Write-Host "Extended weapon validation passed."

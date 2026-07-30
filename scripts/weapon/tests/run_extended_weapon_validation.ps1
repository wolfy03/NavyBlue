param(
	[string]$GodotBin = "C:\Users\maker\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe"
)

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$originalAppData = $env:APPDATA
$testAppData = Join-Path `
	([System.IO.Path]::GetTempPath()) `
	("NavyBlueGodotTests_" + [guid]::NewGuid().ToString("N"))

New-Item -ItemType Directory -Path $testAppData -Force | Out-Null
$env:APPDATA = $testAppData

$tests = @(
	"res://scripts/weapon/tests/CombatVisibilityTest.gd",
	"res://scripts/weapon/tests/ProjectileBaseContractTest.gd",
	"res://scripts/weapon/tests/ShellBallisticsTest.gd",
	"res://scripts/weapon/tests/ExtendedWeaponSystemTest.gd",
	"res://scripts/weapon/tests/WeaponReadinessTest.gd",
	"res://scripts/weapon/tests/TorpedoXZCollisionTest.gd",
	"res://scripts/weapon/tests/WeaponRuntimeLoadoutTest.gd",
	"res://scripts/weapon/tests/WeaponTeamInitializationTest.gd",
	"res://scripts/world/tests/ResourceDataFlowTest.gd",
	"res://scripts/world/tests/StageDataDefaultsTest.gd",
	"res://scripts/world/tests/StageTestIsolationTest.gd",
	"res://scripts/world/tests/MainMenuCarrierFlowTest.gd",
	"res://scripts/world/tests/PlayerShipResolutionTest.gd",
	"res://scripts/world/tests/StageDataNoPlayerShipTypeTest.gd",
	"res://scripts/battle/tests/BattleServicesTypedAdapterTest.gd",
	"res://scripts/battle/tests/NoDomainRootAutoloadLookupTest.gd",
	"res://scripts/battle/tests/ResourceValidationImmutabilityTest.gd",
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
	"res://scripts/aircraft/tests/CollaboratorSetupTwiceTest.gd",
	"res://scripts/aircraft/tests/CarrierLossResolutionTest.gd",
	"res://scripts/aircraft/tests/CarrierBattleEndIdempotencyTest.gd",
	"res://scripts/aircraft/tests/CarrierSaveMigrationTest.gd",
	"res://scripts/aircraft/tests/CarrierCommandAuthorityTest.gd",
	"res://scripts/aircraft/tests/CarrierCommandControllerTest.gd",
	"res://scripts/aircraft/tests/CarrierBattleEndResolutionTest.gd",
	"res://scripts/aircraft/tests/FighterCombatDataTest.gd",
	"res://scripts/aircraft/tests/FighterFiringConeTest.gd",
	"res://scripts/aircraft/tests/FighterAccuracyTest.gd",
	"res://scripts/aircraft/tests/FighterBurstResolutionTest.gd",
	"res://scripts/aircraft/tests/FighterCombatControllerTest.gd",
	"res://scripts/aircraft/tests/InterceptMissionBehaviorTest.gd",
	"res://scripts/aircraft/tests/AircraftCombatCoordinatorTest.gd",
	"res://scripts/aircraft/tests/CarrierFighterLaunchTest.gd",
	"res://scripts/aircraft/tests/CarrierFighterAITest.gd",
	"res://scripts/aircraft/tests/FighterLossIntegrationTest.gd",
	"res://scripts/aircraft/tests/DiveBombAttackControllerTest.gd",
	"res://scripts/aircraft/tests/DiveBombPartialSquadronReleaseTest.gd",
	"res://scripts/aircraft/tests/PlayerMissionCancellationTest.gd",
	"res://scripts/aircraft/tests/CarrierAirGroupPanelRoleTest.gd",
	"res://scripts/aircraft/tests/CarrierAirGroupTemplateValidationTest.gd",
	"res://scripts/aircraft/tests/DiveAircraftDirectFlightTest.gd",
	"res://scripts/aircraft/tests/DiveBombNoFormationRequirementTest.gd",
    "res://scripts/aircraft/tests/DiveBombReleaseRetryTest.gd",
    "res://scripts/aircraft/tests/DiveBombReleaseCancellationTest.gd",
    "res://scripts/aircraft/tests/DiveBombReleaseAircraftDestroyedTest.gd",
    "res://scripts/aircraft/tests/DiveBombNullAircraftReleaseResultTest.gd",
    "res://scripts/aircraft/tests/DiveBombReleaseRequestTimeoutTest.gd",
    "res://scripts/aircraft/tests/DiveBombNoTorpedoWeaponTest.gd",
    "res://scripts/aircraft/tests/DiveBombTargetPassMarginTest.gd",
    "res://scripts/aircraft/tests/DiveBombNoSourceBeginTest.gd",
    "res://scripts/aircraft/tests/DiveBombDestinationSerialTest.gd",
    "res://scripts/aircraft/tests/DiveBombAdditionalRetryCountTest.gd",
    "res://scripts/aircraft/tests/DiveBombReleaseSignalSemanticsTest.gd",
    "res://scripts/aircraft/tests/DiveBombPullOutRatioTest.gd",
    "res://scripts/aircraft/tests/DiveBombMissionDestinationStateTest.gd",
	"res://scripts/aircraft/tests/DiveBombAIApproachRepathTest.gd",
	"res://scripts/aircraft/tests/AircraftLoiterTest.gd",
	"res://scripts/input/tests/AircraftSelectionControllerTest.gd",
	"res://scripts/input/tests/AircraftDragSelectionIntegrationTest.gd",
	"res://scripts/input/tests/AircraftSelectionCandidateReasonTest.gd",
	"res://scripts/input/tests/CommandModeToggleTest.gd"
)

try {
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
}
finally {
	$env:APPDATA = $originalAppData
}

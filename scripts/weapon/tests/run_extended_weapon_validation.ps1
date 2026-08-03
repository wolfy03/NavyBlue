param(
	[string]$GodotBin = "C:\Users\maker\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe"
)

. (Join-Path $PSScriptRoot "GodotOutputPolicy.ps1")

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
	"res://scripts/weapon/tests/ProjectileLifecycleServiceTest.gd",
	"res://scripts/weapon/tests/ProjectileLifecycleStateTest.gd",
	"res://scripts/weapon/tests/ProjectileFallbackOwnershipTest.gd",
	"res://scripts/weapon/tests/ProjectileCreationAtomicCleanupTest.gd",
	"res://scripts/weapon/tests/ShellBallisticsTest.gd",
	"res://scripts/weapon/tests/ExtendedWeaponSystemTest.gd",
	"res://scripts/weapon/tests/WeaponReadinessTest.gd",
	"res://scripts/weapon/tests/NavalGunLeadResolverTest.gd",
	"res://scripts/weapon/tests/GunneryAccuracyResolverTest.gd",
	"res://scripts/weapon/tests/GunnerySalvoStructureTest.gd",
	"res://scripts/weapon/tests/AIGunneryFireControlIntegrationTest.gd",
	"res://scripts/weapon/tests/AIGunneryDifficultyResourceSelectionTest.gd",
	"res://scripts/weapon/tests/GunneryProfileValidationTest.gd",
	"res://scripts/weapon/tests/GunneryWeaponAccuracyProfileSelectionTest.gd",
	"res://scripts/weapon/tests/GunneryAccuracyStatisticalTest.gd",
	"res://scripts/weapon/tests/AIGunnerySameTargetAssignmentTest.gd",
	"res://scripts/weapon/tests/GunnerySalvoIndexLifecycleTest.gd",
	"res://scripts/weapon/tests/GunneryFreedMountCleanupTest.gd",
	"res://scripts/weapon/tests/PlayerAutoDoesNotUseAIDifficultyTest.gd",
	"res://scripts/weapon/tests/GunneryTrackingConfidenceDropOnManeuverTest.gd",
	"res://scripts/weapon/tests/TorpedoXZCollisionTest.gd",
	"res://scripts/unit/tests/TorpedoCollisionMarginShapeTest.gd",
	"res://scripts/weapon/tests/AirDroppedTorpedoLifecycleTest.gd",
	"res://scripts/weapon/tests/AirDroppedTorpedoPredictionAgreementTest.gd",
	"res://scripts/weapon/tests/WeaponRuntimeLoadoutTest.gd",
	"res://scripts/weapon/tests/WeaponTeamInitializationTest.gd",
	"res://scripts/world/tests/ResourceDataFlowTest.gd",
	"res://scripts/world/tests/StageDataDefaultsTest.gd",
	"res://scripts/world/tests/StageTestIsolationTest.gd",
	"res://scripts/world/tests/MainMenuCarrierFlowTest.gd",
	"res://scripts/world/tests/PlayerShipResolutionTest.gd",
	"res://scripts/world/tests/StageDataNoPlayerShipTypeTest.gd",
	"res://scripts/battle/tests/BattleServicesTypedAdapterTest.gd",
	"res://scripts/battle/tests/BattleServicesDependencyTest.gd",
	"res://scripts/battle/tests/BattleServicesAtomicSetupTest.gd",
	"res://scripts/battle/tests/NoDomainRootAutoloadLookupTest.gd",
	"res://scripts/battle/tests/ResourceValidationImmutabilityTest.gd",
	"res://scripts/combat/tests/CombatDamageTest.gd",
	"res://scripts/combat/tests/ProjectileCollisionTest.gd",
	"res://scripts/effects/tests/PooledEffectContractTest.gd",
	"res://scripts/effects/tests/PooledEffectCoverageAuditTest.gd",
	"res://scripts/effects/tests/EffectPresenterPassiveTest.gd",
	"res://scripts/tests/TestTeardownAuditTest.gd",
	"res://scripts/world/tests/BattleSceneSmokeTest.gd",
	"res://scripts/world/tests/BattleSceneShutdownIdempotenceTest.gd",
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
	"res://scripts/aircraft/tests/TorpedoAttackCommandResolverTest.gd",
	"res://scripts/aircraft/tests/TorpedoAttackTargetingSessionTest.gd",
	"res://scripts/aircraft/tests/TorpedoAttackPerAircraftReleaseTest.gd",
	"res://scripts/aircraft/tests/TorpedoAttackLifecyclePolicyTest.gd",
	"res://scripts/aircraft/tests/TorpedoReleaseServicePolicyTest.gd",
	"res://scripts/aircraft/tests/TorpedoAttackAIPlannerIntegrationTest.gd",
	"res://scripts/aircraft/tests/DiveBombAITargetDestroyedBeforeReleaseTest.gd",
	"res://scripts/aircraft/tests/AircraftLoiterTest.gd",
	"res://scripts/input/tests/AircraftSelectionControllerTest.gd",
	"res://scripts/input/tests/AircraftDragSelectionIntegrationTest.gd",
	"res://scripts/input/tests/AircraftSelectionCandidateReasonTest.gd",
	"res://scripts/input/tests/CommandModeToggleTest.gd",
	"res://scripts/input/tests/CommandModeFocusPolicyTest.gd",
	"res://scripts/combat/tests/ManualAimRelativeBearingTest.gd",
	"res://scripts/aircraft/tests/AircraftCommandPresentationTest.gd",
	"res://scripts/ai/tests/AIDifficultyEffectiveIntervalTest.gd",
	"res://scripts/ai/tests/FleetAIEvaluationCadenceTest.gd",
	"res://scripts/ai/tests/FleetRoleSuitabilityPolicyTest.gd",
	"res://scripts/ai/tests/EmergencyInterceptorPolicyTest.gd",
	"res://scripts/tests/endurance/EnduranceProfileDefinitionTest.gd",
	"res://scripts/tests/endurance/EnduranceChunkCountConsistencyTest.gd",
	"res://scripts/tests/endurance/PoolMetricSemanticsTest.gd",
	"res://scripts/tests/endurance/NightlyResultContractTest.gd"
)

try {
	& (Join-Path $PSScriptRoot "GodotOutputPolicyTest.ps1")
	foreach ($test in $tests) {
		Write-Host "Running $test"
		Invoke-GodotChecked -GodotBin $GodotBin -Arguments @(
			"--headless",
			"--path",
			$projectRoot.Path,
			"--script",
			$test
		)
	}

	$sceneTests = @(
		"res://scenes/debug/shell_projectile_integration_test.tscn",
		"res://scenes/debug/shell_projectile_physics_frame_test.tscn",
		"res://scenes/debug/shell_ship_impact_effect_test.tscn",
		"res://scenes/debug/torpedo_impact_effect_test.tscn"
	)

	foreach ($scene in $sceneTests) {
		Write-Host "Running $scene"
		Invoke-GodotChecked -GodotBin $GodotBin -Arguments @(
			"--headless",
			"--path",
			$projectRoot.Path,
			$scene
		)
	}

	Write-Host "Extended weapon validation passed."
}
finally {
	$env:APPDATA = $originalAppData
}

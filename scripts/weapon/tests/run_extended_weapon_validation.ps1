param(
	[string]$GodotBin = "C:\Users\maker\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe"
)

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$tests = @(
	"res://scripts/weapon/tests/ExtendedWeaponSystemTest.gd",
	"res://scripts/world/tests/ResourceDataFlowTest.gd",
	"res://scripts/combat/tests/CombatDamageTest.gd",
	"res://scripts/combat/tests/ProjectileCollisionTest.gd",
	"res://scripts/world/tests/BattleSceneSmokeTest.gd"
)

foreach ($test in $tests) {
	Write-Host "Running $test"
	& $GodotBin --headless --path $projectRoot --script $test
	if ($LASTEXITCODE -ne 0) {
		exit $LASTEXITCODE
	}
}

Write-Host "Extended weapon validation passed."

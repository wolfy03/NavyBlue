param(
	[string]$GodotBin = $env:GODOT_BIN,
	[int]$Frames = 600,
	[switch]$IncludeFleetLongRun
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($GodotBin)) {
	throw "Set GODOT_BIN or pass -GodotBin with the Godot 4.7 console executable."
}

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "../../..")
$env:NAVYBLUE_ENDURANCE_FRAMES = [string][Math]::Max($Frames, 1)

& $GodotBin `
	--headless `
	--path $projectRoot `
	--script res://scripts/tests/endurance/BattleEnduranceSmokeTest.gd

if ($LASTEXITCODE -ne 0) {
	exit $LASTEXITCODE
}

if ($IncludeFleetLongRun) {
	$env:NAVYBLUE_LONG_RUN_FRAMES = [string][Math]::Max($Frames, 1)
	& $GodotBin `
		--headless `
		--fixed-fps 60 `
		--path $projectRoot `
		--script res://scripts/ai/tests/FleetAI6v6LongRunTest.gd
	exit $LASTEXITCODE
}

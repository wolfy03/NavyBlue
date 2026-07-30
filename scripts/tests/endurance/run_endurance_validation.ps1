param(
	[string]$GodotBin = $env:GODOT_BIN,
	[int]$Frames = 1800,
	[switch]$IncludeExtendedProfiles,
	[switch]$IncludeNightly
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

if ($IncludeExtendedProfiles) {
	$env:NAVYBLUE_LONG_RUN_FRAMES = [string][Math]::Max($Frames, 1)
	& $GodotBin `
		--headless `
		--fixed-fps 60 `
		--path $projectRoot `
		--script res://scripts/ai/tests/FleetAI6v6LongRunTest.gd
	if ($LASTEXITCODE -ne 0) {
		exit $LASTEXITCODE
	}

	$env:NAVYBLUE_LONG_RUN_FRAMES = "9000"
	foreach ($seed in @(1, 2)) {
		$env:NAVYBLUE_ENDURANCE_SEED = [string]$seed
		& $GodotBin `
			--headless `
			--fixed-fps 60 `
			--path $projectRoot `
			--script res://scripts/ai/tests/FleetAI10v10LongRunTest.gd
		if ($LASTEXITCODE -ne 0) {
			exit $LASTEXITCODE
		}
	}
	& $GodotBin `
		--headless `
		--fixed-fps 60 `
		--path $projectRoot `
		--script res://scripts/ai/tests/BattleAILongRunTest.gd
	if ($LASTEXITCODE -ne 0) {
		exit $LASTEXITCODE
	}
}

if ($IncludeNightly) {
	$env:NAVYBLUE_LONG_RUN_FRAMES = "36000"
	$env:NAVYBLUE_ENDURANCE_SEED = "1"
	& $GodotBin `
		--headless `
		--fixed-fps 60 `
		--path $projectRoot `
		--script res://scripts/ai/tests/FleetAI6v6LongRunTest.gd
	exit $LASTEXITCODE
}

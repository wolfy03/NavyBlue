param(
	[string]$GodotBin = $env:GODOT_BIN,
	[switch]$IncludeLongRun
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($GodotBin)) {
	foreach ($candidate in @("godot4", "godot")) {
		$command = Get-Command $candidate -ErrorAction SilentlyContinue
		if ($null -ne $command) {
			$GodotBin = $command.Source
			break
		}
	}
}

if ([string]::IsNullOrWhiteSpace($GodotBin)) {
	throw "Set GODOT_BIN or pass -GodotBin with a Godot 4.7 console executable."
}

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "../../..")
$tests = @(
	"res://scripts/ai/tests/ThreatTargetingSystemTest.gd",
	"res://scripts/ai/tests/FleetAIArchitectureTest.gd",
	"res://scripts/ai/tests/FleetAIStage3Test.gd",
	"res://scripts/ai/tests/FleetAIStabilizationTest.gd"
)

if ($IncludeLongRun) {
	$tests += "res://scripts/ai/tests/FleetAI6v6LongRunTest.gd"
}

& $GodotBin --headless --path $projectRoot --editor --quit
if ($LASTEXITCODE -ne 0) {
	exit $LASTEXITCODE
}

foreach ($test in $tests) {
	if ($test -eq "res://scripts/ai/tests/FleetAI6v6LongRunTest.gd") {
		# 36,000 frames at 60 Hz represents ten minutes of battle simulation.
		& $GodotBin --headless --fixed-fps 60 --path $projectRoot --script $test
	} else {
		& $GodotBin --headless --path $projectRoot --script $test
	}
	if ($LASTEXITCODE -ne 0) {
		exit $LASTEXITCODE
	}
}

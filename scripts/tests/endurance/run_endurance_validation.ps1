param(
	[string]$GodotBin = $env:GODOT_BIN,
	[ValidateSet("smoke", "extended_smoke", "6v6", "10v10", "battle_ai")]
	[string]$Profile = "smoke",
	[int]$Frames = 0,
	[int]$Seed = 1,
	[string]$OutputPath = "",
	[int]$TimeoutSeconds = 1800
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($GodotBin)) {
	throw "Set GODOT_BIN or pass -GodotBin with the Godot 4.7 console executable."
}

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "../../..")
$defaultFrames = @{
	"smoke" = 600
	"extended_smoke" = 1800
	"6v6" = 9000
	"10v10" = 9000
	"battle_ai" = 9000
}
$resolvedFrames = if ($Frames -gt 0) { $Frames } else { $defaultFrames[$Profile] }
$dateDirectory = Get-Date -Format "yyyy-MM-dd"
$artifactDirectory = if ([string]::IsNullOrWhiteSpace($OutputPath)) {
	Join-Path $projectRoot "artifacts/endurance/$dateDirectory"
} elseif ([IO.Path]::GetExtension($OutputPath) -eq ".json") {
	Split-Path -Parent $OutputPath
} else {
	$OutputPath
}
if ([string]::IsNullOrWhiteSpace($artifactDirectory)) {
	$artifactDirectory = "."
}
New-Item -ItemType Directory -Force -Path $artifactDirectory | Out-Null
$resultPath = if ([IO.Path]::GetExtension($OutputPath) -eq ".json") {
	$OutputPath
} else {
	Join-Path $artifactDirectory "$Profile-seed-$Seed.json"
}
$logPath = [IO.Path]::ChangeExtension($resultPath, ".log")

$scriptPath = switch ($Profile) {
	"smoke" { "res://scripts/tests/endurance/BattleEnduranceSmokeTest.gd" }
	"extended_smoke" { "res://scripts/tests/endurance/BattleEnduranceSmokeTest.gd" }
	"6v6" { "res://scripts/ai/tests/FleetAI6v6LongRunTest.gd" }
	"10v10" { "res://scripts/ai/tests/FleetAI10v10LongRunTest.gd" }
	"battle_ai" { "res://scripts/ai/tests/BattleAILongRunTest.gd" }
}

$env:NAVYBLUE_ENDURANCE_PROFILE = $Profile
$env:NAVYBLUE_ENDURANCE_FRAMES = [string]$resolvedFrames
$env:NAVYBLUE_LONG_RUN_FRAMES = [string]$resolvedFrames
$env:NAVYBLUE_ENDURANCE_SEED = [string]$Seed
if ($Profile -in @("smoke", "extended_smoke")) {
	$env:NAVYBLUE_ENDURANCE_OUTPUT_PATH = $resultPath
} else {
	$env:NAVYBLUE_ENDURANCE_OUTPUT_PATH = ""
}

$arguments = @(
	"--headless",
	"--fixed-fps", "60",
	"--path", $projectRoot,
	"--script", $scriptPath
)
$processInfo = [Diagnostics.ProcessStartInfo]::new()
$processInfo.FileName = $GodotBin
$processInfo.UseShellExecute = $false
$processInfo.RedirectStandardOutput = $true
$processInfo.RedirectStandardError = $true
$processInfo.Arguments = (($arguments | ForEach-Object {
	'"' + ([string]$_).Replace('"', '\"') + '"'
}) -join " ")
$process = [Diagnostics.Process]::new()
$process.StartInfo = $processInfo
$null = $process.Start()
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
if (-not $process.WaitForExit([Math]::Max($TimeoutSeconds, 1) * 1000)) {
	$process.Kill()
	@{
		profile = $Profile
		frames = $resolvedFrames
		seed = $Seed
		success = $false
		error = "timeout"
		metrics = @{}
	} | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 $resultPath
	exit 124
}
$stdout = $stdoutTask.Result
$stderr = $stderrTask.Result
($stdout + [Environment]::NewLine + $stderr) | Set-Content -Encoding utf8 $logPath
Write-Output $stdout
if (-not [string]::IsNullOrWhiteSpace($stderr)) {
	Write-Error $stderr -ErrorAction Continue
}

$forbiddenLogPattern = "ObjectDB instances leaked|resources still in use|ERROR:"
$logFailure = ($stdout + $stderr) -match $forbiddenLogPattern
if ($Profile -notin @("smoke", "extended_smoke")) {
	$summaryLine = [string](($stdout -split "`r?`n") | Where-Object {
		$_ -match "FLEET_AI_|AI_LONG_RUN|BATTLE_ENDURANCE"
	} | Select-Object -Last 1)
	$summaryMissing = [string]::IsNullOrWhiteSpace($summaryLine)
	$runSuccess = $process.ExitCode -eq 0 `
		-and -not $logFailure `
		-and -not $summaryMissing
	@{
		profile = $Profile
		frames = $resolvedFrames
		seed = $Seed
		success = $runSuccess
		metrics = @{
			summary = $summaryLine
		}
	} | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 $resultPath
}

if ($process.ExitCode -ne 0 -or $logFailure -or -not (Test-Path $resultPath)) {
	exit $(if ($process.ExitCode -ne 0) { $process.ExitCode } else { 1 })
}
try {
	$result = Get-Content -Raw $resultPath | ConvertFrom-Json
} catch {
	exit 2
}
if (-not $result.success) {
	exit 3
}
exit 0

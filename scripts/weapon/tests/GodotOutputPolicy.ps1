$GodotForbiddenPatterns = @(
	'SCRIPT ERROR',
	'Trying to cast a freed object',
	'Invalid call',
	'Invalid get index',
	'Attempt to call function',
	'Previously freed instance',
	'Parser Error',
	'Compile Error: Failed to compile',
	'ERROR:'
)


function Test-GodotOutputAllowed {
	param(
		[int]$ExitCode,
		[string]$Output
	)

	if ($ExitCode -ne 0) {
		return $false
	}
	foreach ($pattern in $GodotForbiddenPatterns) {
		if ($Output.IndexOf(
			$pattern,
			[System.StringComparison]::OrdinalIgnoreCase
		) -ge 0) {
			return $false
		}
	}
	return $true
}


function Invoke-GodotChecked {
	param(
		[Parameter(Mandatory = $true)]
		[string]$GodotBin,
		[Parameter(Mandatory = $true)]
		[string[]]$Arguments
	)

	$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
	$startInfo.FileName = $GodotBin
	$startInfo.UseShellExecute = $false
	$startInfo.RedirectStandardOutput = $true
	$startInfo.RedirectStandardError = $true
	$startInfo.CreateNoWindow = $true
	$quotedArguments = foreach ($argument in $Arguments) {
		'"{0}"' -f $argument.Replace('"', '\"')
	}
	$startInfo.Arguments = $quotedArguments -join ' '

	$process = [System.Diagnostics.Process]::new()
	$process.StartInfo = $startInfo
	if (-not $process.Start()) {
		throw 'Godot process could not be started.'
	}
	$stdoutTask = $process.StandardOutput.ReadToEndAsync()
	$stderrTask = $process.StandardError.ReadToEndAsync()
	$process.WaitForExit()
	$stdout = $stdoutTask.GetAwaiter().GetResult()
	$stderr = $stderrTask.GetAwaiter().GetResult()
	$combined = $stdout + $stderr
	if (-not [string]::IsNullOrWhiteSpace($stdout)) {
		Write-Host $stdout.TrimEnd()
	}
	if (-not [string]::IsNullOrWhiteSpace($stderr)) {
		Write-Host $stderr.TrimEnd()
	}
	if (-not (Test-GodotOutputAllowed $process.ExitCode $combined)) {
		throw (
			'Godot validation failed (exit code {0}).' -f $process.ExitCode
		)
	}
}

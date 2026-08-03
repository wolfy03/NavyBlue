. (Join-Path $PSScriptRoot 'GodotOutputPolicy.ps1')

if (-not (Test-GodotOutputAllowed 0 'normal test output')) {
	throw 'Normal output was rejected.'
}
if (Test-GodotOutputAllowed 1 'normal test output') {
	throw 'A non-zero process exit was accepted.'
}
foreach ($pattern in $GodotForbiddenPatterns) {
	if (Test-GodotOutputAllowed 0 ("prefix {0} suffix" -f $pattern)) {
		throw ("Forbidden Godot output was accepted: {0}" -f $pattern)
	}
}

Write-Host 'Godot output policy self-test passed.'

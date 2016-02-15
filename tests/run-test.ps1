Import-Module '.\task\ps_modules\VstsTaskSdk'

$env:INPUT_BUILDFILE = '.\tests\build-script.ps1'
$env:INPUT_TASKS = 'LogScript, LogFramework, LogProperties'
$env:INPUT_PARAMETERS = "p1 = v1, p2 = v2 `r`n p3=v3=true,p4=v4 = false "
$env:INPUT_PROPERTIES = " overridableProperty = overriden "
$env:INPUT_FRAMEWORK = '4.5.2'
$env:INPUT_NOLOGO = 'true'

Invoke-VstsTaskScript -ScriptBlock ([scriptblock]::Create('. .\task\psake.ps1'))
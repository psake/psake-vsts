[CmdletBinding()]
param()

Function _ExpandToArray {
    param(
        [string] $Value
    )
    
    if (!$Value) {
        return @()
    }
    
    $Value.Split(',').Trim()
}

Function _ExpandToHashtable {
    param(
        [string] $Value
    )

    if (!$Value) {
        return @{}
    }

    $hash = @{}
    $Value -split "[`r`n]|," | ? { $_ } | % {
        $items = $_.Split('=', 2).Trim()
        if ($items.Length -ne 2) {
            Write-Warning "Cannot parse parameter or property '${_}'."
   
            return
        }

        $hash[$items[0]] = $items[1]
    }

    $hash
}

Trace-VstsEnteringInvocation $MyInvocation

try {
    # get inputs
    [string] $buildFile = Get-VstsInput -Name BuildFile -Require
    [string] $inputTasks = Get-VstsInput -Name Tasks
    [string] $inputParameters = Get-VstsInput -Name Parameters
    [string] $inputProperties = Get-VstsInput -Name Properties
    [string] $framework = Get-VstsInput -Name Framework
    [bool] $noLogo = Get-VstsInput -Name NoLogo -AsBool

    $PSBoundParameters.Keys | % { Write-Verbose "${_} = $($PSBoundParameters[$_])" }

    # validate inputs
    if (!(Test-Path $buildFile))
    {
        Write-Error "Build script '${buildFile}' not found."
    }

    # expand inputs
    $tasks = _ExpandToArray $inputTasks
    $parameters = _ExpandToHashtable $inputParameters
    $properties = _ExpandToHashtable $inputProperties
    
    if ($framework -eq 'default')
    {
        $framework = $null
    } 

    # invoke script
    Import-Module -Name $PSScriptRoot\ps_modules\psake\psake.psm1
    Invoke-psake -buildFile $buildFile -taskList $tasks -parameters $parameters -properties $properties -framework $framework -nologo:$noLogo

    Write-Verbose "build_success: $($psake.build_success)"
    if (!$psake.build_success)
    {
        Write-Error "Invoke-psake exited with build_success '$($psake.build_success)'."
    }
}
finally
{
    Trace-VstsLeavingInvocation $MyInvocation
}
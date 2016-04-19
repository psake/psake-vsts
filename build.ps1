Properties {
    $srcPath = Split-Path $psake.build_script_file
    $buildPath = Join-Path $srcPath '_build'
    $packagesPath = Join-Path $srcPath '_packages'
    $publisher = $null
    $token = $null
    $shareWith = $null
}

FormatTaskName { Write-Host (('-' * 5) + "[${taskName}]" + ('-' * (63 - $taskName.Length))) -ForegroundColor Magenta }

Task Default -Depends Build

Task Build -Depends Clean {
    # copy extension files
    Copy-Item -Path (Join-Path $srcPath 'docs') -Destination (Join-Path $buildPath 'docs') -Recurse
    Copy-Item -Path (Join-Path $srcPath 'images') -Destination (Join-Path $buildPath 'images') -Recurse
    Copy-Item -Path (Join-Path $srcPath 'LICENSE.txt') -Destination $buildPath
    Copy-Item -Path (Join-Path $srcPath 'vss-extension.json') -Destination $buildPath
    
    # copy task files
    Copy-Item -Path (Join-Path $srcPath 'task') -Destination (Join-Path $buildPath 'task') -Recurse
    
    # copy librairies files
    $libPath = Join-Path $srcPath 'node_modules\vsts-task-sdk\VstsTaskSdk'
    if (!(Test-Path $libPath))
    {
        throw "Directory '${libPath}' not found."
    }
    
    Copy-Item -Path $libPath -Destination (Join-Path $buildPath 'task\ps_modules\VstsTaskSdk') -Recurse
}

Task Clean {
    if (Test-Path $buildPath)
    {
        Write-Host "Deleting folder '${buildPath}'..."
        Remove-Item -Path $buildPath -Recurse -Force > $null
    }
}

Task UpdateBuildNumber {
    # set build number to extension version
    $path = Join-Path $buildPath 'vss-extension.json'
    $metadata = Get-Content $path -Raw | ConvertFrom-Json
    
    Write-Host "##vso[build.updatebuildnumber]psake-extension_$($metadata.version)+${env:BUILD_BUILDID}"
    Write-Host "##vso[task.setvariable variable=Extension.Version;]$($metadata.version)"
}

Task PublishDev {
    # check for build directory
    if (!(Test-Path $buildPath))
    {
        throw "Directory '${buildPath}' not found."
    }
    
    # generate unique version:
    #  - major: 0
    #  - minor: number of days since 2000-01-01
    #  - patch: number of seconds since midnight divided by 2
    $ref = New-Object DateTime 2000,1,1
    $now = [DateTime]::UtcNow
    $major = 0
    $minor = $now.Subtract($ref).Days
    $patch = [Math]::Floor([Math]::Floor($now.TimeOfDay.TotalSeconds) * 0.5)
    $version = "${major}.${minor}.${patch}"
    
    # update metadata
    _UpdateExtensionMetaData -IdTag '-dev' -NameTag ' (dev)' -Version $version
    _UpdateTaskMetadata -Id '7011cf27-c181-443a-9f07-3e6ffea72b6b' -NameTag '-dev' -FriendlyNameTag " (dev ${version})" -Version $version
    
    # publish extension
    _PublishExtension
}

Function _UpdateExtensionMetaData
{
    param(
        [string] $IdTag,
        [string] $NameTag,
        [string] $Version,
        [switch] $Public
    )
    
    $path = Join-Path $buildPath 'vss-extension.json'
    $metadata = Get-Content $path -Raw | ConvertFrom-Json
    
    Write-Host "Adding tag '${IdTag}' to extension id..."
    $metadata.id = $metadata.id -replace '#{IdTag}',$IdTag
    
    Write-Host "Adding tag '${NameTag}' to extension name..."
    $metadata.name = $metadata.name -replace '#{NameTag}',$NameTag
    
    Write-Host "Updating extension version to '${Version}'..."
    $metadata.version = $Version

    if (!$Public -and $metadata.public)
    {
        Write-Host 'Removing extension public flag...'
        $metadata = $metadata | Select-Object -Property * -ExcludeProperty 'public'
    }
    
    if ($Public -and !$metadata.public)
    {
        Write-Host 'Adding extension public flag...'
        Add-Member -InputObject $metadata -NotePropertyName "public" -NotePropertyValue $true -Force
    }
    
    Write-Host "Updating extension file '${path}'..."
    ConvertTo-Json $metadata -Depth 20 | Out-File $path -Encoding utf8 -Force
}

Function _UpdateTaskMetadata
{
    param(
        [string] $Id,
        [string] $NameTag,
        [string] $FriendlyNameTag,
        [string] $Version
    )
    
    $path = Join-Path $buildPath 'task\task.json'
    $metadata = Get-Content $path -Raw | ConvertFrom-Json

    Write-Host "Updating task id to '${Id}'..."
    $metadata.id = $metadata.id -replace  '#{Task.Id}',$Id
    
    Write-Host "Adding tag '${NameTag}' to task name..."
    $metadata.name = $metadata.name -replace '#{IdTag}',$NameTag
    
    Write-Host "Adding tag '${FriendlyNameTag}' to task friendly name..."
    $metadata.friendlyName = $metadata.friendlyName -replace '#{NameTag}',$FriendlyNameTag
    
    Write-Host "Updating task version to '${Version}'..."
    $parsedVersion = [Version]::Parse($Version)
    $metadata.version.major = $parsedVersion.Major
    $metadata.version.minor = $parsedVersion.Minor
    $metadata.version.patch = $parsedVersion.Build
    
    Write-Host "Adding version to task help..."
    $metadata.helpMarkDown = $metadata.helpMarkDown -replace '#{Task.Version}',$Version
    
    Write-Host "Updating task file '${path}'..."
    ConvertTo-Json $metadata -Depth 20 | Out-File $path -Encoding utf8 -Force
}

Function _PublishExtension
{
    Write-Host "Publishing extension..."
    $arguments = @(
        'extension',
        'publish',
        '--root',$buildPath,
        '--output-path',$packagesPath
    )
    
    if ($publisher)
    {
        $arguments += @('--publisher',$publisher)
    }
    
    if ($token)
    {
        $arguments += @('--token',$token)
    }
    
    if ($shareWith)
    {
        $arguments += @('--share-with',$shareWith)
    }
    
    Exec { tfx $arguments }
}
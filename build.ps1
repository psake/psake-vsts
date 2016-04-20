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
    Write-Host "Copying folder 'docs'..."
    Copy-Item -Path (Join-Path $srcPath 'docs') -Destination (Join-Path $buildPath 'docs') -Recurse
    
    Write-Host "Copying folder 'images'..."
    Copy-Item -Path (Join-Path $srcPath 'images') -Destination (Join-Path $buildPath 'images') -Recurse
    
    Write-Host "Copying file 'LICENSE.txt'..."
    Copy-Item -Path (Join-Path $srcPath 'LICENSE.txt') -Destination $buildPath
    
    Write-Host "Copying file 'vss-extension.json'..."
    Copy-Item -Path (Join-Path $srcPath 'vss-extension.json') -Destination $buildPath
    
    # copy task files
    Write-Host "Copying folder 'task'..."
    Copy-Item -Path (Join-Path $srcPath 'task') -Destination (Join-Path $buildPath 'task') -Recurse
    
    # copy librairies files
    $libPath = Join-Path $srcPath 'node_modules\vsts-task-sdk\VstsTaskSdk'
    if (!(Test-Path $libPath))
    {
        throw "Directory '${libPath}' not found."
    }
    
    Write-Host "Copying library 'VstsTaskSdk'..."
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
    $manifestPath = Join-Path $srcPath 'vss-extension.json'
    $manifestData = Get-Content $manifestPath -Raw | ConvertFrom-Json

    $buildNumber =  "psake-extension_$($manifestData.version)+${env:BUILD_BUILDID}"
    Write-Host "Setting build number to '${buildNumber}'..."
    Write-Host "##vso[build.updatebuildnumber]${buildNumber}"
    Write-Host "##vso[task.setvariable variable=Extension.Version;]$($manifestData.version)"
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
    
    # update manifest
    _UpdateExtensionManifest -Tag 'dev' -Version $version
    _UpdateTaskManifest -Id '7011cf27-c181-443a-9f07-3e6ffea72b6b' -NameTag " (dev ${version})" -Version $version
    
    # publish extension
    _PublishExtension
}

Function _UpdateExtensionManifest
{
    param(
        [string] $Tag,
        [string] $Version,
        [switch] $Public
    )
    
    Write-Host "Updating extension manifest..."
    $manifestPath = Join-Path $buildPath 'vss-extension.json'
    $manifestData = Get-Content $manifestPath -Raw | ConvertFrom-Json
    
    if ($Tag)
    {
        Write-Host "Adding tag '${Tag}' to extension id..."
        $manifestData.id = "$($manifestData.id)-${Tag}"
    }
    
    Write-Host "Adding tag '${Tag}' to extension name..."
    $manifestData.name = $manifestData.name -replace '#{NameTag}'," (${Tag})"
    
    Write-Host "Updating extension version to '${Version}'..."
    $manifestData.version = $Version

    if (!$Public -and $manifestData.public)
    {
        Write-Host 'Removing extension public flag...'
        $manifestData = $manifestData | Select-Object -Property * -ExcludeProperty 'public'
    }
    
    if ($Public -and !$manifestData.public)
    {
        Write-Host 'Adding extension public flag...'
        Add-Member -InputObject $manifestData -NotePropertyName "public" -NotePropertyValue $true -Force
    }
    
    Write-Host "Updating extension file '${manifestPath}'..."
    ConvertTo-Json $manifestData -Depth 20 | Out-File $manifestPath -Encoding utf8 -Force
}

Function _UpdateTaskManifest
{
    param(
        [string] $Id,
        [string] $NameTag,
        [string] $Version
    )
    
    Write-Host "Updating task manifest..."
    $manifestPath = Join-Path $buildPath 'task\task.json'
    $manifestData = Get-Content $manifestPath -Raw | ConvertFrom-Json

    Write-Host "Updating task id to '${Id}'..."
    $manifestData.id = $manifestData.id -replace  '#{Task.Id}',$Id
        
    Write-Host "Adding tag '${NameTag}' to task friendly name..."
    $manifestData.friendlyName = $manifestData.friendlyName -replace '#{NameTag}',$NameTag
    
    Write-Host "Updating task version to '${Version}'..."
    $parsedVersion = [Version]::Parse($Version)
    $manifestData.version.major = $parsedVersion.Major
    $manifestData.version.minor = $parsedVersion.Minor
    $manifestData.version.patch = $parsedVersion.Build
    
    Write-Host "Adding version to task help..."
    $manifestData.helpMarkDown = $manifestData.helpMarkDown -replace '#{Task.Version}',$Version
    
    Write-Host "Updating task file '${manifestPath}'..."
    ConvertTo-Json $manifestData -Depth 20 | Out-File $manifestPath -Encoding utf8 -Force
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
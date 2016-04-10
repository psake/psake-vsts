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

Task PublishDev {
    # check for build directory
    if (!(Test-Path $buildPath))
    {
        throw "Directory '${buildPath}' not found."
    }
    
    # generate unique version
    $ref = New-Object DateTime 2000,1,1
    $now = [DateTime]::Now
    $major = 0
    $minor = $now.Subtract($ref).Days
    $patch = [Math]::Floor([Math]::Floor($now.TimeOfDay.TotalSeconds) * 0.5)
    $version = "${major}.${minor}.${patch}"
    
    # update extension metadata
    $extensionPath = Join-Path $buildPath 'vss-extension.json'
    $extensionMetadata = Get-Content $extensionPath -Raw | ConvertFrom-Json
    
    Write-Host "Adding tag '-dev' to extension id..."
    $extensionMetadata.id = $extensionMetadata.id -replace '#{IdTag}','-dev'
    
    Write-Host "Adding tag ' (dev)' to extension name..."
    $extensionMetadata.name = $extensionMetadata.name -replace '#{NameTag}',' (dev)'
    
    Write-Host "Updating extension version to '${version}'..."
    $extensionMetadata.version = $version

    if ($extensionMetadata.public)
    {
        Write-Host 'Removing extension public flag...'
        $extensionMetadata = $extensionMetadata | Select-Object -Property * -ExcludeProperty 'public'
    }
    
    Write-Host "Updating extension file '${extensionPath}'..."
    ConvertTo-Json $extensionMetadata -Depth 20 | Out-File $extensionPath -Encoding utf8 -Force
    
    # update task metadata
    $taskPath = Join-Path $buildPath 'task\task.json'
    $taskMetadata = Get-Content $taskPath -Raw | ConvertFrom-Json

    Write-Host "Updating task id to '7011cf27-c181-443a-9f07-3e6ffea72b6b'..."
    $taskMetadata.id = $taskMetadata.id -replace  '#{Task.Id}','7011cf27-c181-443a-9f07-3e6ffea72b6b'
    
    Write-Host "Adding tag '-dev' to task name..."
    $taskMetadata.name = $taskMetadata.name -replace '#{IdTag}','-dev'
    
    Write-Host "Adding tag ' (dev ${version})' to task friendly name..."
    $taskMetadata.friendlyName = $taskMetadata.friendlyName -replace '#{NameTag}'," (dev ${version})"
    
    Write-Host "Updating task version to '${version}'..."
    $taskMetadata.version.major = 0
    $taskMetadata.version.minor = $minor
    $taskMetadata.version.patch = $patch
    
    Write-Host "Adding version to task help..."
    $taskMetadata.helpMarkDown = $taskMetadata.helpMarkDown -replace '#{Task.Version}',$version
    
    Write-Host "Updating task file '${taskPath}'..."
    ConvertTo-Json $taskMetadata -Depth 20 | Out-File $taskPath -Encoding utf8 -Force
    
    # publish extension
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
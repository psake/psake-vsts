Properties {
    $overridableProperty = "default"
    $parameterizedProperty = "[${p1}] [${p2}] [${p3}] [${p4}]"
}

Task Default -Depends LogScript,LogFramework,LogProperties

Task LogScript {
    Write-Host "script: $($psake.build_script_file)"
}

Task LogFramework {
    Write-Host "framework: $($psake.context.peek().config.framework)"
}

Task LogProperties {
    Write-Host "overridableProperty ${overridableProperty}"
    Write-Host "parameterizedProperty: ${parameterizedProperty}"
}